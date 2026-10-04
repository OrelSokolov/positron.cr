require "json"

module Positron::Plugins
  # Platform-agnostic interface for persistent key-value preferences.
  #
  # Each platform provides a thin adapter that stores values in the OS-native
  # preference mechanism:
  #   - Linux:   JSON file under $XDG_CONFIG_HOME/positron
  #   - Windows: Registry stub (falls back to JSON file)
  #   - macOS:   NSUserDefaults stub (falls back to JSON file)
  #   - Android: SharedPreferences stub
  #   - iOS:     NSUserDefaults stub
  abstract class PreferencesAdapter
    # Read a single preference value. Returns `default` if the key is missing.
    abstract def get(key : String, default : JSON::Any? = nil) : JSON::Any

    # Store a single preference value.
    abstract def set(key : String, value : JSON::Any) : Bool

    # Remove a single preference key.
    abstract def remove(key : String) : Bool

    # Remove all preferences.
    abstract def clear : Bool

    # Returns true if the key exists.
    abstract def has?(key : String) : Bool

    # Returns all stored preferences as a hash.
    abstract def all : Hash(String, JSON::Any)
  end
end
