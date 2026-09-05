require "json"

module CrystalUI::Plugins
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
  class Permissions < CrystalUI::Plugin
    def name : String
      "permissions"
    end

    def supported_platforms : Array(Symbol)
      [:desktop, :android, :ios]
    end

    def manifest : Hash(String, CrystalUI::CommandManifest)
      {
        "permissions.check" => CrystalUI::CommandManifest.new(
          name: "permissions.check",
          args: [CrystalUI::ArgumentManifest.new(name: "permission", type: "String")],
          returns: "Object",
        ),
        "permissions.request" => CrystalUI::CommandManifest.new(
          name: "permissions.request",
          args: [CrystalUI::ArgumentManifest.new(name: "permission", type: "String")],
          returns: "Object",
        ),
      }
    end

    def bind(registry : CrystalUI::CommandRegistry, state : CrystalUI::StateManager)
      registry.register("permissions.check") do |request|
        permission = str(request.args, "permission")
        CrystalUI::CommandResult.new(
          success: true,
          data: granted_state(permission)
        )
      end

      registry.register("permissions.request") do |request|
        permission = str(request.args, "permission")
        CrystalUI::EventBus.emit("permission.changed", JSON.parse(
          {permission: permission, state: "granted"}.to_json
        ))
        CrystalUI::CommandResult.new(
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
