require "log"
require "base64"
require "./adapter"

module CrystalUI::Plugins
  # Linux implementation of the Clipboard plugin using GTK/GDK.
  #
  # Reads plain text, images and file URIs from the GTK clipboard.
  # Images are converted to PNG so the host can pass them to the frontend as
  # base64 data URIs.
  class LinuxClipboardAdapter < ClipboardAdapter
    def read_text : String?
      clipboard = default_clipboard
      ptr = LibGTK.gtk_clipboard_wait_for_text(clipboard)
      return nil if ptr.null?

      text = String.new(ptr)
      LibGLib.g_free(ptr.as(Void*))
      text
    end

    def read_image : {mime: String, data: Bytes}?
      clipboard = default_clipboard
      pixbuf = LibGTK.gtk_clipboard_wait_for_image(clipboard)
      return nil if pixbuf.null?

      buffer_ptr = Pointer(LibC::Char).null
      size : LibC::SizeT = 0

      ok = LibGdkPixbuf.gdk_pixbuf_save_to_buffer(
        pixbuf,
        pointerof(buffer_ptr),
        pointerof(size),
        "png",
        nil,
        nil
      )

      return nil if ok == 0 || buffer_ptr.null?

      # Copy the buffer before freeing it.
      data = Bytes.new(buffer_ptr.as(UInt8*), size).dup
      LibGLib.g_free(buffer_ptr.as(Void*))

      {mime: "image/png", data: data}
    end

    def read_files : Array(String)
      clipboard = default_clipboard
      uris_ptr = LibGTK.gtk_clipboard_wait_for_uris(clipboard)
      return [] of String if uris_ptr.null?

      files = [] of String
      i = 0
      loop do
        uri_ptr = uris_ptr[i]
        break if uri_ptr.null?
        files << String.new(uri_ptr)
        i += 1
      end

      LibGLib.g_free(uris_ptr.as(Void*))
      files
    end

    def has_text? : Bool
      LibGTK.gtk_clipboard_wait_is_text_available(default_clipboard) != 0
    end

    def has_image? : Bool
      LibGTK.gtk_clipboard_wait_is_image_available(default_clipboard) != 0
    end

    def has_files? : Bool
      LibGTK.gtk_clipboard_wait_is_uris_available(default_clipboard) != 0
    end

    def write_text(text : String) : Bool
      clipboard = default_clipboard
      LibGTK.gtk_clipboard_set_text(clipboard, text, text.bytesize)
      LibGTK.gtk_clipboard_store(clipboard)
      true
    end

    def write_image(base64 : String, mime : String) : Bool
      Log.for("crystalui.plugins.clipboard").warn { "Writing images to the clipboard is not yet implemented on Linux" }
      false
    end

    private def default_clipboard : Void*
      atom = LibGDK.gdk_atom_intern("CLIPBOARD", 0)
      LibGTK.gtk_clipboard_get(atom)
    end

    @[Link("gtk-3")]
    lib LibGTK
      fun gtk_clipboard_get(selection : Void*) : Void*
      fun gtk_clipboard_wait_for_text(clipboard : Void*) : LibC::Char*
      fun gtk_clipboard_wait_for_image(clipboard : Void*) : Void*
      fun gtk_clipboard_wait_for_uris(clipboard : Void*) : LibC::Char**
      fun gtk_clipboard_wait_is_text_available(clipboard : Void*) : Int32
      fun gtk_clipboard_wait_is_image_available(clipboard : Void*) : Int32
      fun gtk_clipboard_wait_is_uris_available(clipboard : Void*) : Int32
      fun gtk_clipboard_set_text(clipboard : Void*, text : LibC::Char*, len : Int32)
      fun gtk_clipboard_store(clipboard : Void*)
    end

    @[Link("gdk-3")]
    lib LibGDK
      fun gdk_atom_intern(atom_name : LibC::Char*, only_if_exists : Int32) : Void*
    end

    @[Link("gdk_pixbuf-2.0")]
    lib LibGdkPixbuf
      fun gdk_pixbuf_save_to_buffer(
        pixbuf : Void*,
        buffer : LibC::Char**,
        buffer_size : LibC::SizeT*,
        type : LibC::Char*,
        error : Void**,
        ...
      ) : Int32
    end

    @[Link("glib-2.0")]
    lib LibGLib
      fun g_free(mem : Void*)
    end
  end
end
