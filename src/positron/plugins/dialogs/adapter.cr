module Positron::Plugins
  # Platform adapter contract for native dialogs (alert / confirm / prompt).
  abstract class DialogsAdapter
    # kind: "info" | "warning" | "error"
    abstract def alert(message : String, title : String, kind : String) : Nil
    abstract def confirm(message : String, title : String) : Bool
    # Returns the entered text, or nil when the user cancelled.
    abstract def prompt(message : String, default : String, title : String) : String?

    # Non-blocking variants — see FilePickerAdapter#pick(accept, &).
    # Overridden by callback-driven platforms (Android: the dialog runs
    # on the OS UI thread; the answer arrives through the shim event
    # queue). `alert` needs no callback form — it is fire-and-forget.
    def confirm(message : String, title : String, &on_done : Bool ->) : Nil
      on_done.call(confirm(message, title))
    end

    def prompt(message : String, default : String, title : String,
               &on_done : String? ->) : Nil
      on_done.call(prompt(message, default, title))
    end
  end
end
