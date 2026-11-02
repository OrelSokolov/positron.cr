require "../src/positron/command_registry"
require "spec"
require "json"

describe Positron::CommandRegistry do
  registry = Positron::CommandRegistry.new

  it "dispatches a registered command" do
    registry.register("greet") do |request|
      name = request.args["name"]?.try(&.as_s?) || "world"
      Positron::CommandResult.new(
        success: true,
        data: JSON.parse(%({"message": "Hello, #{name}!"}))
      )
    end

    request = Positron::CommandRequest.new(
      id: "abc",
      name: "greet",
      args: JSON.parse(%({"name": "Crystal"}))
    )
    result = registry.dispatch(request)

    result.success.should be_true
    result.data["message"].to_s.should eq("Hello, Crystal!")
  end

  it "returns an error for unknown commands" do
    request = Positron::CommandRequest.new(
      id: "xyz",
      name: "does.not.exist",
      args: JSON.parse("{}")
    )
    result = registry.dispatch(request)

    result.success.should be_false
    error = result.error.not_nil!
    error.should contain("Unknown command")
    error.should contain("does.not.exist")
  end

  it "parses a JSON bridge payload into a CommandRequest" do
    json = %({"id":"req-1","name":"do_thing","args":{"flag":true}})
    request = Positron::CommandRegistry.parse(json)

    request.id.should eq("req-1")
    request.name.should eq("do_thing")
    request.args["flag"].as_bool.should be_true
  end

  it "parses a payload without args gracefully" do
    json = %({"id":"req-2","name":"no_args"})
    request = Positron::CommandRegistry.parse(json)

    request.id.should eq("req-2")
    request.name.should eq("no_args")
    request.args.as_h.should be_empty
  end

  it "generates a __positronResolve JS call with correct data" do
    request = Positron::CommandRequest.new(
      id: "js-1",
      name: "cmd",
      args: JSON.parse("{}")
    )
    result = Positron::CommandResult.new(
      success: true,
      data: JSON.parse(%({"value": 42}))
    )

    js = Positron::CommandRegistry.to_js_resolve(request, result)

    js.should contain("__positronResolve")
    js.should contain(%("js-1"))
    js.should contain("true")
    js.should contain(%({"value":42}))
  end

  it "includes error message in JS resolve when command fails" do
    request = Positron::CommandRequest.new(
      id: "js-2",
      name: "cmd",
      args: JSON.parse("{}")
    )
    result = Positron::CommandResult.new(
      success: false,
      data: JSON.parse("{}"),
      error: "Something went wrong"
    )

    js = Positron::CommandRegistry.to_js_resolve(request, result)

    js.should contain("false")
    js.should contain(%("Something went wrong"))
  end

  describe "execution contexts" do
    it "runs a :parallel handler's body off the dispatch fiber" do
      dispatcher = Fiber.current
      registry = Positron::CommandRegistry.new
      registry.register("cpu.burn", execution: :parallel) do |request|
        Positron::CommandResult.new(
          success: true,
          data: JSON.parse(%({"same_fiber": #{Fiber.current == dispatcher}}))
        )
      end

      result = registry.dispatch(Positron::CommandRequest.new(
        id: "p1", name: "cpu.burn", args: JSON.parse("{}")))
      result.success.should be_true
      result.data["same_fiber"].as_bool.should be_false
    end

    it "turns a crashing :parallel handler into an error result" do
      registry = Positron::CommandRegistry.new
      registry.register("cpu.boom", execution: :parallel) { |r| raise "burn exploded" }

      result = registry.dispatch(Positron::CommandRequest.new(
        id: "p2", name: "cpu.boom", args: JSON.parse("{}")))
      result.success.should be_false
      result.error.to_s.should contain("burn exploded")
    end

    it "rejects unknown execution symbols" do
      registry = Positron::CommandRegistry.new
      expect_raises ArgumentError, /unknown execution context/ do
        registry.register("bad", execution: :somewhere) { |r| Positron::CommandResult.new(success: true, data: JSON.parse("{}")) }
      end
    end
  end
end
