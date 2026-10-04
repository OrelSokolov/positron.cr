require "json"
require "file_utils"
require "log"

module Positron::Plugins
  # File system access plugin.
  #
  # Exposes to the frontend:
  #   - fs.home_dir() / fs.temp_dir() / fs.app_data_dir() / fs.app_cache_dir()
  #   - fs.read(path)            → text content
  #   - fs.write(path, content)  → creates parent directories
  #   - fs.append(path, content)
  #   - fs.exists(path) / fs.is_dir(path)
  #   - fs.remove(path)
  #   - fs.mkdir(path)
  #   - fs.list(path)            → [{name, dir, size}]
  #   - fs.stat(path)            → {size, dir, modified}
  #
  # Paths follow the desktop trust model: the frontend has the same file
  # access as the process. To sandbox it, construct the plugin with a
  # `root` — every path is then resolved (and confined) inside it:
  #
  #   use Positron::Plugins::Filesystem.new(root: "/home/user/docs")
  #
  # This plugin has no platform adapters: it is pure Crystal. App dirs
  # follow the XDG base directory spec on Linux, the known folders
  # (%APPDATA% / %LOCALAPPDATA%) on Windows, neutral fallbacks elsewhere.
  class Filesystem < Positron::Plugin
    def initialize(@app_id : String = "positron", @root : String? = nil)
    end

    def name : String
      "fs"
    end

    def supported_platforms : Array(Symbol)
      [:desktop, :android, :ios]
    end

    def manifest : Hash(String, Positron::CommandManifest)
      path_arg = Positron::ArgumentManifest.new(name: "path", type: "String")
      content_arg = Positron::ArgumentManifest.new(name: "content", type: "String")

      {
        "fs.home_dir"      => Positron::CommandManifest.new(name: "fs.home_dir", returns: "String"),
        "fs.temp_dir"      => Positron::CommandManifest.new(name: "fs.temp_dir", returns: "String"),
        "fs.app_data_dir"  => Positron::CommandManifest.new(name: "fs.app_data_dir", returns: "String"),
        "fs.app_cache_dir" => Positron::CommandManifest.new(name: "fs.app_cache_dir", returns: "String"),
        "fs.read"          => Positron::CommandManifest.new(
          name: "fs.read", args: [path_arg], returns: "String"),
        "fs.write" => Positron::CommandManifest.new(
          name: "fs.write", args: [path_arg, content_arg], returns: "Bool"),
        "fs.append" => Positron::CommandManifest.new(
          name: "fs.append", args: [path_arg, content_arg], returns: "Bool"),
        "fs.exists" => Positron::CommandManifest.new(
          name: "fs.exists", args: [path_arg], returns: "Bool"),
        "fs.is_dir" => Positron::CommandManifest.new(
          name: "fs.is_dir", args: [path_arg], returns: "Bool"),
        "fs.remove" => Positron::CommandManifest.new(
          name: "fs.remove", args: [path_arg], returns: "Bool"),
        "fs.mkdir" => Positron::CommandManifest.new(
          name: "fs.mkdir", args: [path_arg], returns: "Bool"),
        "fs.list" => Positron::CommandManifest.new(
          name: "fs.list", args: [path_arg], returns: "Array"),
        "fs.stat" => Positron::CommandManifest.new(
          name: "fs.stat", args: [path_arg], returns: "Object"),
      }
    end

    def bind(registry : Positron::CommandRegistry, state : Positron::StateManager)
      register(registry, "fs.home_dir") { JSON.parse(home_dir.to_json) }
      register(registry, "fs.temp_dir") { JSON.parse(temp_dir.to_json) }
      register(registry, "fs.app_data_dir") { JSON.parse(app_data_dir.to_json) }
      register(registry, "fs.app_cache_dir") { JSON.parse(app_cache_dir.to_json) }

      register(registry, "fs.read") do |args|
        JSON.parse(File.read(safe_path(str(args, "path"))).to_json)
      end

      register(registry, "fs.write") do |args|
        path = safe_path(str(args, "path"))
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, str(args, "content"))
        true
      end

      register(registry, "fs.append") do |args|
        path = safe_path(str(args, "path"))
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, str(args, "content"), mode: "a")
        true
      end

      register(registry, "fs.exists") { |args| File.exists?(safe_path(str(args, "path"))) }
      register(registry, "fs.is_dir") { |args| File.directory?(safe_path(str(args, "path"))) }

      register(registry, "fs.remove") do |args|
        path = safe_path(str(args, "path"))
        if File.directory?(path)
          FileUtils.rm_r(path)
        elsif File.exists?(path)
          File.delete(path)
        end
        true
      end

      register(registry, "fs.mkdir") do |args|
        FileUtils.mkdir_p(safe_path(str(args, "path")))
        true
      end

      register(registry, "fs.list") do |args|
        dir = safe_path(str(args, "path"))
        entries = Dir.children(dir).sort.map do |child|
          full = File.join(dir, child)
          {
            name: child,
            dir:  File.directory?(full),
            size: File.file?(full) ? File.size(full) : 0,
          }
        end
        JSON.parse(entries.to_json)
      end

      register(registry, "fs.stat") do |args|
        path = safe_path(str(args, "path"))
        info = File.info(path)
        JSON.parse({
          size:     info.size,
          dir:      info.directory?,
          modified: info.modification_time.to_unix,
        }.to_json)
      end
    end

    # --- Directory helpers (XDG on Linux, known folders on Windows) ---

    def home_dir : String
      {% if flag?(:win32) %}
        ENV["USERPROFILE"]? || "/"
      {% else %}
        ENV["HOME"]? || "/"
      {% end %}
    end

    def temp_dir : String
      Dir.tempdir
    end

    def app_data_dir : String
      base = {% if flag?(:linux) && !flag?(:android) %}
               ENV["XDG_DATA_HOME"]? || File.join(home_dir, ".local", "share")
             {% elsif flag?(:win32) %}
               # Roaming profile data (per-user, follows the user)
               ENV["APPDATA"]? || File.join(home_dir, "AppData", "Roaming")
             {% else %}
               ENV["POSITRON_DATA"]? || File.join(home_dir, ".local", "share")
             {% end %}
      File.join(base, @app_id)
    end

    def app_cache_dir : String
      base = {% if flag?(:linux) && !flag?(:android) %}
               ENV["XDG_CACHE_HOME"]? || File.join(home_dir, ".cache")
             {% elsif flag?(:win32) %}
               # Machine-local cache (never roams with the profile)
               ENV["LOCALAPPDATA"]? || File.join(home_dir, "AppData", "Local")
             {% else %}
               ENV["POSITRON_CACHE"]? || File.join(home_dir, ".cache")
             {% end %}
      {% if flag?(:win32) %}
        File.join(base, @app_id, "cache")
      {% else %}
        File.join(base, @app_id)
      {% end %}
    end

    # Resolve a frontend-supplied path. Relative paths resolve against the
    # sandbox root when one is set (or the process CWD otherwise). When a
    # `root` sandbox is set the path must stay inside it; violations raise
    # and are reported to JS as command errors.
    private def safe_path(raw : String) : String
      if sandbox = @root
        root_expanded = File.expand_path(sandbox)
        expanded = File.expand_path(raw, root_expanded)
        # File.expand_path normalizes to the native separator ("\\" on
        # Windows), while File::SEPARATOR is "/" everywhere — use the
        # native one or the containment check fails on win32.
        separator = Path::SEPARATORS[0]
        unless expanded == root_expanded || expanded.starts_with?(root_expanded + separator)
          raise "path '#{raw}' is outside the fs plugin sandbox"
        end
        expanded
      else
        File.expand_path(raw)
      end
    end

    private def str(args : JSON::Any, key : String) : String
      args[key]?.try(&.as_s?) || ""
    end

    private def register(registry : Positron::CommandRegistry, name : String,
                         &block : JSON::Any -> _)
      registry.register(name) do |request|
        begin
          data = block.call(request.args)
          Positron::CommandResult.new(
            success: true,
            data: data.is_a?(JSON::Any) ? data : JSON.parse(data.to_json)
          )
        rescue ex
          Log.error { "#{name} failed: #{ex.message}" }
          Positron::CommandResult.new(
            success: false,
            data: JSON.parse("{}"),
            error: "#{name}: #{ex.message}"
          )
        end
      end
    end
  end
end
