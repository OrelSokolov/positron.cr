module Positron::Plugins
  # Platform-agnostic interface for the permissions plugin.
  #
  # States follow the web Permissions API: "granted" | "denied" |
  # "prompt". `request` starts the OS permission flow where one exists
  # (Android runtime permissions) and returns the CURRENT state — the
  # user's answer, when the dialog is async, arrives later as a
  # `permission.result` event which the plugin forwards to the frontend
  # as `permission.changed`.
  abstract class PermissionsAdapter
    # Current state of `permission`
    # ("notifications" | "clipboard" | "files" | "camera" |
    #  "microphone" | "location" | …).
    abstract def check(permission : String) : String

    # Request `permission`; returns the state at call time.
    abstract def request(permission : String) : String
  end
end
