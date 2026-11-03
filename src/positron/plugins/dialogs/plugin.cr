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
      [:desktop, :android]
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

        confirmed = ask(false) do |channel|
          @adapter.confirm(message, title) { |ok| channel.send(ok) }
        end

        Positron::CommandResult.new(
          success: true,
          data: JSON.parse(confirmed.to_json)
        )
      end

      registry.register("dialogs.prompt") do |request|
        message = str(request.args, "message")
        default = str(request.args, "default")
        title = str(request.args, "title")

        text = ask(nil.as(String?)) do |channel|
          @adapter.prompt(message, default, title) { |value| channel.send(value) }
        end

        Positron::CommandResult.new(
          success: true,
          data: text.nil? ? JSON.parse("null") : JSON.parse(text.to_json)
        )
      end
    end

    # Run a dialog on the GUI thread and wait for its result. Command
    # handlers may execute on non-main fibers; the channel parks this
    # fiber while the nested GTK main loop shows the dialog (blocking
    # desktop adapters), or — on callback platforms like Android —
    # until the OS delivers the answer through the shim event queue.
    private def on_main(&block : -> T) forall T
      channel = Channel(T).new(1)
      host.try(&.run_on_main { channel.send(block.call) }) || channel.send(block.call)
      channel.receive
    end

    # Start an async adapter call on the GUI fiber (or the current
    # fiber when no host is bound — specs) and park this fiber until
    # the adapter's callback resolves. On adapter errors the channel
    # receives `fallback`.
    private def ask(fallback : T, &start : Channel(T) ->) : T forall T
      channel = Channel(T).new(1)
      if h = host
        h.run_on_main do
          begin
            start.call(channel)
          rescue ex
            Log.error { "dialogs adapter error: #{ex.message}" }
            channel.send(fallback)
          end
        end
      else
        begin
          start.call(channel)
        rescue ex
          Log.error { "dialogs adapter error: #{ex.message}" }
          channel.send(fallback)
        end
      end
      channel.receive
    end

    private def str(args : JSON::Any, key : String) : String
      args[key]?.try(&.as_s?) || ""
    end
  end
end
