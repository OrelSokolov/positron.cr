require "json"

# True-parallel parallel_work for Crystal >= 1.21 (execution contexts).
#
# Selected by require-level gating in positron.cr: wrapping a def in
# {% if %} silently drops its block binding on Crystal 1.21.1, and a
# block-capturing call inside {% if %} fails to compile — both verified
# on 1.21.1. Plain defs in a gated file avoid the whole class of bugs.

module Positron
  # Run a block with true parallelism — on a worker thread of the
  # shared Fiber::ExecutionContext::Parallel pool. Use this for
  # CPU-bound work: tight loops that would otherwise starve the
  # cooperative scheduler and freeze the GUI.
  #
  # The block runs in parallel to the GUI fiber and MUST NOT touch the
  # UI or GTK state. Deliver results via the return value (it is
  # JSON-serialized across the thread boundary, so no mutable object
  # graph is shared) and update the UI with `Positron.on_main`. Block
  # errors arrive under "_parallel_error".
  # The `-> _` annotation is load-bearing (see async_work.cr).
  def self.parallel_work(*, name : String = "parallel_work", &block : -> _)
    channel = Channel(JSON::Any).new(1)
    parallel_context.spawn(name: name) do
      result =
        begin
          JSON.parse(block.call.to_json)
        rescue ex
          JSON.parse({"_parallel_error" => ex.message}.to_json)
        end
      channel.send(result)
    end
    AsyncWork::Task.new(channel)
  end

  # The shared worker pool for parallel_work. Threads spawn on demand
  # and idle workers park themselves, so one modest pool serves the
  # whole app.
  @@parallel_ctx : Fiber::ExecutionContext::Parallel?

  def self.parallel_context : Fiber::ExecutionContext::Parallel
    @@parallel_ctx ||= Fiber::ExecutionContext::Parallel.new(
      "positron-parallel",
      System.cpu_count.try(&.clamp(2, 8)) || 4)
  end

  # One job, `threads` workers: the block runs once per worker on a
  # Parallel worker thread (index 0...threads — split the work by it),
  # all sharing a single pause/cancel token. CPU-bound jobs finish
  # ~n times faster. Same contract as parallel_work: never touch the
  # UI inside the block; each worker's return value crosses as JSON
  # (null if cancelled), `job.value` aggregates them as
  # `{"results": [...], "cancelled": bool}`.
  def self.async_work_n_threads(*, threads : Int32 = 2,
                                name : String = "async_work_n_threads",
                                &block : AsyncWork::Token, Int32 -> _)
    count = {threads, 1}.max
    job = AsyncWork::Job.new(name, count)
    count.times do |i|
      parallel_context.spawn(name: "#{name}-w#{i}") do
        job.run_worker { |token| block.call(token, i) }
      end
    end
    job
  end

  # Framework-internal typed variant: run the block on a worker thread
  # and return its value as-is (no JSON round-trip). Used by
  # CommandRegistry for `execution: :parallel` handlers — CommandResult
  # is an immutable record, safe to hand across the boundary. The
  # block must not raise (wrap internally) and must not touch the UI.
  def self.run_parallel(&block : -> T) : T forall T
    if Positron.gui_context?
      raise "run_parallel/.value on the GUI fiber would park the UI " \
            "loop — dispatch through Host#dispatch or await from a " \
            "background task."
    end
    channel = Channel(T).new
    parallel_context.spawn do
      channel.send(block.call)
    end
    channel.receive
  end
end
