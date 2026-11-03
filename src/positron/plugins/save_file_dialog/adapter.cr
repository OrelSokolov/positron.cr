require "json"

module Positron::Plugins
  # Platform-agnostic interface for the SaveFileDialog plugin.
  #
  # Each platform provides a thin adapter that shows the OS-native save dialog
  # and returns the selected target path (or `nil` if the user cancelled).
  abstract class SaveFileDialogAdapter
    # Open the save dialog pre-filled with `suggested_name`.
    #
    # `content` is the payload the caller wants to save. Desktop adapters
    # (GTK, AppKit, Win32) only return a path and let the plugin write the
    # file afterwards, so they may ignore `content`; system-picker
    # platforms where the OS performs the copy (iOS export mode) must
    # stage `content` BEFORE the picker is shown — see #writes_content?.
    #
    # Returns the path chosen by the user or `nil` if cancelled.
    abstract def save(suggested_name : String, content : String) : String?

    # Non-blocking variant — see FilePickerAdapter#pick(accept, &).
    # Overridden by callback-driven platforms (Android SAF).
    def save(suggested_name : String, content : String,
             &on_done : String? ->) : Nil
      on_done.call(save(suggested_name, content))
    end

    # True when #save has already persisted `content` to the returned
    # path (the OS picker performed the copy), so the plugin must not
    # write the file again. False by default.
    def writes_content? : Bool
      false
    end
  end
end
