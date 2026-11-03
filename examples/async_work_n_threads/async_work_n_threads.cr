require "json"
require "../../src/positron"
require "./worker"

# N-workers demo: one CPU-bound job (NThreadsDemo::TOTAL_UNITS hash
# units) executed by `Positron.async_work_n_threads` — the block runs
# once per worker on a Parallel worker thread, each burning an equal
# static slice, so N workers finish ~N times faster. All workers share
# one Token: `demo.pause` / `demo.resume` / `demo.stop` control the
# whole fleet at once. Progress is polled from a coordinator fiber
# (workers run on threads and must not touch the UI) and pushed as
# `demo.progress` events.
class NThreadsApp < Positron::Application
  embed_application_files(__DIR__, "../../assets/crystal-icon")

  @job : Positron::AsyncWork::Job?
  @job_id = 0

  def configure_plugins
    use Positron::Plugins::Logger
  end

  def register_commands(registry : Positron::CommandRegistry)
    registry.register("demo.start") do |request|
      job_id = (@job_id += 1)
      workers = request.args["workers"]?.try(&.as_i?) || 4
      workers = workers.clamp(1, 8)

      job, progress = NThreadsDemo.start(NThreadsDemo::TOTAL_UNITS, workers)
      @job = job

      # Coordinator: workers live on Parallel threads and never touch
      # the UI — this fiber polls their shared atomic counter and
      # emits progress, then awaits the aggregated result.
      async_work(name: "nthreads-report-#{job_id}") do
        total = NThreadsDemo::TOTAL_UNITS
        t0 = Time.instant
        host.emit_to_js("demo.started",
          {job: job_id, workers: workers, total: total})

        until job.done?
          sleep 100.milliseconds
          host.emit_to_js("demo.progress",
            {job: job_id, done: progress.get, total: total,
             workers: workers, paused: job.paused?})
        end

        value = job.value
        checksum = value["results"].as_a.reduce(0_i64) { |acc, r| acc ^ (r.as_i64? || 0) }
        host.emit_to_js("demo.done",
          {job: job_id, workers: workers, done: progress.get, total: total,
           cancelled: value["cancelled"].as_bool,
           checksum: checksum,
           elapsed_ms: (Time.instant - t0).total_milliseconds.round(1)})
        nil
      end

      Positron::CommandResult.new(
        success: true,
        data: JSON.parse({job: job_id, workers: workers, total: NThreadsDemo::TOTAL_UNITS}.to_json)
      )
    end

    registry.register("demo.pause") do
      control { |job| job.pause!; {paused: true} }
    end

    registry.register("demo.resume") do
      control { |job| job.resume!; {paused: false} }
    end

    registry.register("demo.stop") do
      control { |job| job.cancel!; {stopping: true} }
    end
  end

  def on_ready
    webview.create(Positron::WebViewConfig.new(
      title: "Positron — N workers demo",
      width: 820,
      height: 640,
      close_to_tray: false,
      icon: icon_source(:svg)
    ))

    webview.bind("crystal") { |json| host.dispatch(json) }
    webview.load_html(application_html)
  end

  private def control(&flip : Positron::AsyncWork::Job -> _)
    if (job = @job) && !job.done?
      Positron::CommandResult.new(
        success: true,
        data: JSON.parse(flip.call(job).to_json)
      )
    else
      Positron::CommandResult.new(
        success: false,
        data: JSON.parse("{}"),
        error: "воркер не запущен"
      )
    end
  end
end

NThreadsApp.new.run
