require "json"
require "log"
require "./adapter"
require "./factory"

module CrystalUI::Plugins
  # Cross-platform file picker plugin.
  #
  # Exposes a single host-side command to the frontend:
  #   - file_picker.pick(accept)
  #
  # The command opens the OS-native file picker and resolves immediately with
  # a pending status. The actual selection is delivered back to JavaScript as a
  # reverse event:
  #   - file_picker.selected  { path, name, content }
  #   - file_picker.canceled  {}
  #   - file_picker.error     { error }
  #
  # Platform adapters live in `src/crystal_ui/plugins/file_picker/` and are
  # selected at compile time by `FilePickerAdapterFactory`.
  class FilePicker < CrystalUI::Plugin
    @adapter : FilePickerAdapter

    def initialize
      @adapter = FilePickerAdapterFactory.create
    end

    def name : String
      "file_picker"
    end

    def supported_platforms : Array(Symbol)
      [:desktop, :android, :ios]
    end

    def manifest : Hash(String, CrystalUI::CommandManifest)
      {
        "file_picker.pick" => CrystalUI::CommandManifest.new(
          name: "file_picker.pick",
          args: [
            CrystalUI::ArgumentManifest.new(name: "accept", type: "String"),
          ],
          returns: "Object",
        ),
      }
    end

    def bind(registry : CrystalUI::CommandRegistry, state : CrystalUI::StateManager)
      registry.register("file_picker.pick") do |request|
        accept = request.args["accept"]?.try(&.as_s?) || ".txt"
        spawn { open_file(accept) }

        CrystalUI::CommandResult.new(
          success: true,
          data: JSON.parse({status: "opened", accept: accept}.to_json)
        )
      end
    end

    private def open_file(accept : String)
      host = self.host
      unless host
        Log.error { "file_picker.pick called before host was bound" }
        return
      end

      channel = Channel(String?).new

      host.run_on_main do
        begin
          channel.send(@adapter.pick(accept))
        rescue ex
          Log.error { "file_picker adapter error: #{ex.message}" }
          channel.send(nil)
        end
      end

      path = channel.receive

      if path
        begin
          content = File.read(path).scrub
          payload = {path: path, name: File.basename(path), content: content}

          host.emit_to_js("file_picker.selected", payload)
          CrystalUI::EventBus.emit("file_picker.selected", payload)
        rescue ex
          payload = {error: ex.message}

          host.emit_to_js("file_picker.error", payload)
          CrystalUI::EventBus.emit("file_picker.error", payload)
        end
      else
        host.emit_to_js("file_picker.canceled", {} of String => String)
        CrystalUI::EventBus.emit("file_picker.canceled", {} of String => String)
      end
    end
  end
end
