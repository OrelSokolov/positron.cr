require "../src/positron/event_bus"
require "spec"
require "json"

describe Positron::EventBus do
  it "delivers events to subscribers" do
    received = [] of JSON::Any

    handler = ->(payload : JSON::Any) do
      received << payload
      nil
    end

    Positron::EventBus.on("test.event", &handler)
    Positron::EventBus.emit("test.event", {"key" => "value"})

    # Handlers run in fibers — give them time to execute.
    sleep 50.milliseconds

    received.size.should eq(1)
    received[0]["key"].to_s.should eq("value")

    Positron::EventBus.off("test.event", handler)
  end

  it "supports multiple subscribers for the same event" do
    results = [] of Int32

    h1 = ->(_p : JSON::Any) { results << 1; nil }
    h2 = ->(_p : JSON::Any) { results << 2; nil }

    Positron::EventBus.on("multi.event", &h1)
    Positron::EventBus.on("multi.event", &h2)
    Positron::EventBus.emit("multi.event", {} of String => JSON::Any)

    sleep 50.milliseconds

    results.sort.should eq([1, 2])

    Positron::EventBus.off("multi.event", h1)
    Positron::EventBus.off("multi.event", h2)
  end

  it "does not deliver events to unsubscribed handlers" do
    received = [] of JSON::Any

    handler = ->(payload : JSON::Any) do
      received << payload
      nil
    end

    Positron::EventBus.on("off.event", &handler)
    Positron::EventBus.off("off.event", handler)
    Positron::EventBus.emit("off.event", {"x" => 1})

    sleep 50.milliseconds

    received.should be_empty
  end

  it "fires once handlers only a single time" do
    count = 0

    Positron::EventBus.once("once.event") do |_payload|
      count += 1
    end

    Positron::EventBus.emit("once.event", {} of String => JSON::Any)
    sleep 50.milliseconds
    Positron::EventBus.emit("once.event", {} of String => JSON::Any)
    sleep 50.milliseconds

    count.should eq(1)
  end

  it "accepts JSON::Any payloads" do
    received = [] of JSON::Any

    handler = ->(payload : JSON::Any) do
      received << payload
      nil
    end

    Positron::EventBus.on("json.event", &handler)
    payload = JSON.parse(%({"nested": {"a": 1}}))
    Positron::EventBus.emit("json.event", payload)

    sleep 50.milliseconds

    received.size.should eq(1)
    received[0]["nested"]["a"].to_s.should eq("1")

    Positron::EventBus.off("json.event", handler)
  end

  it "does not crash when emitting an event with no subscribers" do
    Positron::EventBus.emit("nobody.listening", {"a" => 1})
    sleep 10.milliseconds
  end
end
