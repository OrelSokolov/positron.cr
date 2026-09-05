require "../src/crystal_ui/dev/asset_server"
require "spec"
require "http/client"
require "file_utils"

describe CrystalUI::Dev::AssetServer do
  it "serves files from disk with correct mime types" do
    with_frontend_dir do |dir|
      server = start_server(dir)

      body, mime = get(server, "/index.html")
      mime.should contain("text/html")
      body.should contain("<h1>hello dev</h1>")

      _, css_mime = get(server, "/style.css")
      css_mime.should contain("text/css")

      _, js_mime = get(server, "/app.js")
      js_mime.should contain("javascript")

      server.stop
    end
  end

  it "injects runtime snippets into HTML responses" do
    with_frontend_dir do |dir|
      server = CrystalUI::Dev::AssetServer.new(
        dir,
        runtime_provider: -> { ["window.__testRuntime = 1;"] },
      ) { }

      server.start
      body, _mime = get(server, "/index.html")

      body.should contain("<script>window.__testRuntime = 1;</script>")
      # injected before the page body content
      ((body.index("<script>window.__testRuntime").not_nil!) < (body.index("<h1>").not_nil!)).should be_true

      server.stop
    end
  end

  it "falls back to index.html for extensionless SPA routes" do
    with_frontend_dir do |dir|
      server = start_server(dir)

      body, mime = get(server, "/some/deep/route")
      mime.should contain("text/html")
      body.should contain("<h1>hello dev</h1>")

      server.stop
    end
  end

  it "returns 404 for missing files and rejects traversal" do
    with_frontend_dir do |dir|
      server = start_server(dir)

      status = get_status(server, "/missing.css")
      status.should eq(404)

      status = get_status(server, "/../secret.txt")
      [400, 404].should contain(status)

      server.stop
    end
  end

  it "fires the reload callback when a file changes" do
    with_frontend_dir do |dir|
      reloaded = 0
      server = CrystalUI::Dev::AssetServer.new(dir) { reloaded += 1 }
      server.start

      # No reload without changes (the watcher polls every 500ms).
      sleep 700.milliseconds
      reloaded.should eq(0)

      File.write(File.join(dir, "app.js"), "console.log('changed');\n")
      wait_until(timeout: 3.seconds) { reloaded > 0 }
      reloaded.should be > 0

      server.stop
    end
  end
end

def start_server(dir)
  server = CrystalUI::Dev::AssetServer.new(dir) { }
  server.start
  server
end

def get(server, path) : {String, String}
  HTTP::Client.get("#{server.base_url}#{path}") do |response|
    {response.body_io.gets_to_end, response.headers["Content-Type"]? || ""}
  end
end

def get_status(server, path) : Int32
  HTTP::Client.get("#{server.base_url}#{path}") { |response| response.status_code }
end

def with_frontend_dir(&)
  dir = File.join(Dir.tempdir, "crystalui-spec-#{Random::Secure.hex(6)}")
  FileUtils.mkdir_p(dir)
  File.write(File.join(dir, "index.html"), "<html><head><title>t</title></head><body><h1>hello dev</h1></body></html>")
  File.write(File.join(dir, "style.css"), "body { color: red; }")
  File.write(File.join(dir, "app.js"), "console.log('hi');")
  yield dir
ensure
  FileUtils.rm_rf(dir) if dir
end

# Poll + sleep loop with a bounded number of iterations. Deliberately avoids
# Time.monotonic (deprecated in newer Crystal in favour of Time.instant,
# which older compilers supported by this repo do not have yet).
def wait_until(timeout : Time::Span, &condition : -> Bool)
  remaining = {(timeout.total_milliseconds / 50).ceil.to_i, 1}.max
  until condition.call
    raise "condition not met within #{timeout}" if (remaining -= 1) < 0
    sleep 50.milliseconds
  end
end
