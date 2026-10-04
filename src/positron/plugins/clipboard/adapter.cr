require "json"

module Positron::Plugins
  # Platform-agnostic interface for the Clipboard plugin.
  #
  # Each platform provides a thin adapter that reads from and writes to the
  # OS-native clipboard. The Crystal Host decides what to do with the data.
  abstract class ClipboardAdapter
    # Read plain text from the clipboard. Returns `nil` if no text is available.
    abstract def read_text : String?

    # Read an image from the clipboard. Returns `nil` if no image is available.
    #
    # The returned tuple contains the MIME type and the raw binary data.
    abstract def read_image : {mime: String, data: Bytes}?

    # Read file URIs from the clipboard. Returns an empty array if none.
    abstract def read_files : Array(String)

    # Returns true if the clipboard currently contains text.
    abstract def has_text? : Bool

    # Returns true if the clipboard currently contains an image.
    abstract def has_image? : Bool

    # Returns true if the clipboard currently contains file URIs.
    abstract def has_files? : Bool

    # Write plain text to the clipboard.
    abstract def write_text(text : String) : Bool

    # Write an image to the clipboard from a base64-encoded string.
    abstract def write_image(base64 : String, mime : String) : Bool
  end
end
