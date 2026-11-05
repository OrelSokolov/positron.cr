require "json"
require "time"
require "../../src/positron"
require "./burn"

# Autotest tracing: log every eval_js dispatched by the adapter and
# every command dispatched by the host, so a scripted xvfb run shows
# exactly which command runs when (gated by DEMO_AUTOTEST — zero cost
# otherwise).
{% if flag?(:linux) %}
  class Positron::Adapters::Linux::WebKitGTK
    def eval_js(script : String)
      if ENV["DEMO_AUTOTEST"]?
        STDERR.puts "[autotest] eval_js: #{script.lines.first?.try(&.[0, 100])}"
        STDERR.flush
      end
      previous_def
    end
  end

  class Positron::Host
    def dispatch_now(json : String) : String
      if ENV["DEMO_AUTOTEST"]?
        STDERR.puts "[autotest] dispatch: #{json[0, 120]}"
        STDERR.flush
      end
      previous_def
    end
  end
{% end %}

# Scheduler demo app: how CPU-bound work interacts with Crystal's
# cooperative single-threaded scheduler (see burn.cr for the three
# burn strategies and the catch being demonstrated).
#
# Freeze indicator: the web process runs JS timers independently of
# the host, so a JS clock keeps ticking even while the host is frozen.
# The host therefore emits a "demo.tick" event every 250 ms; the
# frontend shows the tick age — when it stalls, the host loop is
# blocked.
class SchedulerDemoApp < Positron::Application
  embed_application_files(__DIR__, "../../assets/crystal-icon")

  def configure_plugins
    use Positron::Plugins::Logger
  end

  def register_commands(registry : Positron::CommandRegistry)
    registry.register("demo.freeze") do |request|
      burn_result { SchedulerDemo.freeze_burn(seconds(request)) }
    end

    registry.register("demo.busy") do |request|
      burn_result { SchedulerDemo.yielding_burn(seconds(request)) }
    end

    registry.register("demo.isolated", execution: :parallel) do |request|
      # Declaring execution: :parallel lets the framework run this
      # handler body on a worker thread — the CPU burn cannot freeze
      # the GUI, and the handler code stays a plain loop.
      burn_result { SchedulerDemo.freeze_burn(seconds(request)) }
    end

    # Autotest logging hook: the control run intercepts Positron.call
    # and reports the JS stack of every call, to pinpoint autonomous
    # command sources.
    registry.register("demo.log") do |request|
      STDERR.puts "[autotest] js: #{request.args["line"]?.try(&.to_s)}"
      STDERR.flush
      Positron::CommandResult.new(success: true, data: JSON.parse("null"))
    end

    # Autotest hook (DEMO_AUTOTEST=1): the JS side reports end-to-end
    # promise latency so the scheduler behaviour can be measured
    # without clicking (see on_ready). Quits the app after reporting
    # (or on a 60 s watchdog) for scripted xvfb runs.
    registry.register("demo.report") do |request|
      STDERR.puts "[autotest] report: #{request.args.to_json}"
      STDERR.flush
      spawn do
        sleep 100.milliseconds
        host.try(&.stop)
      end
      Positron::CommandResult.new(success: true, data: JSON.parse("null"))
    end
  end

  def on_ready
    webview.create(Positron::WebViewConfig.new(
      title: "Positron — scheduler demo",
      width: 720,
      height: 520,
      close_to_tray: false,
      icon: icon_source(:svg)
    ))

    webview.bind("crystal") { |json| host.dispatch(json) }
    webview.load_html(application_html)

    # Host heartbeat: proves the Crystal loop is alive from JS.
    spawn do
      loop do
        sleep 250.milliseconds
        host.emit_to_js("demo.tick", {t: Time.utc.to_rfc3339, pid: Process.pid})
      end
    end

    # Autotest (DEMO_AUTOTEST=freeze|busy|isolated): click the button
    # from JS after the page settles, report end-to-end promise latency,
    # quit. Any other value enables tracing only (no click) — a control
    # run proving the page issues no commands on its own.
    if ENV["DEMO_AUTOTEST"]?
      command = case ENV["DEMO_AUTOTEST"]?
                when "freeze"   then "demo.freeze"
                when "isolated" then "demo.isolated"
                when "busy"     then "demo.busy"
                else                 nil
                end
      seconds = (ENV["DEMO_AUTOTEST_SECONDS"]? || "2").to_i
      spawn do
        sleep 3000.milliseconds
        if command
          STDERR.puts "[autotest] click: #{command} #{seconds}s"
          STDERR.flush
          host.eval_js(<<-JS)
            (function(){
              var t0 = performance.now();
              Positron.call(#{command.to_json}, {seconds: #{seconds}}).then(
                function(r) {
                  Positron.call('demo.report', {
                    jsMs: Math.round(performance.now() - t0),
                    hostMs: r && r.ms
                  });
                },
                function(e) {
                  Positron.call('demo.report', {jsMs: -1, hostMs: -1, err: String(e)});
                }
              );
            })();
          JS
        else
          STDERR.puts "[autotest] control run: intercepting Positron.call"
          STDERR.flush
          host.eval_js(<<-JS)
            (function(){
              var orig = Positron.call.bind(Positron);
              Positron.call = function(name, args) {
                if (name !== 'demo.log') {
                  try {
                    orig('demo.log', {line: 'CALL ' + name + ' :: ' +
                      String((new Error().stack || '').split('\\n').slice(1, 5).join(' | '))});
                  } catch (e) {}
                }
                return orig(name, args);
              };
            })();
          JS
        end
      end
      spawn do
        sleep 60.seconds
        STDERR.puts "[autotest] TIMEOUT: promise never resolved"
        STDERR.flush
        exit 2
      end
    end
  end

  private def seconds(request : Positron::CommandRequest) : Int32
    request.args["seconds"]?.try(&.as_i?) || 10
  end

  private def burn_result(& : -> T) forall T
    t0 = Time.instant
    value = yield
    Positron::CommandResult.new(
      success: true,
      data: JSON.parse({value: value, ms: (Time.instant - t0).total_milliseconds.round(1)}.to_json)
    )
  end
end

{% if flag?(:android) %}
  # Mobile: the native shim owns the lifecycle; register the app for
  # the host thread boot (see src/positron/entry/android.cr).
  Positron::EntryAndroid.app(SchedulerDemoApp)
{% else %}
  SchedulerDemoApp.new.run
{% end %}
