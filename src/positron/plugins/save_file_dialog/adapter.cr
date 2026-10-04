require "json"

module Positron::Plugins
  # Platform-agnostic interface for the SaveFileDialog plugin.
  #
  # Each platform provides a thin adapter that shows the OS-native save dialog
  # and returns the selected target path (or `nil` if the user cancelled).
  abstract class SaveFileDialogAdapter
    # Open the save dialog pre-filled with `suggested_name`.
    #
    # Returns the path chosen by the user or `nil` if cancelled.
    abstract def save(suggested_name : String) : String?
  end
end
