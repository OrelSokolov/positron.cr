require "json"

module Positron::Plugins
  # Permissions manager plugin.
  #
  # Exposes to the frontend:
  #   - permissions.check(permission)  → { state: "granted"|"denied"|"prompt" }
  #   - permissions.request(permission) → { state: "granted"|"denied" }
  #
  # On desktop the model is trivial: the app runs with the user's rights,
  # so every permission reports "granted". Mobile hosts override this
  # plugin later with real OS permission flows — the API shape stays
  # stable so frontends can be written once.
  #
  # Known permission names (desktop semantics):
  #   notifications, clipboard, files, camera, microphone, location,
  #   contacts, calendar
  class Permissions < Positron::Plugin
    def name : String
      "permissions"
    end

    def supported_platforms : Array(Symbol)
      [:desktop, :android, :ios]
    end

    def manifest : Hash(String, Positron::CommandManifest)
      {
        "permissions.check" => Positron::CommandManifest.new(
          name: "permissions.check",
          args: [Positron::ArgumentManifest.new(name: "permission", type: "String")],
          returns: "Object",
        ),
        "permissions.request" => Positron::CommandManifest.new(
          name: "permissions.request",
          args: [Positron::ArgumentManifest.new(name: "permission", type: "String")],
          returns: "Object",
        ),
      }
    end

    def bind(registry : Positron::CommandRegistry, state : Positron::StateManager)
      registry.register("permissions.check") do |request|
        permission = str(request.args, "permission")
        Positron::CommandResult.new(
          success: true,
          data: granted_state(permission)
        )
      end

      registry.register("permissions.request") do |request|
        permission = str(request.args, "permission")
        Positron::EventBus.emit("permission.changed", JSON.parse(
          {permission: permission, state: "granted"}.to_json
        ))
        Positron::CommandResult.new(
          success: true,
          data: granted_state(permission)
        )
      end
    end

    private def granted_state(permission : String) : JSON::Any
      JSON.parse({state: "granted", permission: permission}.to_json)
    end

    private def str(args : JSON::Any, key : String) : String
      args[key]?.try(&.as_s?) || ""
    end
  end
end
