require "json"

module Positron::Plugins
  # Platform-agnostic interface for the FilePicker plugin.
  #
  # Each platform provides a thin adapter that shows the OS-native file picker
  # and returns the selected path (or `nil` if the user cancelled).
  abstract class FilePickerAdapter
    # Open the file picker filtered by `accept`.
    #
    # `accept` follows the HTML `<input type="file">` convention, e.g.:
    #   ".txt", ".txt,.md", "text/plain".
    #
    # Returns the selected file path or `nil` if cancelled.
    abstract def pick(accept : String) : String?

    # Common MIME types → file extensions, for the `accept` filter.
    # Shared by the platform adapters (macOS NSOpenPanel, iOS
    # UIDocumentPickerViewController).
    MIME_EXTENSIONS = {
      "text/plain"       => ["txt"],
      "text/*"           => ["txt", "md"],
      "text/markdown"    => ["md"],
      "image/*"          => ["png", "jpg", "jpeg", "gif", "webp", "tiff"],
      "image/png"        => ["png"],
      "image/jpeg"       => ["jpg", "jpeg"],
      "image/gif"        => ["gif"],
      "image/webp"       => ["webp"],
      "image/tiff"       => ["tiff"],
      "application/json" => ["json"],
    }

    # Translates an HTML <input type="file"> accept attribute into file
    # extensions (".txt,.md" → ["txt","md"], "image/*" → common image
    # types). "*" and an empty value mean no filtering. Unknown MIME
    # types are dropped. Exposed for specs.
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
  end
end
