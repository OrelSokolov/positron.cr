require "json"
require "../../src/positron"
require "./worker"

# Async worker with progress: a background job (Positron.async_work)
# sleeps 10 seconds and pushes a `demo.progress` event to the UI every
# second — elapsed t and its square t². The command resolves
# immediately with a job id (fire-and-forget pattern); the final
# result arrives as a `demo.done` event, so the promise never parks.
# `demo.ping` proves the host answers while the job runs.
class AsyncProgressApp < Positron::Application
  embed_application_files(__DIR__, "../../assets/crystal-icon")

  @next_job_id = 0

  def configure_plugins
    use Positron::Plugins::Logger
  end

  def register_commands(registry : Positron::CommandRegistry)
    # Fire-and-forget: launch the worker fiber and return at once.
    # Progress and the final result are delivered as events — the
    # single supported way to notify the UI from Crystal.
    registry.register("demo.start") do |request|
      job_id = (@next_job_id += 1)
      seconds = request.args["seconds"]?.try(&.as_i?) || 10

      async_work(name: "demo-job-#{job_id}") do
        host.emit_to_js("demo.started", {job: job_id, seconds: seconds})
        result = AsyncProgressDemo.run(seconds) do |elapsed, square|
          host.emit_to_js("demo.progress",
            {job: job_id, elapsed: elapsed, square: square})
        end
        host.emit_to_js("demo.done",
          {job: job_id, elapsed: result.elapsed, square: result.square})
        nil
      end

      Positron::CommandResult.new(
        success: true,
        data: JSON.parse({job: job_id, seconds: seconds}.to_json)
      )
    end

    # Responsiveness probe: answers instantly even mid-job, because the
    # job sleeps in its own fiber and never touches the GUI fiber.
    registry.register("demo.ping") do |_request|
      Positron::CommandResult.new(
        success: true,
        data: JSON.parse({pong: Time.utc.to_rfc3339}.to_json)
      )
    end
  end

  def on_ready
    webview.create(Positron::WebViewConfig.new(
      title: "Positron — async progress demo",
      width: 720,
      height: 520,
      close_to_tray: false,
      icon: icon_source(:svg)
    ))

    webview.bind("crystal") { |json| host.dispatch(json) }
    webview.load_html(application_html)
  end
end

AsyncProgressApp.new.run
