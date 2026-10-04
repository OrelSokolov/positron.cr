require "base64"
require "./adapter"
require "../../adapters/macos/objc"

module Positron::Plugins
  # macOS clipboard adapter backed by NSPasteboard (the general
  # pasteboard), driven through the pure-Crystal ObjC runtime layer.
  class MacOSClipboardAdapter < ClipboardAdapter
    OBJC = Positron::Adapters::MacOS::ObjC

    # UTI identifiers for the pasteboard types we read/write.
    TYPE_STRING  = "public.utf8-plain-text"
    TYPE_FILE_URL = "public.file-url"
    TYPE_PNG     = "public.png"
    TYPE_TIFF    = "public.tiff"

    def read_text : String?
      OBJC.with_autorelease_pool do
        OBJC.to_s(OBJC.send1(pasteboard, OBJC.sel("stringForType:"), OBJC.nsstr(TYPE_STRING)))
      end
    end

    def read_image : {mime: String, data: Bytes}?
      OBJC.with_autorelease_pool do
        [{TYPE_PNG, "image/png"}, {TYPE_TIFF, "image/tiff"}].each do |(type, mime)|
          data = OBJC.send1(pasteboard, OBJC.sel("dataForType:"), OBJC.nsstr(type))
          next if data.null?

          length = OBJC.send0_i(data, OBJC.sel("length"))
          next if length <= 0

          bytes = Bytes.new(OBJC.send0(data, OBJC.sel("bytes")).as(UInt8*), length)
          return {mime: mime, data: bytes.dup}
        end
        nil
      end
    end

    def read_files : Array(String)
      OBJC.with_autorelease_pool do
        classes = OBJC.send1(OBJC.cls("NSArray"), OBJC.sel("arrayWithObject:"), OBJC.cls("NSURL"))
        objects = OBJC.send2(pasteboard, OBJC.sel("readObjectsForClasses:options:"),
          classes, Pointer(Void).null)

        files = [] of String
        unless objects.null?
          OBJC.send0_i(objects, OBJC.sel("count")).times do |i|
            url = OBJC.send1(objects, OBJC.sel("objectAtIndex:"), OBJC.int_arg(i))
            path = OBJC.to_s(OBJC.send0(url, OBJC.sel("path")))
            files << path if path && !path.empty?
          end
        end
        files
      end
    end

    def has_text? : Bool
      has_type?(TYPE_STRING)
    end

    def has_image? : Bool
      has_type?(TYPE_PNG) || has_type?(TYPE_TIFF)
    end

    def has_files? : Bool
      has_type?(TYPE_FILE_URL)
    end

    def write_text(text : String) : Bool
      OBJC.with_autorelease_pool do
        write_object(OBJC.nsstr(text))
      end
    end

    def write_image(base64 : String, mime : String) : Bool
      bytes = Base64.decode(base64)
      type = mime.includes?("tiff") ? TYPE_TIFF : TYPE_PNG
      # Raw PNG/TIFF bytes go onto the pasteboard through an
      # NSPasteboardItem — no NSImage round-trip needed.
      OBJC.with_autorelease_pool do
        data = OBJC.nsdata(bytes)
        item = OBJC.send0(OBJC.cls("NSPasteboardItem"), OBJC.sel("new"))
        ok = OBJC.send2_b(item, OBJC.sel("setData:forType:"), data, OBJC.nsstr(type))
        next false unless ok
        write_object(item)
      end
    end

    # --- Internals ---

    private def pasteboard : Void*
      OBJC.send0(OBJC.cls("NSPasteboard"), OBJC.sel("generalPasteboard"))
    end

    # Clears the pasteboard and writes a single NSPasteboardWriting
    # object (NSString or NSImage); returns whether it was accepted.
    private def write_object(object : Void*) : Bool
      paste = pasteboard
      OBJC.send0(paste, OBJC.sel("clearContents"))
      array = OBJC.send1(OBJC.cls("NSArray"), OBJC.sel("arrayWithObject:"), object)
      OBJC.send1_i(paste, OBJC.sel("writeObjects:"), array) > 0
    end

    private def has_type?(type : String) : Bool
      types = OBJC.send0(pasteboard, OBJC.sel("types"))
      return false if types.null?
      OBJC.send1_b(types, OBJC.sel("containsObject:"), OBJC.nsstr(type))
    end
  end
end
