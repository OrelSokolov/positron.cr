require "log"
require "./adapter"
require "../../adapters/macos/objc"

module Positron::Plugins
  # macOS dialogs adapter built on NSAlert (plus an NSTextField accessory
  # view for prompt).
  #
  # All calls must run on the main/AppKit thread; the plugin marshals
  # them there via `Host#run_on_main` (see plugins/dialogs/plugin.cr).
  class MacOSDialogsAdapter < DialogsAdapter
    OBJC = Positron::Adapters::MacOS::ObjC
    App = Positron::Adapters::MacOS::App

    # NSAlertStyle: 0 informational, 1 warning, 2 critical.
    NS_ALERT_STYLE_WARNING = 1
    NS_ALERT_STYLE_CRITICAL = 2

    # NSModalResponseOK — the return of runModal for the first
    # (default) button; later buttons return NSAlertSecondButtonReturn
    # (1001) and up.
    NS_MODAL_RESPONSE_OK = 1

    def alert(message : String, title : String, kind : String) : Nil
      OBJC.with_autorelease_pool do
        dialog = new_alert(title)
        style = case kind
                when "warning" then NS_ALERT_STYLE_WARNING
                when "error"   then NS_ALERT_STYLE_CRITICAL
                else                0
                end
        OBJC.send1(dialog, OBJC.sel("setAlertStyle:"), OBJC.int_arg(style))
        OBJC.send1(dialog, OBJC.sel("setMessageText:"), OBJC.nsstr(message))
        OBJC.send1(dialog, OBJC.sel("addButtonWithTitle:"), OBJC.nsstr("OK"))

        App.activate!
        OBJC.send0(dialog, OBJC.sel("runModal"))
      end
    end

    def confirm(message : String, title : String) : Bool
      OBJC.with_autorelease_pool do
        dialog = new_alert(title)
        OBJC.send1(dialog, OBJC.sel("setMessageText:"), OBJC.nsstr(message))
        OBJC.send1(dialog, OBJC.sel("addButtonWithTitle:"), OBJC.nsstr("OK"))
        OBJC.send1(dialog, OBJC.sel("addButtonWithTitle:"), OBJC.nsstr("Cancel"))

        App.activate!
        OBJC.send0_i(dialog, OBJC.sel("runModal")) == NS_MODAL_RESPONSE_OK
      end
    end

    def prompt(message : String, default : String, title : String) : String?
      OBJC.with_autorelease_pool do
        dialog = new_alert(title)
        OBJC.send1(dialog, OBJC.sel("setMessageText:"), OBJC.nsstr(message))

        field = OBJC.invoke_rect3(
          OBJC.send0(OBJC.cls("NSTextField"), OBJC.sel("alloc")),
          "initWithFrame:",
          Positron::Adapters::MacOS::LibObjC::NSRect.new(
            origin: Positron::Adapters::MacOS::LibObjC::NSPoint.new(x: 0.0, y: 0.0),
            size: Positron::Adapters::MacOS::LibObjC::NSSize.new(width: 280.0, height: 24.0)))
        OBJC.send1(field, OBJC.sel("setStringValue:"), OBJC.nsstr(default)) unless default.empty?
        OBJC.send1(dialog, OBJC.sel("setAccessoryView:"), field)

        OBJC.send1(dialog, OBJC.sel("addButtonWithTitle:"), OBJC.nsstr("OK"))
        OBJC.send1(dialog, OBJC.sel("addButtonWithTitle:"), OBJC.nsstr("Cancel"))

        App.activate!
        result = OBJC.send0_i(dialog, OBJC.sel("runModal"))
        next nil unless result == NS_MODAL_RESPONSE_OK

        OBJC.to_s(OBJC.send0(field, OBJC.sel("stringValue")))
      end
    end

    # --- Internals ---

    private def new_alert(title : String) : Void*
      App.ensure_app
      dialog = OBJC.send0(OBJC.send0(OBJC.cls("NSAlert"), OBJC.sel("alloc")), OBJC.sel("init"))
      unless title.empty?
        OBJC.send1(OBJC.send0(dialog, OBJC.sel("window")), OBJC.sel("setTitle:"), OBJC.nsstr(title))
      end
      dialog
    end
  end
end
