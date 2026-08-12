require "../src/crystal_ui/state_manager"
require "spec"
require "json"

describe CrystalUI::StateManager do
  manager = CrystalUI::StateManager.new

  it "stores and retrieves plugin state" do
    manager.load_plugin_state("settings", {"theme" => JSON.parse(%("dark"))})

    state = manager.plugin_state("settings")
    state["theme"].to_s.should eq("dark")
  end

  it "reads individual values" do
    manager.get("settings", "theme").not_nil!.to_s.should eq("dark")
  end

  it "returns nil for missing plugin state" do
    manager.get("nonexistent", "key").should be_nil
    manager.plugin_state("nonexistent").should be_empty
  end

  it "updates a value and emits state.changed" do
    received = [] of JSON::Any

    handler = ->(payload : JSON::Any) do
      received << payload
      nil
    end

    CrystalUI::EventBus.on("state.changed", &handler)
    manager.set("settings", "theme", "light")

    sleep 50.milliseconds

    received.size.should eq(1)
    received[0]["plugin"].to_s.should eq("settings")
    received[0]["key"].to_s.should eq("theme")
    received[0]["value"].to_s.should eq("light")

    manager.get("settings", "theme").not_nil!.to_s.should eq("light")

    CrystalUI::EventBus.off("state.changed", handler)
  end

  it "takes a full snapshot" do
    manager.load_plugin_state("other", {"count" => JSON.parse("10")})
    snapshot = manager.snapshot

    snapshot.has_key?("settings").should be_true
    snapshot.has_key?("other").should be_true
    snapshot["other"]["count"].to_s.should eq("10")
  end

  it "ignores empty state slices" do
    manager.load_plugin_state("empty", {} of String => JSON::Any)
    manager.snapshot.has_key?("empty").should be_false
  end

  it "hydrate replaces all state" do
    sm = CrystalUI::StateManager.new
    sm.load_plugin_state("a", {"x" => JSON.parse("1")})

    sm.hydrate({"fresh" => JSON.parse(%({"y": 2}))})
    snapshot = sm.snapshot

    snapshot.has_key?("a").should be_false
    snapshot.has_key?("fresh").should be_true
  end
end
