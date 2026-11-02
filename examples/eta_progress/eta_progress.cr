require "json"
require "../../src/positron"
require "./worker"

# tqdm-style multi-worker demo: `demo.start` launches 10 background
# workers (one async_work fiber each) at deliberately different speeds
# (~20 down to ~4 units/s, 100 units each — finishing in a visible
# stagger from ~5 s to ~25 s). Every worker reports a tqdm-style
# snapshot per tick (percent, elapsed, smoothed rate, ETA) as a
# `demo.worker.progress` event; the UI renders one colored bar per
# worker plus an overall bar. Colors are assigned by worker id in JS.
class EtaProgressApp < Positron::Application
  embed_application_files(__DIR__, "../../assets/crystal-icon")

  WORKER_COUNT =  10
  TOTAL_UNITS  = 100

  def configure_plugins
    use Positron::Plugins::Logger
  end

  def register_commands(registry : Positron::CommandRegistry)
    # Fire-and-forget (same pattern as async_progress): the command
    # resolves immediately with the fleet shape; progress flows to the
    # UI as events — the single supported notification channel.
    registry.register("demo.start") do |_request|
      WORKER_COUNT.times do |i|
        id = i + 1
        rate = 20.0 - i * 1.8 # 20.0, 18.2, ... 3.8 u/s

        async_work(name: "eta-worker-#{id}") do
          host.emit_to_js("demo.worker.started",
            {id: id, total: TOTAL_UNITS, rate: rate.round(1)})
          last = nil
          worker = EtaProgressDemo::Worker.new(id, TOTAL_UNITS, rate)
          worker.run { |snap| last = snap; host.emit_to_js("demo.worker.progress", snap) }
          host.emit_to_js("demo.worker.done",
            {id: id, elapsed_ms: last.try(&.elapsed_ms) || 0.0})
          nil
        end
      end

      Positron::CommandResult.new(
        success: true,
        data: JSON.parse({workers: WORKER_COUNT, total_units: WORKER_COUNT * TOTAL_UNITS}.to_json)
      )
    end
  end

  def on_ready
    webview.create(Positron::WebViewConfig.new(
      title: "Positron — ETA progress demo",
      width: 860,
      height: 720,
      close_to_tray: false,
      icon: icon_source(:svg)
    ))

    webview.bind("crystal") { |json| host.dispatch(json) }
    webview.load_html(application_html)
  end
end

EtaProgressApp.new.run
