require "json"
require "log"
require "random"
require "./adapter"
require "./factory"

module CrystalUI::Plugins
  # System notifications plugin.
  #
  # Exposes a small host-side API to the frontend:
  #   - notifications.send(title, body, id?)
  #   - notifications.clear(id)
  #   - notifications.request_permission()
  #   - notifications.check_permission()
  #
  # Platform adapters live in `src/crystal_ui/plugins/notifications/` and are
  # selected at compile time by `NotificationsAdapterFactory`.
  class Notifications < CrystalUI::Plugin
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

    def manifest : Hash(String, CrystalUI::CommandManifest)
      {
        "notifications.send" => CrystalUI::CommandManifest.new(
          name: "notifications.send",
          args: [
            CrystalUI::ArgumentManifest.new(name: "title", type: "String"),
            CrystalUI::ArgumentManifest.new(name: "body", type: "String"),
            CrystalUI::ArgumentManifest.new(name: "id", type: "String"),
          ],
          returns: "String",
        ),
        "notifications.clear" => CrystalUI::CommandManifest.new(
          name: "notifications.clear",
          args: [
            CrystalUI::ArgumentManifest.new(name: "id", type: "String"),
          ],
          returns: "Bool",
        ),
        "notifications.request_permission" => CrystalUI::CommandManifest.new(
          name: "notifications.request_permission",
          returns: "Bool",
        ),
        "notifications.check_permission" => CrystalUI::CommandManifest.new(
          name: "notifications.check_permission",
          returns: "Bool",
        ),
      }
    end

    def bind(registry : CrystalUI::CommandRegistry, state : CrystalUI::StateManager)
      registry.register("notifications.send") do |request|
        title = request.args["title"]?.try(&.as_s?) || ""
        body = request.args["body"]?.try(&.as_s?) || ""
        id = request.args["id"]?.try(&.as_s?) || generate_id

        @adapter.send(id, title, body)

        CrystalUI::CommandResult.new(
          success: true,
          data: JSON.parse(id.to_json)
        )
      end

      registry.register("notifications.clear") do |request|
        id = request.args["id"]?.try(&.as_s?) || ""
        cleared = @adapter.clear(id)

        CrystalUI::CommandResult.new(
          success: true,
          data: JSON.parse(cleared.to_json)
        )
      end

      registry.register("notifications.request_permission") do |_request|
        granted = @adapter.request_permission

        CrystalUI::CommandResult.new(
          success: true,
          data: JSON.parse(granted.to_json)
        )
      end

      registry.register("notifications.check_permission") do |_request|
        granted = @adapter.check_permission

        CrystalUI::CommandResult.new(
          success: true,
          data: JSON.parse(granted.to_json)
        )
      end
    end

    def on_ready(host : CrystalUI::DesktopHost)
      @adapter.on_click do |id|
        host.emit_to_js("notification.clicked", {id: id})
      end
    end

    private def generate_id : String
      Random::Secure.hex(8)
    end
  end
end
