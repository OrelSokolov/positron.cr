require "base64"
require "log"
require "./adapter"
require "../../adapters/ios/objc"

module Positron::Plugins
  # iOS clipboard adapter backed by UIPasteboard (the general
  # pasteboard), driven through the pure-Crystal ObjC runtime layer.
  # iOS has no file entries on the pasteboard — `has_files?` /
  # `read_files` report empty, like the Android adapter.
  class IOSClipboardAdapter < ClipboardAdapter
    ObjC = Positron::Adapters::IOS::ObjC

    def read_text : String?
      ObjC.with_autorelease_pool do
        ObjC.to_s(ObjC.send0(pasteboard, ObjC.sel("string")))
      end
    end

    def read_image : {mime: String, data: Bytes}?
      ObjC.with_autorelease_pool do
        image = ObjC.send0(pasteboard, ObjC.sel("image"))
        next nil if image.null?

        data = LibUIImage.UIImagePNGRepresentation(image)
        next nil if data.null?

        length = ObjC.send0_i(data, ObjC.sel("length"))
        next nil if length <= 0

        bytes = Bytes.new(ObjC.send0(data, ObjC.sel("bytes")).as(UInt8*), length)
        {mime: "image/png", data: bytes.dup}
      end
    end

    def read_files : Array(String)
      [] of String
    end

    def has_text? : Bool
      ObjC.with_autorelease_pool { ObjC.send0_b(pasteboard, ObjC.sel("hasStrings")) }
    end

    def has_image? : Bool
      ObjC.with_autorelease_pool { ObjC.send0_b(pasteboard, ObjC.sel("hasImages")) }
    end

    def has_files? : Bool
      false
    end

    def write_text(text : String) : Bool
      ObjC.with_autorelease_pool do
        ObjC.send1(pasteboard, ObjC.sel("setString:"), ObjC.nsstr(text))
        true
      end
    end

    def write_image(base64 : String, mime : String) : Bool
      bytes = Base64.decode(base64)
      ObjC.with_autorelease_pool do
        data = ObjC.nsdata(bytes)
        image = ObjC.send1(ObjC.cls("UIImage"), ObjC.sel("imageWithData:"), data)
        next false if image.null?
        ObjC.send1(pasteboard, ObjC.sel("setImage:"), image)
        true
      end
    end

    # --- Internals ---

    private def pasteboard : Void*
      ObjC.send0(ObjC.cls("UIPasteboard"), ObjC.sel("generalPasteboard"))
    end

    # Plain C function (not a method) — new symbol, no clash with the
    # one-fun-per-C-symbol rule.
    lib LibUIImage
      fun UIImagePNGRepresentation(image : Void*) : Void*
    end
  end
end
