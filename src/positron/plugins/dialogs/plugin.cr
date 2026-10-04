require "json"
require "log"
require "./adapter"
require "./factory"

module Positron::Plugins
  # Native dialogs & alerts plugin.
  #
  # Exposes to the frontend:
  #   - dialogs.alert(message, title?, kind?)    kind: "info"|"warning"|"error"
  #   - dialogs.confirm(message, title?)  → Bool
  #   - dialogs.prompt(message, default?, title?) → String | null
  #
  # All dialogs are modal and resolve the JS promise when the user
  # dismisses them. Platform adapters live in
  # `src/positron/plugins/dialogs/`.
  class Dialogs < Positron::Plugin
    @adapter : DialogsAdapter

    def initialize
      @adapter = DialogsAdapterFactory.create
    end

    def name : String
      "dialogs"
    end

    def supported_platforms : Array(Symbol)
      [:desktop]
    end

    def manifest : Hash(String, Positron::CommandManifest)
      {
        "dialogs.alert" => Positron::CommandManifest.new(
          name: "dialogs.alert",
          args: [
            Positron::ArgumentManifest.new(name: "message", type: "String"),
            Positron::ArgumentManifest.new(name: "title", type: "String"),
            Positron::ArgumentManifest.new(name: "kind", type: "String"),
          ],
        ),
        "dialogs.confirm" => Positron::CommandManifest.new(
          name: "dialogs.confirm",
          args: [
            Positron::ArgumentManifest.new(name: "message", type: "String"),
            Positron::ArgumentManifest.new(name: "title", type: "String"),
          ],
          returns: "Bool",
        ),
        "dialogs.prompt" => Positron::CommandManifest.new(
          name: "dialogs.prompt",
          args: [
            Positron::ArgumentManifest.new(name: "message", type: "String"),
            Positron::ArgumentManifest.new(name: "default", type: "String"),
            Positron::ArgumentManifest.new(name: "title", type: "String"),
          ],
          returns: "String",
        ),
      }
    end

    def bind(registry : Positron::CommandRegistry, state : Positron::StateManager)
      registry.register("dialogs.alert") do |request|
        message = str(request.args, "message")
        title = str(request.args, "title")
        kind = str(request.args, "kind")

        on_main do
          @adapter.alert(message, title, kind)
        end

        Positron::CommandResult.new(success: true, data: JSON.parse("{}"))
      end

      registry.register("dialogs.confirm") do |request|
        message = str(request.args, "message")
        title = str(request.args, "title")

        confirmed = on_main { @adapter.confirm(message, title) }

        Positron::CommandResult.new(
          success: true,
          data: JSON.parse(confirmed.to_json)
        )
      end

      registry.register("dialogs.prompt") do |request|
        message = str(request.args, "message")
        default = str(request.args, "default")
        title = str(request.args, "title")

        text = on_main { @adapter.prompt(message, default, title) }

        Positron::CommandResult.new(
          success: true,
          data: text.nil? ? JSON.parse("null") : JSON.parse(text.to_json)
        )
      end
    end

    # Run a dialog on the GUI thread and wait for its result. Command
    # handlers may execute on non-main fibers; the channel parks this
    # fiber while the nested GTK main loop shows the dialog.
    private def on_main(&block : -> T) forall T
      channel = Channel(T).new(1)
      host.try(&.run_on_main { channel.send(block.call) }) || channel.send(block.call)
      channel.receive
    end

    private def str(args : JSON::Any, key : String) : String
      args[key]?.try(&.as_s?) || ""
    end
  end
end
