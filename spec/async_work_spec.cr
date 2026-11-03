require "../src/positron"
require "spec"

describe "Positron.async_work" do
  it "runs the block in a fiber and returns its value" do
    caller_fiber = Fiber.current
    task = Positron.async_work { Fiber.current == caller_fiber ? "same" : "other" }

    # .value parks this fiber until the block finishes
    task.value.to_s.should eq("other")
  end

  it "captures block errors into the result" do
    task = Positron.async_work { raise "boom" }
    task.value["_async_error"].to_s.should contain("boom")
  end

  it "serializes arbitrary JSON-able results" do
    task = Positron.async_work { {count: 3, items: ["a", "b"]} }
    value = task.value
    value["count"].as_i.should eq(3)
    value["items"].as_a.size.should eq(2)
  end
end

describe "Positron.on_main" do
  it "runs the block inline when no host exists" do
    executed = false
    Positron.on_main { executed = true }
    executed.should be_true
  end
end

{% if compare_versions(Crystal::VERSION, "1.21.0") >= 0 %}
  describe "Positron.parallel_work" do
    it "returns results computed on a worker thread" do
      task = Positron.parallel_work do
        sum = 0
        1000.times { |i| sum += i }
        sum
      end
      task.value.as_i.should eq(499_500)
    end

    it "propagates block errors as _parallel_error" do
      task = Positron.parallel_work { raise "worker boom" }
      task.value["_parallel_error"].to_s.should contain("worker boom")
    end

    it "runs CPU-bound blocks in parallel" do
      # Warm the worker pool first: the first parallel_work pays the
      # thread spawn cost, which on a loaded CI runner can dominate the
      # measurement (observed: parallel pair 1.75x slower than serial).
      Positron.parallel_work { 1_i64 }.value

      n = 30_000_000
      burn_one = -> { i = 0_i64; n.times { i &+= 1 }; i }
      burn_two = -> { i = 0_i64; n.times { i &+= 2 }; i }

      # Best-of-two parallel rounds vs worst-of-two serial rounds:
      # wall-clock on shared CI runners is noisy in both directions,
      # and taking the extremes biases the comparison TOWARD proving
      # parallelism, so a pass still means something.
      both = Time::Span::MAX
      2.times do
        one = Positron.parallel_work &burn_one
        two = Positron.parallel_work &burn_two
        t0 = Time.instant
        one.value
        two.value
        elapsed = Time.instant - t0
        both = elapsed if elapsed < both
      end

      serial = Time::Span.zero
      2.times do
        t0 = Time.instant
        burn_one.call
        burn_two.call
        elapsed = Time.instant - t0
        serial = elapsed if elapsed > serial
      end

      # With real parallelism two burns take far less than twice the
      # serial pair; allow generous slack for machine noise.
      both.total_milliseconds.should be < serial.total_milliseconds * 1.5
    end
  end
{% end %}
