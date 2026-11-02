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
