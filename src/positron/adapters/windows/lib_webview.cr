require "log"
require "./win32"

module Positron
  module Adapters
    module Windows
      # Runtime loader for the vendored `webview.dll` (webview project,
      # version 0.12.0 — see third_party/webview/webview.h for the ABI).
      #
      # The library is loaded dynamically (LoadLibraryW/GetProcAddress) so no
      # import library is needed at link time. The DLL is searched, in order:
      #
      #   1. $POSITRON_WEBVIEW_DLL
      #   2. next to the running executable
      #   3. third_party/webview/webview.dll relative to the executable
      #      (several levels up — covers examples/<name>/ and bin/ layouts)
      #   4. the regular DLL search path (PATH)
      module LibWebview
        class Error < ::Exception; end

        alias WebviewT = Void*

        # Window size hints (webview_hint_t).
        HINT_NONE   = 0
        HINT_MIN    = 1
        HINT_MAX    = 2
        HINT_FIXED  = 3

        # webview_get_native_handle kinds.
        HANDLE_KIND_UI_WINDOW          = 0
        HANDLE_KIND_UI_WIDGET          = 1
        HANDLE_KIND_BROWSER_CONTROLLER = 2

        @@handle : Void*?
        @@create : Proc(Int32, Void*, Void*)?
        @@destroy : Proc(Void*, Int32)?
        @@run : Proc(Void*, Int32)?
        @@terminate : Proc(Void*, Int32)?
        @@dispatch : Proc(Void*, Void*, Void*, Int32)?
        @@get_native_handle : Proc(Void*, Int32, Void*)?
        @@set_title : Proc(Void*, UInt8*, Int32)?
        @@set_size : Proc(Void*, Int32, Int32, Int32, Int32)?
        @@navigate : Proc(Void*, UInt8*, Int32)?
        @@set_html : Proc(Void*, UInt8*, Int32)?
        @@init : Proc(Void*, UInt8*, Int32)?
        @@eval : Proc(Void*, UInt8*, Int32)?
        @@bind : Proc(Void*, UInt8*, Void*, Void*, Int32)?
        @@unbind : Proc(Void*, UInt8*, Int32)?
        @@return_result : Proc(Void*, UInt8*, Int32, UInt8*, Int32)?
        @@version : Proc(Void*)?

        DLL_NAME     = "webview.dll"
        VENDOR_RELS  = {"third_party/webview/webview.dll",
                        "../third_party/webview/webview.dll",
                        "../../third_party/webview/webview.dll",
                        "../../../third_party/webview/webview.dll"}

        def self.loaded? : Bool
          !@@handle.nil?
        end

        def self.load! : Nil
          return if loaded?

          path = resolve_dll_path
          handle =
            if path
              Win32::LibKernel32.LoadLibraryW(Win32.wstr(path).to_unsafe)
            else
              # Fall back to the regular DLL search path; pass the bare name
              # as UTF-16 as well.
              Win32::LibKernel32.LoadLibraryW(Win32.wstr(DLL_NAME).to_unsafe)
            end

          if handle.null?
            raise Error.new(
              "webview.dll not found — place it next to the executable or set " \
              "POSITRON_WEBVIEW_DLL (vendored copy: third_party/webview/webview.dll)")
          end

          @@create = bind_fn(handle, "webview_create", Proc(Int32, Void*, Void*))
          @@destroy = bind_fn(handle, "webview_destroy", Proc(Void*, Int32))
          @@run = bind_fn(handle, "webview_run", Proc(Void*, Int32))
          @@terminate = bind_fn(handle, "webview_terminate", Proc(Void*, Int32))
          @@dispatch = bind_fn(handle, "webview_dispatch", Proc(Void*, Void*, Void*, Int32))
          @@get_native_handle = bind_fn(handle, "webview_get_native_handle", Proc(Void*, Int32, Void*))
          @@set_title = bind_fn(handle, "webview_set_title", Proc(Void*, UInt8*, Int32))
          @@set_size = bind_fn(handle, "webview_set_size", Proc(Void*, Int32, Int32, Int32, Int32))
          @@navigate = bind_fn(handle, "webview_navigate", Proc(Void*, UInt8*, Int32))
          @@set_html = bind_fn(handle, "webview_set_html", Proc(Void*, UInt8*, Int32))
          @@init = bind_fn(handle, "webview_init", Proc(Void*, UInt8*, Int32))
          @@eval = bind_fn(handle, "webview_eval", Proc(Void*, UInt8*, Int32))
          @@bind = bind_fn(handle, "webview_bind", Proc(Void*, UInt8*, Void*, Void*, Int32))
          @@unbind = bind_fn(handle, "webview_unbind", Proc(Void*, UInt8*, Int32))
          @@return_result = bind_fn(handle, "webview_return", Proc(Void*, UInt8*, Int32, UInt8*, Int32))
          @@version = bind_fn(handle, "webview_version", Proc(Void*))
          @@handle = handle
        end

        def self.create(debug : Int32, window : Void* = Pointer(Void).null) : WebviewT
          @@create.not_nil!.call(debug, window)
        end

        def self.destroy(w : WebviewT) : Int32
          @@destroy.not_nil!.call(w)
        end

        def self.run(w : WebviewT) : Int32
          @@run.not_nil!.call(w)
        end

        def self.terminate(w : WebviewT) : Int32
          @@terminate.not_nil!.call(w)
        end

        def self.dispatch(w : WebviewT, fn : Void*, arg : Void*) : Int32
          @@dispatch.not_nil!.call(w, fn, arg)
        end

        def self.get_native_handle(w : WebviewT, kind : Int32) : Void*
          @@get_native_handle.not_nil!.call(w, kind)
        end

        def self.set_title(w : WebviewT, title : String) : Int32
          @@set_title.not_nil!.call(w, title.to_unsafe)
        end

        def self.set_size(w : WebviewT, width : Int32, height : Int32, hints : Int32) : Int32
          @@set_size.not_nil!.call(w, width, height, hints)
        end

        def self.navigate(w : WebviewT, url : String) : Int32
          @@navigate.not_nil!.call(w, url.to_unsafe)
        end

        def self.set_html(w : WebviewT, html : String) : Int32
          @@set_html.not_nil!.call(w, html.to_unsafe)
        end

        def self.init(w : WebviewT, js : String) : Int32
          @@init.not_nil!.call(w, js.to_unsafe)
        end

        def self.eval(w : WebviewT, js : String) : Int32
          @@eval.not_nil!.call(w, js.to_unsafe)
        end

        def self.bind(w : WebviewT, name : String, fn : Void*, arg : Void*) : Int32
          @@bind.not_nil!.call(w, name.to_unsafe, fn, arg)
        end

        def self.unbind(w : WebviewT, name : String) : Int32
          @@unbind.not_nil!.call(w, name.to_unsafe)
        end

        def self.return_result(w : WebviewT, id : UInt8*, status : Int32, result : String) : Int32
          @@return_result.not_nil!.call(w, id, status, result.to_unsafe)
        end

        # "MAJOR.MINOR.PATCH" of the loaded library (for doctor/diagnostics).
        def self.version_string : String
          load!
          info = @@version.not_nil!.call # webview_version_info_t: 3 uints then char[32]
          String.new(info.as(UInt8*) + 12)
        end

        private def self.bind_fn(handle : Void*, name : String, type)
          ptr = Win32::LibKernel32.GetProcAddress(handle, name.to_unsafe)
          raise Error.new("webview.dll: missing export #{name}") if ptr.null?
          type.new(ptr, Pointer(Void).null)
        end

        private def self.resolve_dll_path : String?
          if env = ENV["POSITRON_WEBVIEW_DLL"]?
            return File.exists?(env) ? env : nil
          end

          dir = Process.executable_path.try { |p| File.dirname(p) }
          candidates = [] of String
          if dir
            candidates << File.join(dir, DLL_NAME)
            VENDOR_RELS.each { |rel| candidates << File.expand_path(rel, dir) }
          end
          VENDOR_RELS.each { |rel| candidates << File.expand_path(rel, Dir.current) }

          candidates.find { |c| File.exists?(c) }
        end
      end
    end
  end
end
