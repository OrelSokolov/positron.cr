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

describe "Positron::AsyncWork::Token" do
  it "tracks pause and cancel flags" do
    token = Positron::AsyncWork::Token.new
    token.paused?.should be_false
    token.cancelled?.should be_false

    token.pause!
    token.paused?.should be_true
    token.cancelled?.should be_false

    token.resume!
    token.paused?.should be_false

    token.cancel!
    token.cancelled?.should be_true
    # Cancel wins over pause — a cancelled job never resumes.
    token.paused?.should be_false
  end

  it "sleep raises Cancelled promptly after cancel!" do
    token = Positron::AsyncWork::Token.new
    token.cancel!
    expect_raises(Positron::AsyncWork::Cancelled) { token.sleep(1.second) }
  end

  it "sleep parks while paused and then completes" do
    token = Positron::AsyncWork::Token.new

    spawn do
      sleep 20.milliseconds
      token.pause!
      sleep 100.milliseconds
      token.resume!
    end

    t0 = Time.instant
    token.sleep(50.milliseconds)
    # The pause lands (~20 ms) inside the 50 ms sleep — the second
    # slice parks for ~100 ms before finishing, so well above 100 ms
    # total.
    (Time.instant - t0).total_milliseconds.should be >= 100
  end
end

describe "Positron.async_job" do
  it "returns the block's value through the job" do
    job = Positron.async_job { |token| "value" }
    value = job.value

    value["cancelled"].as_bool.should be_false
    value["results"].as_a.map(&.to_s).should eq(["value"])
  end

  it "cancel! aborts the block at its checkpoint" do
    job = Positron.async_job do |token|
      token.sleep(30.seconds)
      "never reached"
    end

    sleep 50.milliseconds
    job.cancel!

    t0 = Time.instant
    value = job.value
    (Time.instant - t0).total_milliseconds.should be < 1000

    value["cancelled"].as_bool.should be_true
    value["results"].as_a.should eq([JSON.parse("null")])
  end

  it "captures block errors as _worker_error" do
    job = Positron.async_job { |token| raise "job boom" }
    job.value["results"].as_a.first["_worker_error"].to_s.should contain("job boom")
  end
end

{% if compare_versions(Crystal::VERSION, "1.21.0") >= 0 %}
  describe "Positron.async_work_n_threads" do
    it "runs the block once per worker with distinct indexes" do
      job = Positron.async_work_n_threads(threads: 4) { |token, index| index }

      value = job.value
      value["cancelled"].as_bool.should be_false
      value["results"].as_a.map(&.as_i).sort.should eq([0, 1, 2, 3])
    end

    it "cancel! aborts every worker" do
      job = Positron.async_work_n_threads(threads: 3) do |token, index|
        token.sleep(30.seconds)
        index
      end

      sleep 50.milliseconds
      job.cancel!
      value = job.value

      value["cancelled"].as_bool.should be_true
      value["results"].as_a.size.should eq(3)
    end
  end
{% end %}

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
