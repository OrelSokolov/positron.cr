require "json"

# Fallback parallel_work for Crystal < 1.21 (no execution contexts).
#
# Selected by require-level gating in positron.cr. The block runs in a
# plain fiber: concurrent, not parallel. GUI safety is preserved only
# if the block yields or waits; tight loops will still starve the
# scheduler. The result carries "_parallel_fallback" so callers can
# detect the degraded mode.

module Positron
  # The `-> _` annotation is load-bearing (see async_work.cr).
  def self.parallel_work(*, name : String = "parallel_work", &block : -> _)
    channel = Channel(JSON::Any).new(1)
    spawn(name: name) do
      result =
        begin
          JSON.parse({"_parallel_fallback" => true, "value" => JSON.parse(block.call.to_json)}.to_json)
        rescue ex
          JSON.parse({"_parallel_error" => ex.message}.to_json)
        end
      channel.send(result)
    end
    AsyncWork::Task.new(channel)
  end

  # Framework-internal typed variant (see async_work_parallel.cr): no
  # parallelism on this toolchain — the block runs inline on the
  # calling fiber (same semantics for callers, no worker thread).
  def self.run_parallel(&block : -> T) : T forall T
    yield
  end

  # async_work_n_threads fallback (see async_work_parallel.cr): the
  # workers run as plain fibers — concurrent, not parallel, so a
  # CPU-bound job is NOT n times faster here (pause/cancel semantics
  # are identical). Real parallelism needs Crystal >= 1.21.
  def self.async_work_n_threads(*, threads : Int32 = 2,
                                name : String = "async_work_n_threads",
                                &block : AsyncWork::Token, Int32 -> _)
    count = {threads, 1}.max
    job = AsyncWork::Job.new(name, count)
    count.times do |i|
      spawn(name: "#{name}-w#{i}") do
        job.run_worker { |token| block.call(token, i) }
      end
    end
    job
  end
end
