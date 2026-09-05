require "json"
require "log"
require "./adapter"
require "./factory"

module CrystalUI::Plugins
  # Cross-platform save file dialog plugin.
  #
  # Exposes a single host-side command to the frontend:
  #   - save_file_dialog.save({ suggested_name, content })
  #
  # The command opens the OS-native save dialog and resolves immediately with
  # a pending status. The actual result is delivered back to JavaScript as a
  # reverse event:
  #   - save_file_dialog.saved  { path, name }
  #   - save_file_dialog.canceled  {}
  #   - save_file_dialog.error  { error }
  #
  # Platform adapters live in `src/crystal_ui/plugins/save_file_dialog/` and are
  # selected at compile time by `SaveFileDialogAdapterFactory`.
  class SaveFileDialog < CrystalUI::Plugin
    @adapter : SaveFileDialogAdapter

    def initialize
      @adapter = SaveFileDialogAdapterFactory.create
    end

    def name : String
      "save_file_dialog"
    end

    def supported_platforms : Array(Symbol)
      [:desktop, :android, :ios]
    end

    def manifest : Hash(String, CrystalUI::CommandManifest)
      {
        "save_file_dialog.save" => CrystalUI::CommandManifest.new(
          name: "save_file_dialog.save",
          args: [
            CrystalUI::ArgumentManifest.new(name: "suggested_name", type: "String"),
            CrystalUI::ArgumentManifest.new(name: "content", type: "String"),
          ],
          returns: "Object",
        ),
      }
    end

    def bind(registry : CrystalUI::CommandRegistry, state : CrystalUI::StateManager)
      registry.register("save_file_dialog.save") do |request|
        suggested_name = request.args["suggested_name"]?.try(&.as_s?) || ""
        content = request.args["content"]?.try(&.as_s?) || ""
        spawn { save_file(suggested_name, content) }

        CrystalUI::CommandResult.new(
          success: true,
          data: JSON.parse({status: "opened", suggested_name: suggested_name}.to_json)
        )
      end
    end

    private def save_file(suggested_name : String, content : String)
      host = self.host
      unless host
        Log.error { "save_file_dialog.save called before host was bound" }
        return
      end

      channel = Channel(String?).new

      host.run_on_main do
        begin
          channel.send(@adapter.save(suggested_name))
        rescue ex
          Log.error { "save_file_dialog adapter error: #{ex.message}" }
          channel.send(nil)
        end
      end

      path = channel.receive

      if path
        begin
          File.write(path, content)
          payload = {path: path, name: File.basename(path)}

          host.emit_to_js("save_file_dialog.saved", payload)
          CrystalUI::EventBus.emit("save_file_dialog.saved", payload)
        rescue ex
          payload = {error: ex.message}

          host.emit_to_js("save_file_dialog.error", payload)
          CrystalUI::EventBus.emit("save_file_dialog.error", payload)
        end
      else
        host.emit_to_js("save_file_dialog.canceled", {} of String => String)
        CrystalUI::EventBus.emit("save_file_dialog.canceled", {} of String => String)
      end
    end
  end
end
