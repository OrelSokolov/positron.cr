require "log"
require "./adapter"
require "../../adapters/macos/objc"

module Positron::Plugins
  # macOS file picker adapter using NSOpenPanel, driven through the
  # pure-Crystal ObjC runtime layer. Must run on the main/AppKit
  # thread; the plugin marshals calls there via `Host#run_on_main`.
  class MacOSFilePickerAdapter < FilePickerAdapter
    OBJC = Positron::Adapters::MacOS::ObjC
    App  = Positron::Adapters::MacOS::App

    NS_MODAL_RESPONSE_OK = 1

    # Common MIME types → file extensions, for the `accept` filter.
    MIME_EXTENSIONS = {
      "text/plain"        => ["txt"],
      "text/*"            => ["txt", "md"],
      "text/markdown"     => ["md"],
      "image/*"           => ["png", "jpg", "jpeg", "gif", "webp", "tiff"],
      "image/png"         => ["png"],
      "image/jpeg"        => ["jpg", "jpeg"],
      "image/gif"         => ["gif"],
      "image/webp"        => ["webp"],
      "image/tiff"        => ["tiff"],
      "application/json"  => ["json"],
    }

    def pick(accept : String) : String?
      OBJC.with_autorelease_pool do
        App.ensure_app

        panel = OBJC.send0(OBJC.cls("NSOpenPanel"), OBJC.sel("openPanel"))
        OBJC.send1(panel, OBJC.sel("setTitle:"), OBJC.nsstr("Select a file"))
        OBJC.send1(panel, OBJC.sel("setCanChooseFiles:"), OBJC.bool_arg(true))
        OBJC.send1(panel, OBJC.sel("setCanChooseDirectories:"), OBJC.bool_arg(false))
        OBJC.send1(panel, OBJC.sel("setAllowsMultipleSelection:"), OBJC.bool_arg(false))

        extensions = self.class.extensions_for(accept)
        unless extensions.empty?
          OBJC.send1(panel, OBJC.sel("setAllowedFileTypes:"), nsarray_of_strings(extensions))
        end

        App.activate!
        result = OBJC.send0_i(panel, OBJC.sel("runModal"))
        next nil unless result == NS_MODAL_RESPONSE_OK

        url = OBJC.send0(OBJC.send0(panel, OBJC.sel("URLs")), OBJC.sel("firstObject"))
        next nil if url.null?

        OBJC.to_s(OBJC.send0(url, OBJC.sel("path")))
      end
    end

    # --- Internals ---

    # Translates an HTML <input type="file"> accept attribute into file
    # extensions (".txt,.md" → ["txt","md"], "image/*" → common image
    # types). "*" and an empty value mean no filtering. Exposed for specs.
    def self.extensions_for(accept : String) : Array(String)
      extensions = [] of String
      accept.split(",").each do |raw|
        item = raw.strip.downcase
        next if item.empty? || item == "*"

        if item.starts_with?('.')
          extensions << item[1..] unless item.size == 1
        else
          MIME_EXTENSIONS[item]?.try { |list| extensions.concat(list) }
        end
      end
      extensions.uniq
    end

    private def nsarray_of_strings(strings : Array(String)) : Void*
      array = OBJC.send0(OBJC.cls("NSMutableArray"), OBJC.sel("array"))
      strings.each do |string|
        OBJC.send1(array, OBJC.sel("addObject:"), OBJC.nsstr(string))
      end
      array
    end
  end
end
