require "../src/crystal_ui/event_bus"
require "spec"
require "json"

describe CrystalUI::EventBus do
  it "delivers events to subscribers" do
    received = [] of JSON::Any

    handler = ->(payload : JSON::Any) do
      received << payload
      nil
    end

    CrystalUI::EventBus.on("test.event", &handler)
    CrystalUI::EventBus.emit("test.event", {"key" => "value"})

    # Handlers run in fibers — give them time to execute.
    sleep 50.milliseconds

    received.size.should eq(1)
    received[0]["key"].to_s.should eq("value")

    CrystalUI::EventBus.off("test.event", handler)
  end

  it "supports multiple subscribers for the same event" do
    results = [] of Int32

    h1 = ->(_p : JSON::Any) { results << 1; nil }
    h2 = ->(_p : JSON::Any) { results << 2; nil }

    CrystalUI::EventBus.on("multi.event", &h1)
    CrystalUI::EventBus.on("multi.event", &h2)
    CrystalUI::EventBus.emit("multi.event", {} of String => JSON::Any)

    sleep 50.milliseconds

    results.sort.should eq([1, 2])

    CrystalUI::EventBus.off("multi.event", h1)
    CrystalUI::EventBus.off("multi.event", h2)
  end

  it "does not deliver events to unsubscribed handlers" do
    received = [] of JSON::Any

    handler = ->(payload : JSON::Any) do
      received << payload
      nil
    end

    CrystalUI::EventBus.on("off.event", &handler)
    CrystalUI::EventBus.off("off.event", handler)
    CrystalUI::EventBus.emit("off.event", {"x" => 1})

    sleep 50.milliseconds

    received.should be_empty
  end

  it "fires once handlers only a single time" do
    count = 0

    CrystalUI::EventBus.once("once.event") do |_payload|
      count += 1
    end

    CrystalUI::EventBus.emit("once.event", {} of String => JSON::Any)
    sleep 50.milliseconds
    CrystalUI::EventBus.emit("once.event", {} of String => JSON::Any)
    sleep 50.milliseconds

    count.should eq(1)
  end

  it "accepts JSON::Any payloads" do
    received = [] of JSON::Any

    handler = ->(payload : JSON::Any) do
      received << payload
      nil
    end

    CrystalUI::EventBus.on("json.event", &handler)
    payload = JSON.parse(%({"nested": {"a": 1}}))
    CrystalUI::EventBus.emit("json.event", payload)

    sleep 50.milliseconds

    received.size.should eq(1)
    received[0]["nested"]["a"].to_s.should eq("1")

    CrystalUI::EventBus.off("json.event", handler)
  end

  it "does not crash when emitting an event with no subscribers" do
    CrystalUI::EventBus.emit("nobody.listening", {"a" => 1})
    sleep 10.milliseconds
  end
end
