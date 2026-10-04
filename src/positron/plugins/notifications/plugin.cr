require "json"
require "log"
require "random"
require "./adapter"
require "./factory"

module Positron::Plugins
  # System notifications plugin.
  #
  # Exposes a small host-side API to the frontend:
  #   - notifications.send(title, body, id?)
  #   - notifications.clear(id)
  #   - notifications.request_permission()
  #   - notifications.check_permission()
  #
  # Platform adapters live in `src/positron/plugins/notifications/` and are
  # selected at compile time by `NotificationsAdapterFactory`.
  class Notifications < Positron::Plugin
    @adapter : NotificationsAdapter

    def initialize
      @adapter = NotificationsAdapterFactory.create
    end

    def name : String
      "notifications"
    end

    def supported_platforms : Array(Symbol)
      [:desktop, :android, :ios]
    end

    def manifest : Hash(String, Positron::CommandManifest)
      {
        "notifications.send" => Positron::CommandManifest.new(
          name: "notifications.send",
          args: [
            Positron::ArgumentManifest.new(name: "title", type: "String"),
            Positron::ArgumentManifest.new(name: "body", type: "String"),
            Positron::ArgumentManifest.new(name: "id", type: "String"),
          ],
          returns: "String",
        ),
        "notifications.clear" => Positron::CommandManifest.new(
          name: "notifications.clear",
          args: [
            Positron::ArgumentManifest.new(name: "id", type: "String"),
          ],
          returns: "Bool",
        ),
        "notifications.request_permission" => Positron::CommandManifest.new(
          name: "notifications.request_permission",
          returns: "Bool",
        ),
        "notifications.check_permission" => Positron::CommandManifest.new(
          name: "notifications.check_permission",
          returns: "Bool",
        ),
      }
    end

    def bind(registry : Positron::CommandRegistry, state : Positron::StateManager)
      registry.register("notifications.send") do |request|
        title = request.args["title"]?.try(&.as_s?) || ""
        body = request.args["body"]?.try(&.as_s?) || ""
        id = request.args["id"]?.try(&.as_s?) || generate_id

        @adapter.send(id, title, body)

        Positron::CommandResult.new(
          success: true,
          data: JSON.parse(id.to_json)
        )
      end

      registry.register("notifications.clear") do |request|
        id = request.args["id"]?.try(&.as_s?) || ""
        cleared = @adapter.clear(id)

        Positron::CommandResult.new(
          success: true,
          data: JSON.parse(cleared.to_json)
        )
      end

      registry.register("notifications.request_permission") do |_request|
        granted = @adapter.request_permission

        Positron::CommandResult.new(
          success: true,
          data: JSON.parse(granted.to_json)
        )
      end

      registry.register("notifications.check_permission") do |_request|
        granted = @adapter.check_permission

        Positron::CommandResult.new(
          success: true,
          data: JSON.parse(granted.to_json)
        )
      end
    end

    def on_ready(host : Positron::DesktopHost)
      @adapter.on_click do |id|
        host.emit_to_js("notification.clicked", {id: id})
      end
    end

    private def generate_id : String
      Random::Secure.hex(8)
    end
  end
end
