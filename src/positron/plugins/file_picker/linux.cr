require "./adapter"

module Positron::Plugins
  # Linux implementation of the FilePicker plugin using GTK 3.
  #
  # This is a thin FFI wrapper: the Crystal Host drives the dialog,
  # GTK just renders the native file chooser and returns the selection.
  class LinuxFilePickerAdapter < FilePickerAdapter
    def pick(accept : String) : String?
      dialog = LibGTK.gtk_file_chooser_dialog_new(
        "Select a file",
        Pointer(Void).null,
        LibGTK::GTK_FILE_CHOOSER_ACTION_OPEN,
        Pointer(LibC::Char).null
      )

      LibGTK.gtk_dialog_add_button(dialog, "_Cancel", LibGTK::GTK_RESPONSE_CANCEL)
      LibGTK.gtk_dialog_add_button(dialog, "_Open", LibGTK::GTK_RESPONSE_ACCEPT)

      add_text_filter(dialog) if accepts_text?(accept)

      response = LibGTK.gtk_dialog_run(dialog)
      path = nil

      if response == LibGTK::GTK_RESPONSE_ACCEPT
        filename = LibGTK.gtk_file_chooser_get_filename(dialog)
        unless filename.null?
          path = String.new(filename)
          LibPositronGLib.g_free(filename.as(Void*))
        end
      end

      LibGTK.gtk_widget_destroy(dialog)
      path
    end

    private def accepts_text?(accept : String) : Bool
      accept == "*" ||
        accept.includes?(".txt") ||
        accept.includes?("text/plain") ||
        accept.includes?("text/*")
    end

    private def add_text_filter(dialog : Void*)
      filter = LibGTK.gtk_file_filter_new
      LibGTK.gtk_file_filter_set_name(filter, "Text files")
      LibGTK.gtk_file_filter_add_pattern(filter, "*.txt")
      LibGTK.gtk_file_chooser_add_filter(dialog, filter)
    end

    @[Link("glib-2.0")]
    lib LibPositronGLib
      fun g_free(mem : Void*)
    end

    @[Link("gtk-3")]
    lib LibGTK
      GTK_FILE_CHOOSER_ACTION_OPEN =  0
      GTK_RESPONSE_CANCEL          = -6
      GTK_RESPONSE_ACCEPT          = -3

      fun gtk_file_chooser_dialog_new(
        title : LibC::Char*,
        parent : Void*,
        action : Int32,
        first_button_text : LibC::Char*,
        ...
      ) : Void*

      fun gtk_dialog_add_button(dialog : Void*, button_text : LibC::Char*, response_id : Int32) : Void*
      fun gtk_dialog_run(dialog : Void*) : Int32
      fun gtk_file_chooser_get_filename(chooser : Void*) : LibC::Char*
      fun gtk_file_chooser_add_filter(chooser : Void*, filter : Void*)
      fun gtk_file_filter_new : Void*
      fun gtk_file_filter_set_name(filter : Void*, name : LibC::Char*)
      fun gtk_file_filter_add_pattern(filter : Void*, pattern : LibC::Char*)
      fun gtk_widget_destroy(widget : Void*)
    end
  end
end
