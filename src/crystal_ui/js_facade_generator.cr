require "json"

module CrystalUI
  # Generates the JavaScript runtime facade that is injected into the WebView.
  #
  # The generated code exposes:
  #   - CrystalUI.call(name, args) : Promise
  #   - CrystalUI.emit(name, payload)
  #   - CrystalUI.on(name, callback) / CrystalUI.once(name, callback)
  #   - CrystalUI.state (hydrated from the host)
  #   - CrystalUI.<plugin>.<method>(args) generated from plugin manifests
  #
  # The runtime is platform-agnostic: it talks to the host through
  # `window.CrystalBridge.postMessage(jsonString)`, which each WebView adapter
  # injects using the native bridge mechanism (WebKit message handlers,
  # WebView2 chrome.webview, Android @JavascriptInterface, etc.).
  class JSFacadeGenerator
    def initialize(@plugins : Array(Plugin))
    end

    # Returns the full JS runtime to inject before the application loads.
    def runtime_js : String
      [
        "(function() {",
        "  const pending = new Map();",
        "  const listeners = new Map();",
        "",
        "  function notify(event, payload) {",
        "    const cbs = listeners.get(event);",
        "    if (!cbs) return;",
        "    cbs.forEach(cb => {",
        "      try { cb(payload); } catch (e) { console.error(e); }",
        "    });",
        "  }",
        "",
        "  window.__crystalNotify = notify;",
        "",
        "  window.__crystalResolve = function(id, success, data, error) {",
        "    const p = pending.get(id);",
        "    if (!p) return;",
        "    pending.delete(id);",
        "    success ? p.resolve(data) : p.reject(new Error(error));",
        "  };",
        "",
        "  window.__crystalHydrate = function(state) {",
        "    CrystalUI.state = state || {};",
        "  };",
        "",
        "  window.__crystalPatchState = function(patch) {",
        "    const plugin = patch.plugin;",
        "    const key = patch.key;",
        "    const value = patch.value;",
        "    if (!CrystalUI.state[plugin]) CrystalUI.state[plugin] = {};",
        "    CrystalUI.state[plugin][key] = value;",
        "    notify('state.' + plugin + '.' + key, value);",
        "    notify('state.' + plugin + '.*', { plugin: plugin, key: key, value: value });",
        "  };",
        "",
        "  window.CrystalUI = {",
        "    state: {},",
        "",
        "    call: function(name, args) {",
        "      args = args || {};",
        "      return new Promise(function(resolve, reject) {",
        "        const id = Math.random().toString(36).slice(2) + Date.now().toString(36);",
        "        pending.set(id, { resolve: resolve, reject: reject });",
        "        CrystalBridge.postMessage(JSON.stringify({",
        "          type: 'command',",
        "          id: id,",
        "          name: name,",
        "          args: args",
        "        }));",
        "      });",
        "    },",
        "",
        "    emit: function(event, payload) {",
        "      CrystalBridge.postMessage(JSON.stringify({",
        "        type: 'event',",
        "        event: event,",
        "        payload: payload || {}",
        "      }));",
        "    },",
        "",
        "    on: function(event, callback) {",
        "      if (!listeners.has(event)) listeners.set(event, []);",
        "      listeners.get(event).push(callback);",
        "      return function() {",
        "        const arr = listeners.get(event);",
        "        if (!arr) return;",
        "        const i = arr.indexOf(callback);",
        "        if (i >= 0) arr.splice(i, 1);",
        "      };",
        "    },",
        "",
        "    once: function(event, callback) {",
        "      const off = this.on(event, function(data) {",
        "        off();",
        "        callback(data);",
        "      });",
        "      return off;",
        "    },",
        "",
        "    #{generated_namespaces}",
        "  };",
        "})();",
      ].join("\n")
    end

    # Returns a JS snippet that hydrates the frontend with the given state.
    def hydrate_js(state : Hash(String, JSON::Any)) : String
      "window.__crystalHydrate(" + state.to_json + ")"
    end

    # Returns a JS snippet that patches a single state key.
    def patch_js(plugin : String, key : String, value) : String
      "window.__crystalPatchState(" + {plugin: plugin, key: key, value: value}.to_json + ")"
    end

    private def generated_namespaces : String
      grouped = Hash(String, Array(String)).new { |h, k| h[k] = [] of String }

      @plugins.each do |plugin|
        plugin.manifest.each do |full_name, manifest|
          split = split_command_name(full_name)
          next unless split
          namespace, method = split
          grouped[namespace] << "#{method}: function(args) { return CrystalUI.call('#{full_name}', args || {}); }"
        end
      end

      return "" if grouped.empty?

      grouped.map do |namespace, methods|
        "#{namespace}: {\n    " + methods.join(",\n    ") + "\n  }"
      end.join(",\n\n    ")
    end

    private def split_command_name(full_name : String) : {String, String}?
      parts = full_name.split('.')
      return nil if parts.size < 2
      {parts[0..-2].join('.'), parts[-1]}
    end
  end
end
