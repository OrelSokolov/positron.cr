require "json"

module CrystalUI::Plugins
  # Keyboard events, shortcuts and virtual keyboard state plugin.
  #
  # The frontend sends raw `keyboard.keydown` events via the JS bridge.
  # The host records them, matches registered shortcuts and emits
  # `keyboard.shortcut` back to the UI.
  #
  # Exposed commands:
  #   - keyboard.register_shortcut(id, key, ctrl?, alt?, shift?, meta?, prevent_default?)
  #   - keyboard.unregister_shortcut(id)
  #   - keyboard.list_shortcuts()
  #   - keyboard.get_events()
  #   - keyboard.clear_events()
  #   - keyboard.set_virtual_keyboard_visible(visible)
  #   - keyboard.get_virtual_keyboard_info()
  #
  # Emitted events:
  #   - keyboard.keydown  (from frontend)
  #   - keyboard.shortcut (from host when a registered shortcut matches)
  #
  # Observable state:
  #   - keyboard.last_event
  #   - keyboard.events
  #   - keyboard.shortcuts
  #   - keyboard.keyboard_height
  #   - keyboard.is_visible
  class Keyboard < CrystalUI::Plugin
    alias ShortcutMap = Hash(String, Shortcut)

    record Shortcut,
      id : String,
      key : String,
      code : String,
      ctrl : Bool,
      alt : Bool,
      shift : Bool,
      meta : Bool,
      prevent_default : Bool

    record KeyboardEvent,
      type : String,
      key : String,
      code : String,
      ctrl : Bool,
      alt : Bool,
      shift : Bool,
      meta : Bool,
      shortcut : String?,
      timestamp : Int64

    @shortcuts = ShortcutMap.new
    @events = [] of KeyboardEvent
    @max_events = 20
    @keyboard_height = 0
    @visible = false
    @mutex = Mutex.new

    def name : String
      "keyboard"
    end

    def supported_platforms : Array(Symbol)
      [:desktop, :android, :ios]
    end

    def state : Hash(String, JSON::Any)
      @mutex.synchronize do
        last_json = @events.last?.try { |e| event_to_hash(e).to_json } || "null"
        events_json = @events.map { |e| event_to_hash(e) }.to_json
        shortcuts_json = @shortcuts.values.map { |s| shortcut_to_hash(s) }.to_json

        {
          "last_event"      => JSON.parse(last_json),
          "events"          => JSON.parse(events_json),
          "shortcuts"       => JSON.parse(shortcuts_json),
          "keyboard_height" => JSON.parse(@keyboard_height.to_json),
          "is_visible"      => JSON.parse(@visible.to_json),
        }
      end
    end

    def manifest : Hash(String, CrystalUI::CommandManifest)
      {
        "keyboard.register_shortcut" => CrystalUI::CommandManifest.new(
          name: "keyboard.register_shortcut",
          args: [
            CrystalUI::ArgumentManifest.new(name: "id", type: "String"),
            CrystalUI::ArgumentManifest.new(name: "key", type: "String"),
            CrystalUI::ArgumentManifest.new(name: "code", type: "String"),
            CrystalUI::ArgumentManifest.new(name: "ctrl", type: "Bool"),
            CrystalUI::ArgumentManifest.new(name: "alt", type: "Bool"),
            CrystalUI::ArgumentManifest.new(name: "shift", type: "Bool"),
            CrystalUI::ArgumentManifest.new(name: "meta", type: "Bool"),
            CrystalUI::ArgumentManifest.new(name: "prevent_default", type: "Bool"),
          ],
          returns: "Bool",
        ),
        "keyboard.unregister_shortcut" => CrystalUI::CommandManifest.new(
          name: "keyboard.unregister_shortcut",
          args: [CrystalUI::ArgumentManifest.new(name: "id", type: "String")],
          returns: "Bool",
        ),
        "keyboard.list_shortcuts" => CrystalUI::CommandManifest.new(
          name: "keyboard.list_shortcuts",
          returns: "Array",
        ),
        "keyboard.get_events" => CrystalUI::CommandManifest.new(
          name: "keyboard.get_events",
          returns: "Array",
        ),
        "keyboard.clear_events" => CrystalUI::CommandManifest.new(
          name: "keyboard.clear_events",
          returns: "Bool",
        ),
        "keyboard.set_virtual_keyboard_visible" => CrystalUI::CommandManifest.new(
          name: "keyboard.set_virtual_keyboard_visible",
          args: [CrystalUI::ArgumentManifest.new(name: "visible", type: "Bool")],
          returns: "Bool",
        ),
        "keyboard.get_virtual_keyboard_info" => CrystalUI::CommandManifest.new(
          name: "keyboard.get_virtual_keyboard_info",
          returns: "Object",
        ),
      }
    end

    def bind(registry : CrystalUI::CommandRegistry, state : CrystalUI::StateManager)
      registry.register("keyboard.register_shortcut") do |request|
        args = request.args
        key = string_arg(args, "key")
        code = string_arg(args, "code")

        shortcut = Shortcut.new(
          id: string_arg(args, "id"),
          key: key.empty? ? "" : normalize_key(key),
          code: code.empty? ? "" : code.strip.upcase,
          ctrl: bool_arg(args, "ctrl"),
          alt: bool_arg(args, "alt"),
          shift: bool_arg(args, "shift"),
          meta: bool_arg(args, "meta"),
          prevent_default: bool_arg(args, "prevent_default", true)
        )

        @mutex.synchronize { @shortcuts[shortcut.id] = shortcut }
        sync_shortcuts_state

        CrystalUI::CommandResult.new(success: true, data: JSON.parse(true.to_json))
      end

      registry.register("keyboard.unregister_shortcut") do |request|
        id = string_arg(request.args, "id")
        removed = @mutex.synchronize { @shortcuts.delete(id) }
        sync_shortcuts_state if removed

        CrystalUI::CommandResult.new(
          success: removed != nil,
          data: JSON.parse((removed != nil).to_json)
        )
      end

      registry.register("keyboard.list_shortcuts") do |_request|
        CrystalUI::CommandResult.new(
          success: true,
          data: JSON.parse(shortcuts_json)
        )
      end

      registry.register("keyboard.get_events") do |_request|
        CrystalUI::CommandResult.new(
          success: true,
          data: JSON.parse(events_json)
        )
      end

      registry.register("keyboard.clear_events") do |_request|
        @mutex.synchronize { @events.clear }
        sync_events_state

        CrystalUI::CommandResult.new(success: true, data: JSON.parse(true.to_json))
      end

      registry.register("keyboard.set_virtual_keyboard_visible") do |request|
        visible = bool_arg(request.args, "visible")
        @mutex.synchronize { @visible = visible }
        set_state("is_visible", @visible)

        CrystalUI::CommandResult.new(success: true, data: JSON.parse(@visible.to_json))
      end

      registry.register("keyboard.get_virtual_keyboard_info") do |_request|
        @mutex.synchronize do
          data = {
            height:  @keyboard_height,
            visible: @visible,
          }
          CrystalUI::CommandResult.new(success: true, data: JSON.parse(data.to_json))
        end
      end
    end

    # Called by the host when the frontend emits `keyboard.keydown`.
    def on_event(event : String, payload : JSON::Any)
      return unless event == "keyboard.keydown"

      key = payload["key"]?.try(&.as_s) || ""
      code = payload["code"]?.try(&.as_s) || ""
      ctrl = payload["ctrl"]?.try(&.as_bool) || false
      alt = payload["alt"]?.try(&.as_bool) || false
      shift = payload["shift"]?.try(&.as_bool) || false
      meta = payload["meta"]?.try(&.as_bool) || false

      normalized_key = normalize_key(key)
      normalized_code = code.strip.upcase

      matched = @mutex.synchronize do
        @shortcuts.values.find do |s|
          modifiers_match = s.ctrl == ctrl && s.alt == alt && s.shift == shift && s.meta == meta
          next false unless modifiers_match

          key_matches = !s.key.empty? && s.key == normalized_key
          code_matches = !s.code.empty? && s.code == normalized_code
          key_matches || code_matches
        end
      end

      keyboard_event = KeyboardEvent.new(
        type: "keydown",
        key: key,
        code: code,
        ctrl: ctrl,
        alt: alt,
        shift: shift,
        meta: meta,
        shortcut: matched.try(&.id),
        timestamp: Time.utc.to_unix_ms
      )

      @mutex.synchronize do
        @events << keyboard_event
        @events.shift if @events.size > @max_events
      end

      set_state("last_event", event_to_hash(keyboard_event))
      sync_events_state

      if matched
        CrystalUI::EventBus.emit("keyboard.shortcut", {
          id:       matched.id,
          key:      key,
          code:     code,
          ctrl:     ctrl,
          alt:      alt,
          shift:    shift,
          meta:     meta,
          shortcut: matched.id,
        })
      end
    end

    # Mobile/desktop shim can report virtual keyboard geometry via this helper.
    def set_keyboard_height(height : Int32)
      @mutex.synchronize { @keyboard_height = height }
      set_state("keyboard_height", height)
    end

    private def normalize_key(key : String) : String
      key.strip.downcase
    end

    private def string_arg(args : JSON::Any, name : String) : String
      args[name]?.try(&.as_s) || ""
    end

    private def bool_arg(args : JSON::Any, name : String, default : Bool = false) : Bool
      args[name]?.try(&.as_bool) || default
    end

    private def event_to_hash(event : KeyboardEvent) : Hash(String, JSON::Any)
      {
        "type"      => JSON.parse(event.type.to_json),
        "key"       => JSON.parse(event.key.to_json),
        "code"      => JSON.parse(event.code.to_json),
        "ctrl"      => JSON.parse(event.ctrl.to_json),
        "alt"       => JSON.parse(event.alt.to_json),
        "shift"     => JSON.parse(event.shift.to_json),
        "meta"      => JSON.parse(event.meta.to_json),
        "shortcut"  => JSON.parse(event.shortcut.to_json),
        "timestamp" => JSON.parse(event.timestamp.to_json),
      }
    end

    private def shortcut_to_hash(shortcut : Shortcut) : Hash(String, JSON::Any)
      {
        "id"              => JSON.parse(shortcut.id.to_json),
        "key"             => JSON.parse(shortcut.key.to_json),
        "code"            => JSON.parse(shortcut.code.to_json),
        "ctrl"            => JSON.parse(shortcut.ctrl.to_json),
        "alt"             => JSON.parse(shortcut.alt.to_json),
        "shift"           => JSON.parse(shortcut.shift.to_json),
        "meta"            => JSON.parse(shortcut.meta.to_json),
        "prevent_default" => JSON.parse(shortcut.prevent_default.to_json),
      }
    end

    private def last_event_json : String
      @events.last?.try { |e| event_to_hash(e).to_json } || "null"
    end

    private def events_json : String
      @mutex.synchronize { @events.map { |e| event_to_hash(e) }.to_json }
    end

    private def shortcuts_json : String
      @mutex.synchronize { @shortcuts.values.map { |s| shortcut_to_hash(s) }.to_json }
    end

    private def sync_events_state
      set_state("events", JSON.parse(events_json))
    end

    private def sync_shortcuts_state
      set_state("shortcuts", JSON.parse(shortcuts_json))
    end
  end
end
