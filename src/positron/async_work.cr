require "json"

module Positron
  # The single rule for background work in positron apps.
  #
  # Crystal fibers are cooperative and single-threaded: a CPU-bound loop
  # in a fiber still freezes the GUI loop, and waiting on the GUI fiber
  # deadlocks the whole UI. Every place that needs work "somewhere else"
  # must go through this module — the framework itself uses it for
  # command dispatch, so app code and framework code follow the same
  # discipline:
  #
  #   Positron.async_work { ... }     # concurrent: run in a fiber
  #                                    # (IO, subprocesses, timers — anything
  #                                    # that waits; do NOT tight-loop here)
  #
  #   Positron.parallel_work { ... }  # truly parallel: run on a worker
  #                                    # thread (Fiber::ExecutionContext::
  #                                    # Parallel, Crystal >= 1.21) — for
  #                                    # CPU-bound loops. Never touch the
  #                                    # UI inside; the return value
  #                                    # crosses as JSON and errors
  #                                    # arrive as "_parallel_error".
  #
  #   Positron.async_job { |token| }  # cancellable/pausable async_work:
  #                                    # the token is the cooperative
  #                                    # stop/pause signal (job.cancel!,
  #                                    # job.pause!, job.resume!)
  #
  #   Positron.async_work_n_threads(threads: n) { |token, i| }
  #                                    # one job, n workers on parallel
  #                                    # threads sharing a single token —
  #                                    # CPU-bound work finishes ~n times
  #                                    # faster. Pause/cancel work the
  #                                    # same way.
  #
  #   task.value                      # await a result (parks the calling
  #                                    # fiber; refuses to run on the GUI
  #                                    # fiber — that would freeze the UI)
  #
  #   Positron.on_main { ... }        # touch the UI safely from any fiber
  #
  # The mistake this API makes impossible: awaiting a result (or
  # spinning) on the GUI fiber, which is exactly the "whole window
  # froze" bug class.
  module AsyncWork
    # Raised inside a job block at the first checkpoint after
    # `Job#cancel!` (Crystal fibers are cooperative — there is no
    # forced kill, cancellation is a raised signal the worker observes
    # at `Token#checkpoint!` / `Token#sleep`).
    class Cancelled < Exception
      def initialize(message = "job cancelled")
        super(message)
      end
    end

    # The shared pause/cancel signal for a Job. Flags are atomic, so a
    # token is safe to flip from the GUI fiber (or any thread) while
    # workers poll it — including workers on Parallel execution-context
    # threads.
    class Token
      private PAUSED    = 1
      private CANCELLED = 2
      private POLL      = 20.milliseconds
      private SLICE     = 25.milliseconds

      def initialize
        @flags = Atomic(Int32).new(0)
      end

      def pause! : Nil
        @flags.or(PAUSED)
      end

      def resume! : Nil
        @flags.and(~PAUSED)
      end

      def cancel! : Nil
        @flags.or(CANCELLED)
      end

      def paused? : Bool
        (@flags.get & PAUSED) > 0
      end

      def cancelled? : Bool
        (@flags.get & CANCELLED) > 0
      end

      # Cooperative checkpoint: raises Cancelled if the job was
      # cancelled, parks the calling fiber (cheap polling) while the
      # job is paused. Workers should call this between chunks of work.
      def checkpoint! : Nil
        loop do
          raise Cancelled.new if cancelled?
          break unless paused?
          ::sleep(POLL)
        end
      end

      # A cancellable, pausable sleep: sliced into SLICE-sized naps so
      # pause parks the worker and cancel raises within ~25 ms. Use it
      # instead of Kernel#sleep inside job blocks.
      def sleep(span : Time::Span) : Nil
        remaining = span
        while remaining > Time::Span::ZERO
          checkpoint!
          nap = remaining < SLICE ? remaining : SLICE
          ::sleep(nap)
          remaining -= nap
        end
      end
    end

    # A handle to a running async_job / async_work_n_threads block:
    # pause!/resume!/cancel! control the workers, `.value` awaits the
    # aggregated result. All controls are thread-safe and may be called
    # from the GUI fiber (they only flip atomic flags).
    class Job
      getter name : String
      getter worker_count : Int32
      getter token : Token

      @cached_value : JSON::Any?

      def initialize(@name : String, @worker_count : Int32)
        @token = Token.new
        @results = Channel(JSON::Any).new(@worker_count)
        @finished = Atomic(Int32).new(0)
        @mutex = Mutex.new
        @cached_value = nil
      end

      def pause! : Nil
        @token.pause!
      end

      def resume! : Nil
        @token.resume!
      end

      def cancel! : Nil
        @token.cancel!
      end

      def paused? : Bool
        @token.paused?
      end

      def cancelled? : Bool
        @token.cancelled?
      end

      # True once every worker has finished (normally or cancelled).
      def done? : Bool
        @finished.get >= @worker_count
      end

      # Await all workers. Parks the calling fiber (same GUI guard as
      # Task#value). Returns `{"results": [per-worker values],
      # "cancelled": bool}` — workers aborted by cancel! contribute
      # null results, worker errors arrive as "_worker_error" entries.
      def value : JSON::Any
        if Positron.gui_context?
          raise "async_job/.value called on the GUI fiber: awaiting " \
                "here would freeze the UI. Await from a background " \
                "task or deliver the result via Positron.on_main."
        end
        @mutex.synchronize do
          @cached_value ||= begin
            results = Array(JSON::Any).new(@worker_count) { @results.receive }
            JSON.parse({results: results, cancelled: @token.cancelled?}.to_json)
          end
        end
      end

      # Framework-internal: run one worker block to completion, capture
      # its result (or cancellation) and mark it finished. Called once
      # per worker by async_job / async_work_n_threads.
      def run_worker(&block : Token -> _)
        result =
          begin
            JSON.parse(block.call(@token).to_json)
          rescue ex : Cancelled
            JSON.parse("null")
          rescue ex
            JSON.parse({"_worker_error" => ex.message}.to_json)
          end
        @results.send(result)
        @finished.add(1)
      end
    end

    # A handle to a running async_work/parallel_work block. `.value`
    # awaits the result.
    class Task
      def initialize(@channel : Channel(JSON::Any))
      end

      # Await the block's result. Parks the calling fiber until the
      # work finishes. Raises if called from the GUI fiber — waiting
      # there would freeze the UI; deliver results with
      # `Positron.on_main` instead, or await inside another
      # async_work block.
      def value : JSON::Any
        if Positron.gui_context?
          raise "async_work/parallel_work .value called on the GUI " \
                "fiber: awaiting here would freeze the UI. Await from " \
                "a background task or deliver the result via " \
                "Positron.on_main."
        end
        @channel.receive
      end
    end
  end

  # Is the current fiber the GUI fiber (the one running the native
  # loop)? Background helpers refuse to block when this is true.
  def self.gui_context? : Bool
    Host.current.try(&.gui_context?) || false
  end

  # Run a block concurrently in a fiber — the default for work that
  # waits (IO, subprocesses, sleeps, channels). CPU-tight loops must
  # use parallel_work instead: without preemption they would still
  # starve the GUI loop. Errors are captured into the result under
  # "_async_error".
  #
  # The `-> _` annotation is load-bearing: on Crystal 1.21.1 calling an
  # unannotated zero-arg block (`&block`) silently discards the block's
  # return value — every task would resolve to null.
  def self.async_work(*, name : String = "async_work", &block : -> _)
    channel = Channel(JSON::Any).new(1)
    spawn(name: name) do
      result =
        begin
          JSON.parse(block.call.to_json)
        rescue ex
          JSON.parse({"_async_error" => ex.message}.to_json)
        end
      channel.send(result)
    end
    AsyncWork::Task.new(channel)
  end

  # Cancellable, pausable async_work. The block receives a shared
  # `AsyncWork::Token`: `token.sleep` / `token.checkpoint!` are the
  # cooperative stop/pause points (see AsyncWork::Token). Returns an
  # `AsyncWork::Job` handle whose pause!/resume!/cancel! may be called
  # from any fiber (they only flip atomic flags). Block errors arrive
  # under "_worker_error" in `job.value`.
  def self.async_job(*, name : String = "async_job", &block : AsyncWork::Token -> _)
    job = AsyncWork::Job.new(name, 1)
    spawn(name: name) { job.run_worker(&block) }
    job
  end

  # parallel_work lives in async_work_parallel.cr (true parallelism on
  # Crystal >= 1.21 execution contexts) or async_work_fallback.cr
  # (concurrent fiber on older toolchains). The split is done with
  # require-level gating in positron.cr: Fiber::ExecutionContext does
  # not exist on older toolchains, and {% if %} around defs/calls with
  # block capture has rough edges on 1.21.1 — a separate file is the
  # clean cut.

  # Run a block on the GUI fiber. The supported way to touch the UI or
  # evaluate JS from a background task. Without a running host the
  # block runs immediately (tests, scripts).
  def self.on_main(&block : ->) : Nil
    if host = Host.current
      host.run_on_main(&block)
    else
      block.call
    end
  end
end
