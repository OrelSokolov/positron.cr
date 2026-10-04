# positron — developer CLI.
#
# Commands:
#   positron init <name>    scaffold a new Positron application
#   positron dev            build (if stale) and run with live reload
#   positron build          release build with embedded assets
#   positron doctor         check toolchain and native dependencies
#   positron package        .desktop entry, hicolor icons, AppDir/AppImage
#
# The CLI deliberately does NOT require the Positron runtime (no GTK
# linkage): it only orchestrates the compiler and generates files.
require "log"
require "file_utils"
require "process"
require "./packaging"

module Positron::CLI
  VERSION = "0.1.0"

  def self.run(args : Array(String)) : Nil
    command = args[0]? || "help"
    rest = args[1..]

    case command
    when "init"    then init(rest)
    when "dev"     then dev
    when "build"   then build
    when "doctor"  then doctor
    when "package" then package(rest)
    when "help", "--help", "-h"
      puts usage
    when "version", "--version", "-v"
      puts "positron #{VERSION}"
    else
      STDERR.puts "unknown command: #{command}"
      STDERR.puts usage
      exit 1
    end
  end

  def self.usage : String
    <<-USAGE
      Usage: positron <command> [options]

      Commands:
        init <name>     Scaffold a new application in ./<name>
        dev             Rebuild if stale, then run with live reload
        build           Release build (embedded frontend assets)
        doctor          Check toolchain and native dependencies
        package [--install]
                        Generate .desktop entry, hicolor icons and
                        AppDir/AppImage into dist/
        help | version

      Environment:
        POSITRON_PATH   Path to the positron shard source (for init)
        CRYSTAL_CMD       Crystal compiler to use (default: crystal)
    USAGE
  end

  # --- init ---

  def self.init(args : Array(String)) : Nil
    name = args[0]? || abort("usage: positron init <name>")
    abort("'#{name}' is not a valid app name (a-z0-9-_)") unless name =~ /\A[a-z][a-z0-9_-]*\Z/

    framework_path = framework_source_path
    abort(
      "set POSITRON_PATH to the positron checkout (or build the CLI with " \
      "POSITRON_SOURCE_DIR set)") unless framework_path

    dir = File.expand_path(name)
    abort("directory #{dir} already exists") if File.exists?(dir)

    class_name = name.split(/[-_]/).map(&.capitalize).join
    app_title = name.split(/[-_]/).map(&.capitalize).join(" ")

    FileUtils.mkdir_p(File.join(dir, "src", "frontend"))
    FileUtils.mkdir_p(File.join(dir, "assets"))
    FileUtils.mkdir_p(File.join(dir, "bin"))

    # Icon: copy the framework's crystal icon when available.
    icon_src = File.join(framework_path, "assets", "crystal-icon.svg")
    has_icon = File.file?(icon_src)
    FileUtils.cp(icon_src, File.join(dir, "assets", "icon.svg")) if has_icon

    File.write(File.join(dir, "shard.yml"), shard_yml(name, framework_path))
    File.write(File.join(dir, "src", "#{name}.cr"), app_source(name, class_name, app_title, has_icon))
    File.write(File.join(dir, "src", "frontend", "application.html"), frontend_html(app_title))
    File.write(File.join(dir, "src", "frontend", "application.css"), frontend_css)
    File.write(File.join(dir, "src", "frontend", "application.js"), frontend_js)
    File.write(File.join(dir, ".gitignore"), frontend_gitignore)
    File.write(File.join(dir, "README.md"), app_readme(name, app_title))

    puts "Created #{name}/"
    puts "  shard.yml, src/#{name}.cr, src/frontend/, #{has_icon ? "assets/icon.svg, " : ""}bin/"
    puts "Next:"
    puts "  cd #{name}"
    puts "  positron dev"
  end

  def self.framework_source_path : String?
    if env = ENV["POSITRON_PATH"]?
      return File.expand_path(env) if Dir.exists?(env)
      return nil
    end
    # Baked in at CLI build time (see rake build:cli).
    {% if env("POSITRON_SOURCE_DIR") %}
      {{ env("POSITRON_SOURCE_DIR") }}
    {% else %}
      nil
    {% end %}
  end

  def self.shard_yml(name : String, framework_path : String) : String
    <<-YAML
      name: #{name}
      version: 0.1.0
      crystal: ">= 1.10.0"

      dependencies:
        positron:
          path: #{framework_path}

      targets:
        #{name}:
          main: src/#{name}.cr
    YAML
  end

  def self.app_source(name : String, class_name : String, title : String, has_icon : Bool) : String
    icon_macro = has_icon ? %(embed_application_files(__DIR__, "../assets/icon")) : "embed_application_files(__DIR__)"

    <<-SRC
      require "positron"

      class #{class_name}App < Positron::Application
        #{icon_macro}

        def configure_plugins
          register_plugin(Positron::Plugins::Preferences.new(app_id: "#{name}"))
          use Positron::Plugins::Dialogs
        end

        def register_commands(registry)
          command_registry
        end

        def on_ready
          webview.create(Positron::WebViewConfig.new(
            title: "#{title}",
            width: 900,
            height: 640,
            close_to_tray: false
          ))

          webview.bind("crystal") do |json|
            host.dispatch(json)
          end

          if Positron::Dev.enabled?
            # Dev: frontend served from disk, live reload on every change.
            webview.load_url(serve_directory(File.join(__DIR__, "frontend")))
          else
            # Release: frontend baked into the binary at compile time.
            webview.load_html(application_html)
          end
        end
      end

      #{class_name}App.new.run
    SRC
  end

  def self.frontend_html(title : String) : String
    <<-HTML
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>#{title}</title>
        <style>
      {{CSS}}
        </style>
      </head>
      <body>
        <main class="card">
          <h1>#{title}</h1>
          <p class="subtitle">Edit frontend/ and save — the window reloads.</p>
          <button class="button" id="ping">Call the Crystal Host</button>
          <div class="result" id="result">Positron #{title} is ready.</div>
        </main>

        <script>
      {{RUNTIME_JS}}
        </script>
        <script>
      {{HYDRATE_JS}};
        </script>
        <script>
      {{JS}}
        </script>
      </body>
      </html>
    HTML
  end

  def self.frontend_css : String
    <<-CSS
      :root { color-scheme: light dark; }
      * { box-sizing: border-box; }
      body {
        margin: 0; min-height: 100vh; display: grid; place-items: center;
        font-family: system-ui, sans-serif;
        background: #f5f6fa; color: #1f2430;
      }
      @media (prefers-color-scheme: dark) {
        body { background: #1b1e28; color: #e8eaf2; }
      }
      .card {
        text-align: center; padding: 3rem 4rem; border-radius: 16px;
        background: rgba(127, 127, 127, 0.08);
      }
      .subtitle { opacity: 0.7; }
      .button {
        margin-top: 1rem; padding: 0.6rem 1.4rem; border-radius: 8px;
        border: 0; cursor: pointer; font-size: 1rem;
        background: #3b82f6; color: white;
      }
      .button:hover { background: #2563eb; }
      .result { margin-top: 1rem; font-family: ui-monospace, monospace; opacity: 0.8; }
    CSS
  end

  def self.frontend_js : String
    <<-JS
      document.getElementById("ping").addEventListener("click", async () => {
        const result = document.getElementById("result");
        result.textContent = "calling host…";
        try {
          await Positron.preferences.set("last_ping", new Date().toISOString());
          const at = await Positron.preferences.get("last_ping");
          result.textContent = "stored in host state: " + at;
        } catch (e) {
          result.textContent = "host error: " + e.message;
        }
      });
    JS
  end

  def self.frontend_gitignore : String
    "/bin/\n/lib/\n/shard.lock\n/dist/\n"
  end

  def self.app_readme(name : String, title : String) : String
    <<-MD
      # #{title}

      A [Positron](../positron) desktop application.

      ## Development

      ```
      positron dev      # live reload: edit frontend/, see changes instantly
      ```

      ## Build

      ```
      positron build    # release binary in bin/#{name}
      ```

      Frontend sources live in `frontend/` (plain HTML/CSS/JS with the
      `Positron.*` bridge runtime). Backend logic belongs in
      `src/#{name}.cr` as `@[Positron::Command]` methods.
    MD
  end

  # --- project discovery ---

  def self.crystal_cmd : String
    ENV.fetch("CRYSTAL_CMD", "crystal")
  end

  def self.project_name : String
    shard = File.exists?("shard.yml") ? File.read("shard.yml") : nil
    if shard && (match = shard.match(/^\s*name:\s*(\S+)/m))
      match[1]
    else
      abort("no shard.yml with a `name:` found in the current directory")
    end
  end

  def self.entry_source : String
    name = project_name
    candidates = ["src/#{name}.cr"]
    candidates.each do |path|
      return path if File.file?(path)
    end
    abort("entry point not found: tried #{candidates.join(", ")}")
  end

  def self.stale?(binary : String, sources : Array(String)) : Bool
    return true unless File.exists?(binary)
    btime = File.info(binary).modification_time.to_unix_ms
    sources.any? do |pattern|
      Dir.glob(pattern).any? do |f|
        mtime = File.info?(f).try(&.modification_time.to_unix_ms) || 0_i64
        mtime > btime
      end
    end
  end

  # --- dev / build ---

  def self.dev : Nil
    name = project_name
    entry = entry_source
    binary = File.join("bin", name)

    # Frontend changes are served live by the dev asset server — only
    # Crystal sources trigger a rebuild.
    sources = ["src/**/*.cr", "shard.yml", "lib/positron/src/**/*.cr"]
    if stale?(binary, sources)
      puts "→ building #{name}…"
      run! crystal_cmd, ["build", entry, "-o", binary]
    else
      puts "→ #{binary} is up to date"
    end

    puts "→ running with live reload (Ctrl+C to stop)"
    env = {"POSITRON_DEV" => "1"}
    status = Process.run(binary, env: env, output: Process::Redirect::Inherit,
      error: Process::Redirect::Inherit)
    exit status.exit_code if status.normal_exit? && status.exit_code != 0
  end

  def self.build : Nil
    name = project_name
    entry = entry_source
    FileUtils.mkdir_p("bin")
    args = ["build", entry, "-o", File.join("bin", name), "--release"]
    puts "→ crystal #{args.join(" ")}"
    run! crystal_cmd, args
    puts "→ bin/#{name}"
  end

  # --- doctor ---

  def self.doctor : Nil
    puts "Positron doctor"
    puts ""

    ok = true

    ok &= check_command(crystal_cmd, "--version")
    ok &= check_pkg_config("gtk+-3.0")
    ok &= check_pkg_config("webkit2gtk-4.1")
    ok &= check_pkg_config("ayatana-appindicator3-0.1")
    ok &= check_pkg_config("libnotify")
    check_pkg_config("sqlite3", optional: true)
    check_command(Positron::Packaging.find_icon_converter, "--version", optional: true,
      label: "icon converter (rsvg-convert/magick)")
    check_command(Positron::Packaging.find_executable("appimagetool"), "--version",
      optional: true, label: "appimagetool")

    puts ""
    if ok
      puts "All required dependencies are available."
    else
      puts "Some required dependencies are missing (see above)."
      exit 1
    end
  end

  def self.check_command(cmd : String?, flag : String, optional : Bool = false,
                         label : String? = nil) : Bool
    if cmd.nil?
      report(optional ? "warn" : "fail", "#{label || "command"}: not found")
      return optional
    end
    name = label || cmd
    status = Process.run(cmd, [flag], output: Process::Redirect::Close,
      error: Process::Redirect::Close)
    if status.success?
      report("ok", name)
      true
    else
      report(optional ? "warn" : "fail", "#{name}: exited with #{status.exit_code}")
      optional
    end
  end

  def self.check_pkg_config(package : String, optional : Bool = false) : Bool
    status = Process.run("pkg-config", ["--exists", package],
      output: Process::Redirect::Close, error: Process::Redirect::Close)
    if status.success?
      version = IO::Memory.new
      Process.run("pkg-config", ["--modversion", package], output: version)
      report("ok", "#{package} #{version.to_s.strip}")
      true
    else
      report(optional ? "warn" : "fail", "#{package}: missing (pkg-config)")
      optional
    end
  end

  def self.report(kind : String, message : String) : Nil
    symbol = case kind
             when "ok"   then "[OK]  "
             when "warn" then "[SKIP] "
             else             "[FAIL] "
             end
    puts "#{symbol}#{message}"
  end

  # --- package ---

  def self.package(args : Array(String)) : Nil
    name = project_name
    build
    binary = File.expand_path(File.join("bin", name))

    icon = Dir["assets/*.svg"].first? || Dir["assets/*.png"].first?
    icon_path = nil
    if icon
      begin
        written = Positron::Packaging.generate_hicolor_icons(icon, File.join("dist", "icons"))
        icon_path = written.last?
        puts "→ icons: #{written.size} sizes in dist/icons/hicolor"
      rescue ex
        puts "→ icon generation skipped: #{ex.message}"
      end
    else
      puts "→ no assets/*.svg|png found, skipping icon generation"
    end

    entry = Positron::Packaging.desktop_entry(
      app_id: name,
      name: name,
      exec: binary,
      icon: icon_path ? File.join("dist", "icons", "hicolor", "256x256", "apps",
        "#{File.basename(icon.not_nil!, File.extname(icon.not_nil!))}.png") : name,
      comment: "#{name} (Positron)"
    )

    if args.includes?("--install")
      path = Positron::Packaging.install_desktop_entry(name, entry)
      puts "→ desktop entry installed: #{path}"
    else
      File.write(File.join("dist", "#{name}.desktop"), entry)
      puts "→ desktop entry: dist/#{name}.desktop (use --install to install)"
    end

    if icon && icon_path
      result = Positron::Packaging.build_appdir(name, binary, icon_path, entry,
        output_dir: "dist")
      if result.ends_with?(".AppImage")
        puts "→ AppImage: #{result}"
      else
        puts "→ AppDir: #{result} (install appimagetool to produce an AppImage)"
      end
    else
      puts "→ AppDir skipped (no icon available)"
    end
  end

  # --- helpers ---

  def self.abort(message : String) : NoReturn
    STDERR.puts "error: #{message}"
    exit 1
  end

  def self.run!(cmd : String, args : Array(String)) : Nil
    status = Process.run(cmd, args, output: Process::Redirect::Inherit,
      error: Process::Redirect::Inherit)
    abort("#{cmd} failed with exit code #{status.exit_code}") unless status.success?
  end
end

Positron::CLI.run(ARGV)
