require "./adapter"

module CrystalUI::Plugins
  # Linux native dialogs adapter built on GtkMessageDialog.
  #
  # All calls must run on the GTK main thread; the plugin marshals them
  # there via `Host#run_on_main`.
  class LinuxDialogsAdapter < DialogsAdapter
    GTK_DIALOG_MODAL = 1 << 0

    GTK_MESSAGE_INFO    = 0
    GTK_MESSAGE_WARNING = 1
    GTK_MESSAGE_ERROR   = 3

    GTK_BUTTONS_OK        = 0
    GTK_BUTTONS_OK_CANCEL = 4

    GTK_RESPONSE_OK     = -5
    GTK_RESPONSE_CANCEL = -6

    def alert(message : String, title : String, kind : String) : Nil
      type = case kind
             when "warning" then GTK_MESSAGE_WARNING
             when "error"   then GTK_MESSAGE_ERROR
             else                GTK_MESSAGE_INFO
             end

      dialog = LibGTK.gtk_message_dialog_new(
        Pointer(Void).null,           # no parent window
        GTK_DIALOG_MODAL,
        type,
        GTK_BUTTONS_OK,
        "%s",
        message.to_unsafe.as(LibC::Char*)
      )
      LibGTK.gtk_window_set_title(dialog, title) unless title.empty?
      LibGTK.gtk_dialog_run(dialog)
      LibGTK.gtk_widget_destroy(dialog)
    end

    def confirm(message : String, title : String) : Bool
      dialog = LibGTK.gtk_message_dialog_new(
        Pointer(Void).null,
        GTK_DIALOG_MODAL,
        GTK_MESSAGE_INFO,
        GTK_BUTTONS_OK_CANCEL,
        "%s",
        message.to_unsafe.as(LibC::Char*)
      )
      LibGTK.gtk_window_set_title(dialog, title) unless title.empty?
      response = LibGTK.gtk_dialog_run(dialog)
      LibGTK.gtk_widget_destroy(dialog)
      response == GTK_RESPONSE_OK
    end

    def prompt(message : String, default : String, title : String) : String?
      dialog = LibGTK.gtk_message_dialog_new(
        Pointer(Void).null,
        GTK_DIALOG_MODAL,
        GTK_MESSAGE_INFO,
        GTK_BUTTONS_OK_CANCEL,
        "%s",
        message.to_unsafe.as(LibC::Char*)
      )
      LibGTK.gtk_window_set_title(dialog, title) unless title.empty?

      entry = LibGTK.gtk_entry_new
      LibGTK.gtk_entry_set_text(entry, default) unless default.empty?
      content_area = LibGTK.gtk_dialog_get_content_area(dialog)
      LibGTK.gtk_box_pack_start(content_area, entry, 1, 1, 0)

      LibGTK.gtk_widget_show(entry)
      response = LibGTK.gtk_dialog_run(dialog)

      result = nil
      if response == GTK_RESPONSE_OK
        text = LibGTK.gtk_entry_get_text(entry)
        result = String.new(text)
      end

      LibGTK.gtk_widget_destroy(dialog)
      result
    end

    # Local FFI surface. Declared here (not shared) per the project
    # convention: adapters own their bindings.
    @[Link("gtk-3")]
    lib LibGTK
      fun gtk_message_dialog_new(parent : Void*, flags : Int32, message_type : Int32, buttons : Int32, message_format : LibC::Char*, ...) : Void*
      fun gtk_dialog_run(dialog : Void*) : Int32
      fun gtk_dialog_get_content_area(dialog : Void*) : Void*
      fun gtk_window_set_title(window : Void*, title : LibC::Char*)
      fun gtk_widget_show(widget : Void*)
      fun gtk_widget_destroy(widget : Void*)
      fun gtk_entry_new : Void*
      fun gtk_entry_set_text(entry : Void*, text : LibC::Char*)
      fun gtk_entry_get_text(entry : Void*) : LibC::Char*
      fun gtk_box_pack_start(box : Void*, child : Void*, expand : Int32, fill : Int32, padding : Int32)
    end
  end
end
