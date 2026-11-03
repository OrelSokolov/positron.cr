require "json"
require "log"
require "./adapter"
require "./factory"

module Positron::Plugins
  # Permissions manager plugin.
  #
  # Exposes to the frontend:
  #   - permissions.check(permission)  → { state: "granted"|"denied"|"prompt" }
  #   - permissions.request(permission) → { state: ... }
  #
  # Known permission names: notifications, clipboard, files, camera,
  # microphone, location, contacts, calendar.
  #
  # Desktop semantics: the app runs with the user's rights, so every
  # permission reports "granted". On Android the adapter talks to the
  # real runtime-permission flow: `request` returns the state at call
  # time and, when the OS dialog is async, the user's answer arrives
  # later as a `permission.changed` event to the frontend (forwarded
  # from the host's `permission.result` event). The API shape stays
  # stable so frontends can be written once.
  class Permissions < Positron::Plugin
    @adapter : PermissionsAdapter

    def initialize
      @adapter = PermissionsAdapterFactory.create
    end

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
          data: state_for(permission, @adapter.check(permission))
        )
      end

      registry.register("permissions.request") do |request|
        permission = str(request.args, "permission")
        perm_state = @adapter.request(permission)
        Positron::EventBus.emit("permission.changed",
          JSON.parse({permission: permission, state: perm_state}.to_json))
        Positron::CommandResult.new(
          success: true,
          data: state_for(permission, perm_state)
        )
      end
    end

    # OS-level answers (Android runtime dialogs) arrive after #request
    # returned — forward them to the frontend as permission.changed.
    def on_ready(host : Positron::Host)
      Positron::EventBus.on("permission.result") do |payload|
        permission = payload["permission"]?.try(&.as_s?) || ""
        next if permission.empty?
        state = payload["granted"]?.try(&.as?(Bool)) == true ? "granted" : "denied"
        host.emit_to_js("permission.changed",
          {permission: permission, state: state})
      end
    end

    private def state_for(permission : String, state : String) : JSON::Any
      JSON.parse({state: state, permission: permission}.to_json)
    end

    private def str(args : JSON::Any, key : String) : String
      args[key]?.try(&.as_s?) || ""
    end
  end
end
