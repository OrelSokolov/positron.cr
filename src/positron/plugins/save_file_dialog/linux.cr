require "./adapter"

module Positron::Plugins
  # Linux implementation of the SaveFileDialog plugin using GTK 3.
  #
  # This is a thin FFI wrapper: the Crystal Host drives the dialog,
  # GTK just renders the native save chooser and returns the target path.
  class LinuxSaveFileDialogAdapter < SaveFileDialogAdapter
    def save(suggested_name : String) : String?
      dialog = LibGTK.gtk_file_chooser_dialog_new(
        "Save file",
        Pointer(Void).null,
        LibGTK::GTK_FILE_CHOOSER_ACTION_SAVE,
        Pointer(LibC::Char).null
      )

      LibGTK.gtk_dialog_add_button(dialog, "_Cancel", LibGTK::GTK_RESPONSE_CANCEL)
      LibGTK.gtk_dialog_add_button(dialog, "_Save", LibGTK::GTK_RESPONSE_ACCEPT)

      unless suggested_name.empty?
        LibGTK.gtk_file_chooser_set_current_name(dialog, suggested_name)
      end

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

    @[Link("glib-2.0")]
    lib LibPositronGLib
      fun g_free(mem : Void*)
    end

    @[Link("gtk-3")]
    lib LibGTK
      GTK_FILE_CHOOSER_ACTION_SAVE =  1
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
      fun gtk_file_chooser_set_current_name(chooser : Void*, name : LibC::Char*)
      fun gtk_widget_destroy(widget : Void*)
    end
  end
end
