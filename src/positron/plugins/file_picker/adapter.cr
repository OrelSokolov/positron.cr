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
  end
end
