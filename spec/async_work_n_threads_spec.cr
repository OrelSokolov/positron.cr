require "../examples/async_work_n_threads/worker"
require "spec"

# The N-workers demo's core claims, exercised headlessly:
#
#   1. the static split is lossless — every unit is burned exactly
#      once, whatever the worker count;
#   2. the XOR checksum is order-independent — identical for 1 and 4
#      workers (and equal to the inline reference);
#   3. cancel! aborts all workers at chunk boundaries;
#   4. (Crystal >= 1.21) N workers really run in parallel — the same
#      job finishes measurably faster than on one worker.
describe NThreadsDemo do
  it "burns every unit exactly once for any worker count" do
    [1, 3].each do |workers|
      job, progress = NThreadsDemo.start(2_000_000_i64, workers)
      value = job.value

      progress.get.should eq(2_000_000)
      value["cancelled"].as_bool.should be_false
      value["results"].as_a.size.should eq(workers)
    end
  end

  it "produces the same order-independent checksum for 1 and 4 workers" do
    one, _ = NThreadsDemo.start(1_000_000_i64, 1)
    four, _ = NThreadsDemo.start(1_000_000_i64, 4)

    one_checksum = one.value["results"].as_a.reduce(0_i64) { |a, r| a ^ r.as_i64 }
    four_checksum = four.value["results"].as_a.reduce(0_i64) { |a, r| a ^ r.as_i64 }

    one_checksum.should eq(four_checksum)
    one_checksum.should eq(NThreadsDemo.checksum(1_000_000_i64))
  end

  it "stop cancels every worker" do
    job, progress = NThreadsDemo.start(NThreadsDemo::TOTAL_UNITS, 4)

    # Let the workers spin up and land a few chunks, then cancel.
    sleep 100.milliseconds
    job.cancel!
    value = job.value

    value["cancelled"].as_bool.should be_true
    progress.get.should be < NThreadsDemo::TOTAL_UNITS
  end

  {% if compare_versions(Crystal::VERSION, "1.21.0") >= 0 %}
    it "finishes the job measurably faster with 4 workers" do
      total = 100_000_000_i64

      t0 = Time.instant
      one, _ = NThreadsDemo.start(total, 1)
      one.value
      serial = Time.instant - t0

      # Warm the pool: after a long single-worker run the other pool
      # threads are asleep, and freshly spawned workers can all land on
      # the one awake thread (serialized timing). A handful of parked
      # warm-up fibers forces the workers to spread across threads.
      warm = 4.times.map { Positron.parallel_work { ::sleep(50.milliseconds) } }.to_a

      t0 = Time.instant
      four, _ = NThreadsDemo.start(total, 4)
      four.value
      parallel = Time.instant - t0
      warm.each(&.value)

      # 4 workers on separate Parallel threads: generously below the
      # serial time even on busy/noisy runners (same slack style as
      # the parallel_work spec).
      parallel.total_milliseconds.should be < serial.total_milliseconds * 0.8
    end
  {% end %}
end
