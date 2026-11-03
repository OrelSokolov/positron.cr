require "log"
require "./adapter"
require "../../adapters/ios/objc"

module Positron::Plugins
  # iOS file picker adapter: `UIDocumentPickerViewController` in opening
  # mode (`initForOpeningContentTypes:asCopy:`), driven through the
  # pure-Crystal ObjC runtime layer (`Adapters::IOS::ObjC` — no
  # hand-rolled objc_msgSend).
  #
  # `asCopy:YES` has the system copy the picked file into the app
  # container, so the returned path is directly readable — no
  # security-scoped resource bookkeeping (the original lives in the
  # file provider's container, which the sandbox would deny).
  #
  # Blocking model: the plugin calls #pick on the main thread (via
  # `Host#run_on_main`), but UIKit's picker is callback-based — #pick
  # spins a nested default-mode run loop until the delegate IMP fires.
  # The fiber timer lives in common modes (default included), so Crystal
  # fibers and the JS bridge keep running while the picker is up — the
  # same nesting the save dialog adapter enters
  # (`IOSSaveFileDialogAdapter`).
  class IOSFilePickerAdapter < FilePickerAdapter
    ObjC = Positron::Adapters::IOS::ObjC

    STATE_PENDING   = 0
    STATE_PICKED    = 1
    STATE_CANCELLED = 2

    # Distinct from the save dialog adapter's delegate class name so an
    # app using both plugins gets independent delegates — the shared
    # state below lives in *this* adapter's class vars.
    DELEGATE_CLASS = "PositronDocumentPickerOpenDelegate"

    @delegate : Void*?
    @showing = false

    # Written by the delegate IMPs (main thread) and read by #pick's
    # nested run loop — same thread, no synchronization needed. The IMPs
    # must not capture closures, so the shared state lives in class vars.
    @@state : Int32 = STATE_PENDING
    @@picked_url : Void* = Pointer(Void).null

    # Assigned inside #build_delegate (the egui.cr pattern: proc
    # literals assigned in class-body initializers hit a scoping quirk
    # of the patched iOS Crystal — locals of the block are not visible).
    @@pick_imp : Proc(Void*, Void*, Void*, Void*, Nil)?
    @@cancel_imp : Proc(Void*, Void*, Void*, Nil)?

    def pick(accept : String) : String?
      if @showing
        Log.warn { "file_picker: a picker is already up" }
        return nil
      end

      webview = Positron::Host.current.try(&.app.webview)
      unless webview.is_a?(Positron::Adapters::IOS::WKWebView)
        Log.error { "file_picker: no booted iOS webview to present the picker from" }
        return nil
      end

      ObjC.with_autorelease_pool do
        @@state = STATE_PENDING
        @@picked_url = Pointer(Void).null

        picker = ObjC.send2(
          ObjC.send0(ObjC.cls("UIDocumentPickerViewController"), ObjC.sel("alloc")),
          ObjC.sel("initForOpeningContentTypes:asCopy:"),
          content_types(accept), ObjC.bool_arg(true))
        ObjC.send1(picker, ObjC.sel("setDelegate:"), build_delegate)

        @showing = true
        begin
          if webview.present_modal(picker)
            run_until_done
          else
            Log.error { "file_picker: could not present the picker" }
          end
        ensure
          @showing = false
        end

        case @@state
        when STATE_PICKED
          path = ObjC.to_s(ObjC.send0(@@picked_url, ObjC.sel("path")))
          Positron::Adapters::IOS::LibCF.CFRelease(@@picked_url)
          @@picked_url = Pointer(Void).null
          path
        else
          nil
        end
      end
    end

    # --- Internals ---

    # Nested default-mode run loop: processes exactly one run-loop
    # source per pass, then re-checks the delegate state. Blocks until
    # the user confirms or cancels the picker.
    private def run_until_done : Nil
      run_loop = ObjC.send0(ObjC.cls("NSRunLoop"), ObjC.sel("mainRunLoop"))
      mode = ObjC.nsstr("kCFRunLoopDefaultMode")
      distant_future = ObjC.send0(ObjC.cls("NSDate"), ObjC.sel("distantFuture"))
      while @@state == STATE_PENDING
        ObjC.send2(run_loop, ObjC.sel("runMode:beforeDate:"), mode, distant_future)
      end
    end

    # Translates the `accept` filter into a UTType array for
    # initForOpeningContentTypes:. With no recognizable filter the
    # picker falls back to UTType.data — the base type of virtually
    # every file — because an empty array would leave nothing
    # selectable.
    private def content_types(accept : String) : Void*
      uttype = ObjC.cls("UTType")
      array = ObjC.send0(ObjC.cls("NSMutableArray"), ObjC.sel("array"))
      FilePickerAdapter.extensions_for(accept).each do |ext|
        type = ObjC.send1(uttype, ObjC.sel("typeWithFilenameExtension:"), ObjC.nsstr(ext))
        unless type.null?
          ObjC.send1(array, ObjC.sel("addObject:"), type)
        end
      end
      if ObjC.send0_i(array, ObjC.sel("count")) == 0
        fallback = ObjC.send0(uttype, ObjC.sel("data"))
        if fallback.null?
          fallback = ObjC.send1(uttype, ObjC.sel("typeWithIdentifier:"), ObjC.nsstr("public.data"))
        end
        ObjC.send1(array, ObjC.sel("addObject:"), fallback) unless fallback.null?
      end
      array
    end

    private def build_delegate : Void*
      @@pick_imp = ->(_objc_self : Void*, _cmd : Void*, picker : Void*, urls : Void*) {
        first = ObjC.send0(urls, ObjC.sel("firstObject"))
        unless first.null?
          # Retain past the autorelease scope of the picker machinery.
          # (A didPick callback with an empty array does not happen in
          # practice; cancellation arrives via documentPickerWasCancelled:.)
          @@picked_url = Positron::Adapters::IOS::LibCF.CFRetain(first)
          @@state = STATE_PICKED
        end
      }

      @@cancel_imp = ->(_objc_self : Void*, _cmd : Void*, picker : Void*) {
        @@state = STATE_CANCELLED
      }

      objc_class = ObjC.new_class(DELEGATE_CLASS)
      ObjC.add_protocol(objc_class, "UIDocumentPickerDelegate")
      Adapters::IOS::LibObjC.class_addMethod(
        objc_class,
        ObjC.sel("documentPicker:didPickDocumentsAtURLs:"),
        @@pick_imp.not_nil!.pointer.as(Void*), "v@:@@")
      Adapters::IOS::LibObjC.class_addMethod(
        objc_class,
        ObjC.sel("documentPickerWasCancelled:"),
        @@cancel_imp.not_nil!.pointer.as(Void*), "v@:@")
      delegate = ObjC.send0(objc_class, ObjC.sel("new"))
      # The picker's delegate property is weak (UIKit convention) — the
      # adapter keeps it alive.
      @delegate = delegate
      delegate
    end
  end
end
