require "log"
require "./adapter"
require "../../adapters/macos/objc"

module Positron::Plugins
  # macOS save file dialog adapter using NSSavePanel, driven through
  # the pure-Crystal ObjC runtime layer. Must run on the main/AppKit
  # thread; the plugin marshals calls there via `Host#run_on_main`.
  class MacOSSaveFileDialogAdapter < SaveFileDialogAdapter
    OBJC = Positron::Adapters::MacOS::ObjC
    App  = Positron::Adapters::MacOS::App

    NS_MODAL_RESPONSE_OK = 1

    def save(suggested_name : String) : String?
      OBJC.with_autorelease_pool do
        App.ensure_app

        panel = OBJC.send0(OBJC.cls("NSSavePanel"), OBJC.sel("savePanel"))
        OBJC.send1(panel, OBJC.sel("setTitle:"), OBJC.nsstr("Save file"))
        unless suggested_name.empty?
          OBJC.send1(panel, OBJC.sel("setNameFieldStringValue:"), OBJC.nsstr(suggested_name))
        end

        App.activate!
        result = OBJC.send0_i(panel, OBJC.sel("runModal"))
        next nil unless result == NS_MODAL_RESPONSE_OK

        url = OBJC.send0(panel, OBJC.sel("URL"))
        next nil if url.null?

        OBJC.to_s(OBJC.send0(url, OBJC.sel("path")))
      end
    end
  end
end
