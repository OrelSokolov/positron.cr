require "json"

module CrystalUI
  # Central observable state owned by the Crystal Host.
  #
  # Plugins read and write state through this manager. Every change emits
  # a `state.changed` event that the host forwards to the WebView, keeping
  # the JS frontend in sync.
  class StateManager
    @state = {} of String => JSON::Any

    # Replace the entire state. Used during hydration.
    def hydrate(state : Hash(String, JSON::Any))
      @state = state.dup
    end

    # Get the full state snapshot.
    def snapshot : Hash(String, JSON::Any)
      @state.dup
    end

    # Load a plugin's initial state slice without emitting events.
    def load_plugin_state(plugin : String, state : Hash(String, JSON::Any))
      return if state.empty?
      @state[plugin] = JSON.parse(state.to_json)
    end

    # Get a plugin's state slice.
    def plugin_state(plugin : String) : Hash(String, JSON::Any)
      @state[plugin]?.try(&.as_h?) || {} of String => JSON::Any
    end

    # Read a single value from a plugin's state.
    def get(plugin : String, key : String) : JSON::Any?
      plugin_state(plugin)[key]?
    end

    # Update a single value and emit `state.changed`.
    def set(plugin : String, key : String, value)
      data = plugin_state(plugin)
      data[key] = JSON.parse(value.to_json)
      @state[plugin] = JSON.parse(data.to_json)

      EventBus.emit("state.changed", {
        plugin: plugin,
        key:    key,
        value:  value,
      })
    end

    # Batch update several keys at once and emit one `state.changed` event
    # per changed key.
    def set_many(plugin : String, values : Hash(String, _))
      values.each do |key, value|
        set(plugin, key, value)
      end
    end
  end
end
