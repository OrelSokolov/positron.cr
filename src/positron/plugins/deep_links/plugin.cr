require "json"
require "log"
require "socket"

module Positron::Plugins
  # Deep links / URL schemes plugin (Linux desktop, Windows).
  #
  # Two responsibilities:
  #
  # 1. **Single instance.** The plugin tries to bind a unix socket at
  #    `$XDG_RUNTIME_DIR/positron-<app_id>.sock` (Linux) or
  #    `%LOCALAPPDATA%\positron-<app_id>.sock` (Windows, via AF_UNIX on
  #    Win10+). If the socket is
  #    already owned by a live instance, this process forwards every
  #    `ARGV` entry matching the scheme to it and `single_instance?`
  #    returns false — skip `Application#run` in that case:
  #
  #      def configure_plugins
  #        @deep_links = Positron::Plugins::DeepLinks.new(
  #          app_id: "myapp", scheme: "myapp")
  #        use @deep_links
  #      end
  #
  #      def run
  #        return unless @deep_links.try(&.single_instance?)
  #        super
  #      end
  #
  # 2. **URL delivery.** The first instance listens on the socket; every
  #    received URL goes to `Application#on_deep_link`, the EventBus
  #    (`deep_link.opened`) and the frontend JS event `deep_link.opened`.
  #    URLs passed at cold start are exposed via `deep_links.pending()`.
  #
  # Registering the scheme with the OS (`.desktop` entry) is a packaging
  # concern — see `Positron::Packaging` (CLI `positron package`).
  class DeepLinks < Positron::Plugin
    getter pending : Array(String)

    @server : UNIXServer?
    @single_instance : Bool?

    def initialize(app_id : String, scheme : String? = nil)
      @app_id = app_id
      @pending = scheme ? ARGV.select(&.starts_with?("#{scheme}:")) : [] of String
    end

    def name : String
      "deep_links"
    end

    def supported_platforms : Array(Symbol)
      [:desktop, :android, :ios]
    end

    def manifest : Hash(String, Positron::CommandManifest)
      {
        "deep_links.pending" => Positron::CommandManifest.new(
          name: "deep_links.pending",
          returns: "Array",
        ),
      }
    end

    def bind(registry : Positron::CommandRegistry, state : Positron::StateManager)
      registry.register("deep_links.pending") do |_request|
        Positron::CommandResult.new(
          success: true,
          data: JSON.parse(@pending.to_json)
        )
      end
    end

    def on_ready(host : Positron::DesktopHost)
      if single_instance?
        spawn { listen(host) }
      else
        forward(@pending, socket_path)
      end
    end

    # True when this process is the first instance (or single-instance
    # handling is unavailable, e.g. no XDG_RUNTIME_DIR). Calling this
    # binds the socket, so call it once before `run` and reuse the result.
    def single_instance? : Bool
      @single_instance ||= compute_single_instance
    end

    private def compute_single_instance : Bool
      path = socket_path
      return true unless path

      # A stale socket from a crashed instance must not lock the app
      # out: probe it and clean up if nobody answers.
      if File.exists?(path)
        return false if socket_alive?(path)
        begin
          File.delete(path)
        rescue
        end
      end

      @server = UNIXServer.new(path)
      true
    rescue ex
      Log.for("positron.plugins.deep_links").warn {
        "single-instance handshake unavailable: #{ex.message}"
      }
      true
    end

    private def socket_alive?(path : String) : Bool
      client = UNIXSocket.new(path)
      client.close
      true
    rescue
      false
    end

    private def listen(host : Positron::DesktopHost)
      server = @server
      return unless server

      loop do
        client = server.accept? || break
        handle_client(client, host)
      end
    rescue ex
      Log.for("positron.plugins.deep_links").error { "socket listener: #{ex.message}" }
    end

    private def handle_client(client : UNIXSocket, host : Positron::DesktopHost)
      client.read_timeout = 2.seconds
      url = client.gets.try(&.strip)
      client.close

      return if url.nil? || url.empty?
      deliver(url, host)
    end

    private def forward(urls : Array(String), path : String?) : Nil
      return unless path
      urls.each do |url|
        client = UNIXSocket.new(path)
        client.puts(url)
        client.close
      rescue ex
        Log.for("positron.plugins.deep_links").warn { "forward failed: #{ex.message}" }
      end
    end

    private def deliver(url : String, host : Positron::DesktopHost)
      host.app.on_deep_link(url)
      Positron::EventBus.emit("deep_link.opened", JSON.parse({url: url}.to_json))
      host.emit_to_js("deep_link.opened", {url: url})
    end

    private def socket_path : String?
      {% if flag?(:win32) %}
        # AF_UNIX exists on Windows 10+; Crystal supports it. There is no
        # XDG_RUNTIME_DIR — %LOCALAPPDATA% plays that role.
        base = ENV["LOCALAPPDATA"]? || Dir.tempdir
        File.join(base, "positron-#{@app_id}.sock")
      {% else %}
        runtime_dir = ENV["XDG_RUNTIME_DIR"]?
        return nil unless runtime_dir
        File.join(runtime_dir, "positron-#{@app_id}.sock")
      {% end %}
    end
  end
end
