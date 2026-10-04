require "log"
require "uri"
require "./win32"

module Positron
  module Adapters
    module Windows
      # Minimal COM plumbing for the WebView2 interfaces the webview.dll
      # C API does not expose.
      #
      # `webview_get_native_handle(w, BROWSER_CONTROLLER)` returns the
      # ICoreWebView2Controller* created by webview.dll. From there the
      # standard COM vtable calls reach:
      #   - ICoreWebView2::AddWebResourceRequestedFilter +
      #     add_WebResourceRequested — intercept requests to virtual
      #     https://<scheme>.positron.local/* hosts and answer them from
      #     the host process (the WebView2 equivalent of WebKitGTK's
      #     register_uri_scheme; see WebViewPort#register_uri_scheme).
      #   - ICoreWebView2Environment::CreateWebResourceResponse — build
      #     the interception response from an in-memory IStream.
      #
      # COM interfaces are immutable contracts, so the vtable slot numbers
      # below are stable across WebView2 runtime versions.
      module WebView2Com
        Log = ::Log.for("positron.adapters.webview2.com")

        # --- vtable slots (0-based; 0-2 are IUnknown) ---
        CONTROLLER_GET_CORE_WEBVIEW2 = 25 # ICoreWebView2Controller
        CORE_ADD_WEBRESOURCE_REQUESTED = 55 # ICoreWebView2
        CORE_ADD_WEBRESOURCE_REQUESTED_FILTER = 57
        CORE2_GET_ENVIRONMENT = 67 # ICoreWebView2_2
        ENV_CREATE_WEBRESOURCE_RESPONSE = 4 # ICoreWebView2Environment
        ARGS_GET_REQUEST   = 3 # ICoreWebView2WebResourceRequestedEventArgs
        ARGS_PUT_RESPONSE  = 5
        REQUEST_GET_URI    = 3 # ICoreWebView2WebResourceRequest
        STREAM_RELEASE     = 2 # IStream (IUnknown)

        RESOURCE_CONTEXT_ALL = 0_u32

        # GUIDs in memory layout (little-endian first three fields).
        # NOTE: these must stay Slices — a constant holding only
        # `.to_unsafe` loses the GC root on the backing buffer and the
        # bytes get collected (observed as flaky QI failures).
        # {0xA0D6DF20,0x3B92,0x416D,{0xAA,0x0C,0x43,0x7A,0x9C,0x72,0x78,0x57}}
        # QI for ICoreWebView2_2 ({0x9E8F0CF8,...}) was observed failing on
        # the current runtime while _3/_4 succeed; _3 inherits _2's vtable
        # (including get_Environment), so it is the safe entry point.
        IID_COREWEBVIEW2_3 = Bytes[
          0x20_u8, 0xDF, 0xD6, 0xA0, 0x92, 0x3B, 0x6D, 0x41,
          0xAA, 0x0C, 0x43, 0x7A, 0x9C, 0x72, 0x78, 0x57,
        ]

        # IUnknown {00000000-0000-0000-C000-000000000046}
        IID_IUNKNOWN = Bytes[
          0x00_u8, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
          0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46,
        ]

        # {0xAB00B74C,0x15F1,0x4646,{0x80,0xE8,0xE7,0x63,0x41,0xD2,0x5D,0x71}}
        IID_WEBRESOURCE_REQUESTED_HANDLER = Bytes[
          0x4C_u8, 0xB7, 0x00, 0xAB, 0xF1, 0x15, 0x46, 0x46,
          0x80, 0xE8, 0xE7, 0x63, 0x41, 0xD2, 0x5D, 0x71,
        ]

        @[Link("ole32")]
        lib LibOle32
          fun CoTaskMemFree(p : Void*)
        end

        @[Link("shlwapi")]
        lib LibShlwapi
          # Builds an IStream over a memory buffer (the data is copied by
          # the shell stream implementation).
          fun SHCreateMemStream(data : UInt8*, len : UInt32) : Void*
        end

        # --- raw vtable helpers ---

        private def self.slot(ptr : Void*, index : Int32) : Void*
          vtbl = ptr.as(Pointer(Void*)).value
          (vtbl.as(Pointer(Void*)) + index).value
        end

        private def self.guid_matches(riid : UInt8*, guid : Bytes) : Bool
          16.times { |i| return false unless riid[i] == guid[i] }
          true
        end

        def self.query_interface(ptr : Void*, iid : Bytes) : Void*?
          out_ptr = Pointer(Void*).malloc(1)
          fn = slot(ptr, 0)
          qi = Proc(Void*, UInt8*, Void**, Int32).new(fn, Pointer(Void).null)
          hr = qi.call(ptr, iid.to_unsafe, out_ptr)
          hr >= 0 ? out_ptr.value : nil
        end

        def self.core_webview2(controller : Void*) : Void*?
          out_ptr = Pointer(Void*).malloc(1)
          fn = slot(controller, CONTROLLER_GET_CORE_WEBVIEW2)
          m = Proc(Void*, Void**, Int32).new(fn, Pointer(Void).null)
          m.call(controller, out_ptr) >= 0 ? out_ptr.value : nil
        end

        # ICoreWebView2 -> (QI ICoreWebView2_3, inherits _2) -> ICoreWebView2Environment
        def self.environment(core : Void*) : Void*?
          core3 = query_interface(core, IID_COREWEBVIEW2_3)
          if core3.nil?
            Log.warn { "environment: QI to ICoreWebView2_3 failed" }
            return nil
          end
          out_ptr = Pointer(Void*).malloc(1)
          fn = slot(core3, CORE2_GET_ENVIRONMENT)
          m = Proc(Void*, Void**, Int32).new(fn, Pointer(Void).null)
          hr = m.call(core3, out_ptr)
          if hr < 0 || out_ptr.value.null?
            Log.warn { "environment: get_Environment hr=#{hr}" }
            return nil
          end
          out_ptr.value
        end

        # --- the WebResourceRequested interception ---

        # The COM handler object is two raw pointers: [vtable, box]. The
        # reference count is a static 1 — the object lives as long as the
        # process (WebView2 keeps handlers for the controller lifetime
        # anyway). @@objects keeps the allocation from being collected.
        class_property objects = [] of Void*

        QI_FN = ->(this : Void*, riid : UInt8*, ppv : Void**) : Int32 do
          if guid_matches(riid, IID_IUNKNOWN) ||
             guid_matches(riid, IID_WEBRESOURCE_REQUESTED_HANDLER)
            ppv.value = this
            0
          else
            ppv.value = Pointer(Void).null
            0x80004002_u32.to_i32! # E_NOINTERFACE
          end
        end

        ADDREF_FN  = ->(this : Void*) : UInt32 { 1_u32 }
        RELEASE_FN = ->(this : Void*) : UInt32 { 1_u32 }

        INVOKE_FN = ->(this : Void*, sender : Void*, args : Void*) : Int32 do
          box = (this.as(Pointer(Void*)) + 1).value
          adapter = Box(WebView2).unbox(box)
          adapter.handle_webresource_request(args)
          0
        rescue ex
          Log.error { "WebResourceRequested handler: #{ex.message}" }
          0
        end

        @@vtbl : Void*?

        private def self.handler_vtbl : Void*
          @@vtbl ||= begin
            vtbl = Pointer(Void*).malloc(4)
            vtbl[0] = QI_FN.pointer.as(Void*)
            vtbl[1] = ADDREF_FN.pointer.as(Void*)
            vtbl[2] = RELEASE_FN.pointer.as(Void*)
            vtbl[3] = INVOKE_FN.pointer.as(Void*)
            vtbl.as(Void*)
          end
        end

        # Installs the interception for one virtual host:
        # handler first, then the filter (never miss an event).
        def self.install(core : Void*, adapter : WebView2, vhost_pattern : String) : Bool
          obj = Pointer(Void*).malloc(2)
          obj[0] = handler_vtbl
          obj[1] = Box.box(adapter)
          objects << obj.as(Void*)
          handler = obj.as(Void*)

          token = Pointer(UInt64).malloc(1)
          fn = slot(core, CORE_ADD_WEBRESOURCE_REQUESTED)
          add = Proc(Void*, Void*, UInt64*, Int32).new(fn, Pointer(Void).null)
          hr = add.call(core, handler, token)
          if hr < 0
            Log.warn { "add_WebResourceRequested hr=#{hr}" }
            return false
          end

          pattern = Win32.wstr(vhost_pattern)
          fn2 = slot(core, CORE_ADD_WEBRESOURCE_REQUESTED_FILTER)
          filter = Proc(Void*, UInt16*, UInt32, Int32).new(fn2, Pointer(Void).null)
          hr2 = filter.call(core, pattern.to_unsafe, RESOURCE_CONTEXT_ALL)
          if hr2 < 0
            Log.warn { "AddWebResourceRequestedFilter(#{vhost_pattern}) hr=#{hr2}" }
            return false
          end
          true
        end

        # --- called by the adapter from INVOKE_FN (UI thread) ---

        def self.request_uri(args : Void*) : String?
          out_ptr = Pointer(Void*).malloc(1)
          fn = slot(args, ARGS_GET_REQUEST)
          get_request = Proc(Void*, Void**, Int32).new(fn, Pointer(Void).null)
          return nil unless get_request.call(args, out_ptr) >= 0

          uri_out = Pointer(UInt16*).malloc(1)
          fn2 = slot(out_ptr.value, REQUEST_GET_URI)
          get_uri = Proc(Void*, UInt16**, Int32).new(fn2, Pointer(Void).null)
          return nil unless get_uri.call(out_ptr.value, uri_out) >= 0

          uri = Win32.wstr_back(uri_out.value)
          LibOle32.CoTaskMemFree(uri_out.value.as(Void*))
          uri
        end

        def self.respond(args : Void*, env : Void*, bytes : Bytes?, mime_type : String, status : Int32, reason : String) : Nil
          stream =
            if bytes && bytes.size > 0
              LibShlwapi.SHCreateMemStream(bytes.to_unsafe, bytes.size.to_u32!)
            else
              Pointer(Void).null
            end

          content = Win32.wstr("Content-Type: #{mime_type}")
          reason_w = Win32.wstr(reason)
          resp = Pointer(Void*).malloc(1)
          fn = slot(env, ENV_CREATE_WEBRESOURCE_RESPONSE)
          create = Proc(Void*, Void*, Int32, UInt16*, UInt16*, Void**, Int32).new(fn, Pointer(Void).null)
          hr = create.call(env, stream, status, reason_w.to_unsafe, content.to_unsafe, resp)
          if hr < 0
            Log.warn { "CreateWebResourceResponse hr=#{hr}" }
          else
            fn2 = slot(args, ARGS_PUT_RESPONSE)
            put = Proc(Void*, Void*, Int32).new(fn2, Pointer(Void).null)
            put.call(args, resp.value)
          end

          # WebView2 holds its own reference once the response is set.
          release_stream(stream) unless stream.null?
        end

        private def self.release_stream(stream : Void*) : Nil
          fn = slot(stream, STREAM_RELEASE)
          rel = Proc(Void*, UInt32).new(fn, Pointer(Void).null)
          rel.call(stream)
        end
      end
    end
  end
end
