require "json"
require "../../src/positron"
require "./worker"

# Pause/stop demo: `demo.start` launches a cancellable background job
# (Positron.async_job — async_work plus a shared Token). The job runs
# TOTAL_SECONDS units (one per second) and pushes `demo.progress`
# events; `demo.pause` / `demo.resume` flip the token's pause flag (the
# job's token.sleep parks while paused), `demo.stop` cancels it (the
# next checkpoint raises AsyncWork::Cancelled and the job finishes with
# cancelled=true). The start command resolves immediately — fire and
# forget, same pattern as async_progress.
class PauseStopApp < Positron::Application
  embed_application_files(__DIR__, "../../assets/crystal-icon")

  TOTAL_SECONDS = 30

  @job : Positron::AsyncWork::Job?
  @job_id = 0

  def configure_plugins
    use Positron::Plugins::Logger
  end

  def register_commands(registry : Positron::CommandRegistry)
    registry.register("demo.start") do |_request|
      job_id = (@job_id += 1)

      job = async_job(name: "demo-job-#{job_id}") do |token|
        host.emit_to_js("demo.started",
          {job: job_id, total: TOTAL_SECONDS})
        result = PauseStopDemo.run(TOTAL_SECONDS, token) do |done|
          host.emit_to_js("demo.progress",
            {job: job_id, done: done, total: TOTAL_SECONDS,
             paused: token.paused?})
        end
        host.emit_to_js("demo.done",
          {job: job_id, done: result.units_done, total: TOTAL_SECONDS,
           cancelled: result.cancelled, elapsed_ms: result.elapsed_ms.round(1)})
        nil
      end
      @job = job

      Positron::CommandResult.new(
        success: true,
        data: JSON.parse({job: job_id, total: TOTAL_SECONDS}.to_json)
      )
    end

    registry.register("demo.pause") do
      control("pause") do |job|
        job.pause!
        {paused: true}
      end
    end

    registry.register("demo.resume") do
      control("resume") do |job|
        job.resume!
        {paused: false}
      end
    end

    registry.register("demo.stop") do
      control("stop") do |job|
        job.cancel!
        {stopping: true}
      end
    end
  end

  def on_ready
    webview.create(Positron::WebViewConfig.new(
      title: "Positron — pause & stop demo",
      width: 720,
      height: 560,
      close_to_tray: false,
      icon: icon_source(:svg)
    ))

    webview.bind("crystal") { |json| host.dispatch(json) }
    webview.load_html(application_html)
  end

  private def control(action, &flip : Positron::AsyncWork::Job -> _)
    if (job = @job) && !job.done?
      data = flip.call(job)
      Positron::CommandResult.new(
        success: true,
        data: JSON.parse(data.to_json)
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

{% if flag?(:android) %}
  # Mobile: the native shim owns the lifecycle; register the app for
  # the host thread boot (see src/positron/entry/android.cr).
  Positron::EntryAndroid.app(PauseStopApp)
{% else %}
  PauseStopApp.new.run
{% end %}
