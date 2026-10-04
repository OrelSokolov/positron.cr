require "json"

module Positron::Plugins
  # App lifecycle plugin.
  #
  # Formalizes the `lifecycle.*` event stream and exposes the current
  # state to the frontend:
  #   - lifecycle.get_state() → "resumed" | "paused"
  #
  # Events forwarded to JS (subscribe with Positron.on):
  #   - lifecycle.resumed   (window focused / app brought to front)
  #   - lifecycle.paused    (window lost focus)
  #   - lifecycle.destroyed (host shutting down)
  #
  # The host already maps `window.focused`/`window.blurred` to
  # Application#on_lifecycle; this plugin mirrors the same transitions to
  # the frontend and tracks the current state.
  class Lifecycle < Positron::Plugin
    @state = "resumed"

    def name : String
      "lifecycle"
    end

    def supported_platforms : Array(Symbol)
      [:desktop, :android, :ios]
    end

    def state : Hash(String, JSON::Any)
      {"state" => JSON::Any.new(@state)}
    end

    def manifest : Hash(String, Positron::CommandManifest)
      {
        "lifecycle.get_state" => Positron::CommandManifest.new(
          name: "lifecycle.get_state",
          returns: "String",
        ),
      }
    end

    def bind(registry : Positron::CommandRegistry, state : Positron::StateManager)
      registry.register("lifecycle.get_state") do |_request|
        Positron::CommandResult.new(
          success: true,
          data: JSON.parse(@state.to_json)
        )
      end
    end

    def on_ready(host : Positron::DesktopHost)
      Positron::EventBus.on("window.focused") do |_payload|
        transition("resumed", host)
      end

      Positron::EventBus.on("window.blurred") do |_payload|
        transition("paused", host)
      end

      Positron::EventBus.on("app.quitting") do |_payload|
        @state = "destroyed"
        host.emit_to_js("lifecycle.destroyed", {} of String => JSON::Any)
      end
    end

    private def transition(new_state : String, host : Positron::DesktopHost)
      return if @state == new_state
      @state = new_state
      set_state("state", new_state)
      host.emit_to_js("lifecycle.#{"resumed" == new_state ? "resumed" : "paused"}", {} of String => JSON::Any)
    end
  end
end
