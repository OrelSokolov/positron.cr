require "json"
require "log"
require "./adapter"
require "../../adapters/android/shim"
require "../../adapters/android/jni"

module Positron::Plugins
  # Android preferences adapter: SharedPreferences through the JNI
  # bridge. Values cross the bridge as JSON strings — the bridge layer
  # stays untyped, the adapter keeps the JSON::Any contract of the
  # plugin API.
  class AndroidPreferencesAdapter < PreferencesAdapter
    Log = ::Log.for("positron.plugins.preferences")

    # Sentinel the bridge never stores: distinguishes "missing key"
    # from a stored null.
    MISSING = "\u0000MISSING\u0000"

    def initialize(@app_id : String = "positron")
      # All Positron apps share the "positron" SharedPreferences file;
      # the per-app namespace is a key prefix.
    end

    private def bridge : Positron::Adapters::Android::LibJNI::JObject
      Positron::Adapters::Android::LibShim.positron_shim_bridge
    end

    private def prefixed(key : String) : String
      "#{@app_id}.#{key}"
    end

    def get(key : String, default : JSON::Any? = nil) : JSON::Any
      raw = pref_get_string(prefixed(key), default ? default.to_json : MISSING)
      return default.not_nil! if raw == MISSING
      return default.not_nil! if raw.nil? || raw.empty?
      JSON.parse(raw)
    rescue ex
      Log.error(exception: ex) { "get(#{key}) failed" }
      default || JSON.parse(nil.to_json)
    end

    def set(key : String, value : JSON::Any) : Bool
      jni = Positron::Adapters::Android::JNI.instance
      jni.call_bool(bridge, "prefSet", "(Ljava/lang/String;Ljava/lang/String;)Z",
        [jni.to_java(prefixed(key)).address.to_i64,
         jni.to_java(value.to_json).address.to_i64]) == true
    rescue ex
      Log.error(exception: ex) { "set(#{key}) failed" }
      false
    end

    def remove(key : String) : Bool
      jni = Positron::Adapters::Android::JNI.instance
      jni.call_bool(bridge, "prefRemove", "(Ljava/lang/String;)Z",
        [jni.to_java(prefixed(key)).address.to_i64]) == true
    rescue ex
      Log.error(exception: ex) { "remove(#{key}) failed" }
      false
    end

    def clear : Bool
      # SharedPreferences has no prefixed clear; enumerate our keys.
      all.keys.each { |key| remove(key) }
      true
    rescue ex
      Log.error(exception: ex) { "clear failed" }
      false
    end

    def has?(key : String) : Bool
      pref_get_string(prefixed(key), MISSING) != MISSING
    rescue ex
      Log.error(exception: ex) { "has?(#{key}) failed" }
      false
    end

    def all : Hash(String, JSON::Any)
      raw = Positron::Adapters::Android::JNI.instance.call_string(bridge, "prefAll", "()Ljava/lang/String;")
      return {} of String => JSON::Any unless raw

      result = {} of String => JSON::Any
      JSON.parse(raw).as_h.each do |full_key, value|
        next unless full_key.starts_with?("#{@app_id}.")
        key = full_key[@app_id.size + 1..]
        result[key] = value.as_s? ? JSON.parse(value.as_s) : value
      end
      result
    rescue ex
      Log.error(exception: ex) { "all failed" }
      {} of String => JSON::Any
    end

    private def pref_get_string(key : String, default : String) : String?
      jni = Positron::Adapters::Android::JNI.instance
      jni.call_string(bridge, "prefGet", "(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;",
        [jni.to_java(key).address.to_i64,
         jni.to_java(default).address.to_i64])
    end
  end
end
