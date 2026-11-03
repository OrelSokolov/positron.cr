require "./adapter"

# Platform adapter sources are gated by target flags so their @[Link]
# annotations (Linux C libs) never reach non-Linux builds.
{% if flag?(:android) %}
  require "./android"
{% end %}

module Positron::Plugins
  # Compile-time factory that picks the correct native permissions
  # adapter for the current target platform.
  module PermissionsAdapterFactory
    def self.create : PermissionsAdapter
      {% if flag?(:android) %}
        AndroidPermissionsAdapter.new
      {% else %}
        # Desktop (and iOS until its adapter lands): the app runs with
        # the user's rights — everything reports "granted".
        DesktopPermissionsAdapter.new
      {% end %}
    end
  end

  # Desktop permissions semantics: the app runs with the user's rights,
  # so every permission reports "granted" (mobile hosts override with
  # real OS permission flows through the factory).
  class DesktopPermissionsAdapter < PermissionsAdapter
    def check(permission : String) : String
      "granted"
    end

    def request(permission : String) : String
      "granted"
    end
  end
end
