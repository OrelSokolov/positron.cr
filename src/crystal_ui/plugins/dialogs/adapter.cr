module CrystalUI::Plugins
  # Platform adapter contract for native dialogs (alert / confirm / prompt).
  abstract class DialogsAdapter
    # kind: "info" | "warning" | "error"
    abstract def alert(message : String, title : String, kind : String) : Nil
    abstract def confirm(message : String, title : String) : Bool
    # Returns the entered text, or nil when the user cancelled.
    abstract def prompt(message : String, default : String, title : String) : String?
  end
end
