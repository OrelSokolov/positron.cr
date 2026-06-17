require "uri"
require "json"
require "time"
require "../src/crystal_ui"

class HelloApp < CrystalUI::Application
  ICON_PATH = File.expand_path("../assets/crystal-icon.svg", __DIR__)

  def register_commands(registry)
    command_registry
  end

  def on_ready
    webview.create(
      title: "CrystalUI",
      width: 900,
      height: 640,
      icon_path: ICON_PATH
    )

    webview.bind("crystal") do |json|
      STDOUT.puts "[Crystal Host] received from JS: #{json}"
      STDOUT.flush
      CrystalUI::EventBus.emit("command.invoked", JSON.parse(json))
      ""
    end

    webview.navigate("data:text/html,#{URI.encode_path(demo_html)}")

    tray.set_icon(File.read(ICON_PATH).to_slice)
    tray.set_title("CrystalUI")
    tray.add_or_update_item(CrystalUI::TrayItem.new(id: 1, title: "Open"))
    tray.add_or_update_item(CrystalUI::TrayItem.new(id: 2, title: "Quit"))
    tray.on_item_click do |id|
      case id
      when 1 then webview.show
      when 2 then stop
      end
    end
    tray.show
  end

  @[CrystalUI::Command]
  def hello : Hash(String, String)
    {
      "message" => "Hello from the Crystal Host!",
      "time"    => Time.utc.to_rfc3339,
      "pid"     => Process.pid.to_s,
    }
  end

  def stop
    host = @host
    host.stop if host
  end

  private def demo_html : String
    crystal_svg = File.read(ICON_PATH)

    <<-HTML
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>CrystalUI</title>
      <style>
        :root {
          --blue-50: #eff6ff;
          --blue-100: #dbeafe;
          --blue-200: #bfdbfe;
          --blue-300: #93c5fd;
          --blue-400: #60a5fa;
          --blue-500: #3b82f6;
          --blue-600: #2563eb;
          --blue-700: #1d4ed8;
          --blue-800: #1e40af;
          --blue-900: #1e3a8a;
          --shadow: 0 25px 50px -12px rgba(29, 78, 216, 0.35);
        }

        * { box-sizing: border-box; }

        body {
          margin: 0;
          min-height: 100vh;
          display: flex;
          align-items: center;
          justify-content: center;
          font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
          background: radial-gradient(ellipse at top, var(--blue-50), #ffffff),
                      linear-gradient(135deg, #ffffff 0%, var(--blue-100) 100%);
          overflow: hidden;
        }

        /* Animated background orbs */
        .orb {
          position: absolute;
          border-radius: 50%;
          filter: blur(80px);
          opacity: 0.5;
          animation: drift 20s ease-in-out infinite;
        }
        .orb-1 {
          width: 400px; height: 400px;
          background: var(--blue-300);
          top: -100px; left: -100px;
          animation-delay: 0s;
        }
        .orb-2 {
          width: 300px; height: 300px;
          background: var(--blue-400);
          bottom: -80px; right: -80px;
          animation-delay: -7s;
        }
        .orb-3 {
          width: 200px; height: 200px;
          background: var(--blue-200);
          top: 40%; right: 15%;
          animation-delay: -14s;
        }

        @keyframes drift {
          0%, 100% { transform: translate(0, 0) scale(1); }
          33% { transform: translate(30px, -30px) scale(1.05); }
          66% { transform: translate(-20px, 20px) scale(0.95); }
        }

        .card {
          position: relative;
          z-index: 1;
          width: min(480px, 90vw);
          padding: 3rem 2.5rem;
          text-align: center;
          background: rgba(255, 255, 255, 0.75);
          backdrop-filter: blur(20px);
          border: 1px solid rgba(255, 255, 255, 0.6);
          border-radius: 2rem;
          box-shadow: var(--shadow);
          animation: fadeInUp 0.8s cubic-bezier(0.22, 1, 0.36, 1) both;
        }

        @keyframes fadeInUp {
          from { opacity: 0; transform: translateY(30px); }
          to { opacity: 1; transform: translateY(0); }
        }

        .logo {
          width: 96px;
          height: 96px;
          margin: 0 auto 1.5rem;
          animation: float 4s ease-in-out infinite;
          filter: drop-shadow(0 12px 24px rgba(37, 99, 235, 0.3));
        }

        @keyframes float {
          0%, 100% { transform: translateY(0); }
          50% { transform: translateY(-10px); }
        }

        .logo svg { width: 100%; height: 100%; }

        h1 {
          margin: 0 0 0.5rem;
          font-size: 2rem;
          font-weight: 800;
          letter-spacing: -0.025em;
          background: linear-gradient(135deg, var(--blue-700), var(--blue-500));
          -webkit-background-clip: text;
          -webkit-text-fill-color: transparent;
        }

        .subtitle {
          margin: 0 0 2rem;
          color: var(--blue-800);
          font-size: 1rem;
          line-height: 1.5;
          opacity: 0.85;
        }

        .button {
          position: relative;
          display: inline-flex;
          align-items: center;
          justify-content: center;
          gap: 0.5rem;
          padding: 0.9rem 2rem;
          font-size: 1rem;
          font-weight: 600;
          color: white;
          background: linear-gradient(135deg, var(--blue-500), var(--blue-700));
          border: none;
          border-radius: 9999px;
          cursor: pointer;
          box-shadow: 0 10px 25px -5px rgba(37, 99, 235, 0.45);
          transition: transform 0.2s ease, box-shadow 0.2s ease;
          overflow: hidden;
        }

        .button:hover {
          transform: translateY(-2px);
          box-shadow: 0 15px 35px -5px rgba(37, 99, 235, 0.55);
        }

        .button:active { transform: translateY(0); }

        .button::after {
          content: "";
          position: absolute;
          inset: 0;
          background: linear-gradient(90deg, transparent, rgba(255,255,255,0.3), transparent);
          transform: translateX(-100%);
          transition: transform 0.5s ease;
        }
        .button:hover::after {
          transform: translateX(100%);
        }

        .button.loading {
          pointer-events: none;
          opacity: 0.85;
        }

        .spinner {
          display: none;
          width: 18px; height: 18px;
          border: 2px solid rgba(255,255,255,0.4);
          border-top-color: white;
          border-radius: 50%;
          animation: spin 0.8s linear infinite;
        }
        .button.loading .spinner { display: inline-block; }

        @keyframes spin { to { transform: rotate(360deg); } }

        .result {
          margin-top: 1.5rem;
          min-height: 3.5rem;
          padding: 1rem 1.25rem;
          font-size: 0.95rem;
          color: var(--blue-900);
          background: var(--blue-50);
          border: 1px solid var(--blue-200);
          border-radius: 1rem;
          word-break: break-word;
          transition: all 0.3s ease;
          opacity: 0.8;
        }

        .result.success {
          opacity: 1;
          background: linear-gradient(135deg, #ecfdf5, #d1fae5);
          border-color: #6ee7b7;
          color: #065f46;
          animation: popIn 0.4s ease;
        }

        @keyframes popIn {
          from { opacity: 0; transform: scale(0.96); }
          to { opacity: 1; transform: scale(1); }
        }
      </style>
    </head>
    <body>
      <div class="orb orb-1"></div>
      <div class="orb orb-2"></div>
      <div class="orb orb-3"></div>

      <main class="card">
        <div class="logo">#{crystal_svg}</div>
        <h1>CrystalUI</h1>
        <p class="subtitle">
          Crystal Host owns state and logic.<br>
          WebKitGTK is just a thin native shim.
        </p>
        <button class="button" id="actionBtn" onclick="sendCommand()">
          <span class="spinner"></span>
          <span class="label">Call Crystal Host</span>
        </button>
        <div class="result" id="result">Click the button to invoke a Crystal command</div>
      </main>

      <script>
        window.__crystalResolve = function(id, success, data, error) {
          const btn = document.getElementById('actionBtn');
          const result = document.getElementById('result');
          btn.classList.remove('loading');
          result.classList.add('success');
          result.innerHTML = '<strong>Crystal answered:</strong><br>' +
            Object.entries(data).map(([k, v]) => k + ': ' + v).join('<br>');
        };

        function sendCommand() {
          const btn = document.getElementById('actionBtn');
          const result = document.getElementById('result');
          btn.classList.add('loading');
          result.classList.remove('success');
          result.textContent = 'Talking to the Crystal Host...';
          window.webkit.messageHandlers.crystal.postMessage({
            id: 'cmd-' + Date.now(),
            name: 'hello',
            args: {}
          });
        }
      </script>
    </body>
    </html>
    HTML
  end
end

HelloApp.new.run
