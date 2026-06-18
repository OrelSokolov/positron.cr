require "json"

module CrystalUI
  # Base class for all CrystalUI plugins.
  #
  # Plugins live inside the Crystal Host. They request native services
  # through the host and emit events via EventBus.
  abstract class Plugin
    # Unique plugin identifier, e.g. "camera".
    abstract def name : String

    # Platforms supported by this plugin, e.g. [:desktop, :android, :ios].
    abstract def supported_platforms : Array(Symbol)

    # Reference to the host, set by the application during startup.
    property host : DesktopHost?

    # Called by the host during startup to let the plugin register commands.
    # Prefer explicit registration here over macros.
    def bind(registry : CommandRegistry, state : StateManager)
      # override in subclass
    end

    # Manifest of commands exposed to the JS frontend.
    # Used by JSFacadeGenerator to build CrystalUI.* API and TypeScript types.
    def manifest : Hash(String, CommandManifest)
      {} of String => CommandManifest
    end

    # Initial state slice for this plugin. Hydrated into the frontend on startup.
    def state : Hash(String, JSON::Any)
      {} of String => JSON::Any
    end

    # Called by the host when an OS event is routed to this plugin.
    def on_event(event : String, payload : JSON::Any)
      # override in subclass
    end

    # Called once during application startup.
    def on_ready(host : DesktopHost)
      # override in subclass
    end

    # Returns true if the plugin supports the current platform.
    def supports?(platform : Symbol) : Bool
      supported_platforms.includes?(platform)
    end

    # Helper to access the state manager.
    def state_manager : StateManager?
      host.try &.state_manager
    end

    # Helper to emit state changes.
    def set_state(key : String, value)
      state_manager.try &.set(name, key, value)
    end
  end

  # Simple plugin registry.
  class PluginManager
    @plugins = Hash(String, Plugin).new

    def register(plugin : Plugin)
      @plugins[plugin.name] = plugin
    end

    def [](name : String) : Plugin
      @plugins[name]
    end

    def []?(name : String) : Plugin?
      @plugins[name]?
    end

    def each(&block : Plugin ->)
      @plugins.each_value(&block)
    end

    def to_a : Array(Plugin)
      @plugins.values
    end
  end
end
