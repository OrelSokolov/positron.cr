require "log"
require "./adapter"
require "../../adapters/ios/objc"

module Positron::Plugins
  # Foundation C entry points used by the adapter below (new symbols —
  # no clash with the one-fun-per-C-symbol rule).
  lib LibFoundation
    fun NSTemporaryDirectory : UInt8*
  end

  # iOS save file dialog adapter: `UIDocumentPickerViewController` in
  # export mode, driven through the pure-Crystal ObjC runtime layer
  # (`Adapters::IOS::ObjC` — no hand-rolled objc_msgSend).
  #
  # The content is staged into a temp file before the picker is shown;
  # `initForExportingURLs:asCopy:YES` has the system copy that file to
  # the destination the user picks, so #writes_content? is true and the
  # plugin must not write the returned path again (it usually lives in
  # another container the sandbox would deny).
  #
  # Blocking model: the plugin calls #save on the main thread (via
  # `Host#run_on_main`), but UIKit's picker is callback-based — #save
  # spins a nested default-mode run loop until the delegate IMP fires.
  # The fiber timer lives in common modes (default included), so Crystal
  # fibers and the JS bridge keep running while the picker is up — the
  # same nesting the macOS adapter enters with `NSSavePanel runModal`.
  class IOSSaveFileDialogAdapter < SaveFileDialogAdapter
    ObjC = Positron::Adapters::IOS::ObjC

    STATE_PENDING   = 0
    STATE_PICKED    = 1
    STATE_CANCELLED = 2

    @delegate : Void*?
    @showing = false

    # Written by the delegate IMPs (main thread) and read by #save's
    # nested run loop — same thread, no synchronization needed. The IMPs
    # must not capture closures, so the shared state lives in class vars.
    @@state : Int32 = STATE_PENDING
    @@picked_url : Void* = Pointer(Void).null

    # Assigned inside #build_delegate (the egui.cr pattern: proc
    # literals assigned in class-body initializers hit a scoping quirk
    # of the patched iOS Crystal — locals of the block are not visible).
    @@pick_imp : Proc(Void*, Void*, Void*, Void*, Nil)?
    @@cancel_imp : Proc(Void*, Void*, Void*, Nil)?

    def writes_content? : Bool
      true
    end

    def save(suggested_name : String, content : String) : String?
      if @showing
        Log.warn { "save_file_dialog: a picker is already up" }
        return nil
      end

      webview = Positron::Host.current.try(&.app.webview)
      unless webview.is_a?(Positron::Adapters::IOS::WKWebView)
        Log.error { "save_file_dialog: no booted iOS webview to present the picker from" }
        return nil
      end

      ObjC.with_autorelease_pool do
        # Stage the content — the export picker copies this file.
        suggested = File.basename(suggested_name.empty? ? "Untitled.txt" : suggested_name)
        tmp_dir = ObjC.to_s(LibFoundation.NSTemporaryDirectory.as(Void*)) || "/tmp"
        tmp_path = File.join(tmp_dir, "positron-save-#{suggested}")
        File.write(tmp_path, content)

        @@state = STATE_PENDING
        @@picked_url = Pointer(Void).null

        url = ObjC.send1(ObjC.cls("NSURL"), ObjC.sel("fileURLWithPath:"), ObjC.nsstr(tmp_path))
        urls = ObjC.send1(ObjC.cls("NSArray"), ObjC.sel("arrayWithObject:"), url)
        picker = ObjC.send2(
          ObjC.send0(ObjC.cls("UIDocumentPickerViewController"), ObjC.sel("alloc")),
          ObjC.sel("initForExportingURLs:asCopy:"), urls, ObjC.bool_arg(true))
        ObjC.send1(picker, ObjC.sel("setDelegate:"), build_delegate)

        @showing = true
        begin
          if webview.present_modal(picker)
            run_until_done
          else
            Log.error { "save_file_dialog: could not present the picker" }
          end
        ensure
          @showing = false
        end

        begin
          case @@state
          when STATE_PICKED
            path = ObjC.to_s(ObjC.send0(@@picked_url, ObjC.sel("path")))
            Positron::Adapters::IOS::LibCF.CFRelease(@@picked_url)
            @@picked_url = Pointer(Void).null
            path
          else
            nil
          end
        ensure
          # asCopy:YES already moved the bytes for the picked case; the
          # staging file is dropped either way.
          File.delete(tmp_path) if File.exists?(tmp_path)
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

      objc_class = ObjC.new_class("PositronDocumentPickerDelegate")
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
