require "log"
require "file_utils"
require "process"

module CrystalUI
  # Linux desktop packaging helpers: .desktop entries, hicolor icon
  # generation, AppDir/AppImage scaffolding and deb metadata templates.
  #
  # Used by the `crystal-ui package` CLI command. Everything is generated
  # from plain data — no hidden state — so applications can call these
  # helpers from their own build scripts.
  module Packaging
    # Render an XDG .desktop entry. `schemes` adds an `x-scheme-handler/…`
    # MimeType (deep link registration).
    def self.desktop_entry(
      app_id : String,
      name : String,
      exec : String,
      icon : String? = nil,
      comment : String? = nil,
      categories : String = "Utility",
      terminal : Bool = false,
      schemes : Array(String) = [] of String
    ) : String
      mime = schemes.empty? ? "" : "MimeType=#{schemes.map { |s| "x-scheme-handler/#{s}" }.join(";")};\n"

      <<-DESKTOP
        [Desktop Entry]
        Type=Application
        Version=1.0
        Name=#{name}
        Exec=#{exec}
        #{comment ? "Comment=#{comment}\n" : ""}Icon=#{icon || app_id}
        Categories=#{categories};
        Terminal=#{terminal ? "true" : "false"}
        StartupWMClass=#{app_id}
        #{mime}
      DESKTOP
    end

    # Write a .desktop entry into `~/.local/share/applications` (user
    # install, no root needed) and refresh the desktop database.
    def self.install_desktop_entry(app_id : String, entry : String) : String
      dir = File.join(ENV["HOME"]? || "/", ".local", "share", "applications")
      FileUtils.mkdir_p(dir)
      path = File.join(dir, "#{app_id}.desktop")
      File.write(path, entry)
      File.chmod(path, 0o755) # launchable entries must be executable

      Process.run("update-desktop-database", [dir], error: Process::Redirect::Close) rescue nil
      path
    end

    HICOLOR_SIZES = [16, 24, 32, 48, 64, 128, 256, 512]

    # Convert a master SVG/PNG icon into the hicolor size set.
    # Uses whichever rasterizer is available (rsvg-convert preferred,
    # then ImageMagick magick/convert). Returns the list of written files.
    def self.generate_hicolor_icons(svg_path : String,
                                    output_root : String,
                                    sizes : Array(Int32) = HICOLOR_SIZES) : Array(String)
      converter = find_icon_converter
      raise "no icon converter found (install rsvg-convert or imagemagick)" unless converter

      written = [] of String
      sizes.each do |size|
        out_dir = File.join(output_root, "hicolor", "#{size}x#{size}", "apps")
        FileUtils.mkdir_p(out_dir)
        out_path = File.join(out_dir, "#{File.basename(svg_path, File.extname(svg_path))}.png")

        case converter
        when .starts_with?("rsvg")
          run_quiet(converter, ["-w", size.to_s, "-h", size.to_s, "-o", out_path, svg_path])
        else
          run_quiet(converter, [svg_path, "-resize", "#{size}x#{size}", out_path])
        end
        written << out_path
      end
      written
    end

    # Scaffold a Linux AppDir around a built binary and (when appimagetool
    # is available) produce an AppImage. Returns the AppImage path, or the
    # AppDir path when appimagetool is missing.
    def self.build_appdir(app_name : String, binary_path : String,
                          icon_path : String, entry : String,
                          output_dir : String = "dist") : String
      app_dir = File.join(output_dir, "#{app_name}.AppDir")
      FileUtils.rm_rf(app_dir)
      FileUtils.mkdir_p(File.join(app_dir, "usr", "bin"))

      # Binary + icon at the AppDir root (AppImage convention).
      FileUtils.cp(binary_path, File.join(app_dir, File.basename(binary_path)))
      FileUtils.cp(icon_path, File.join(app_dir, "#{app_name}.png")) if File.exists?(icon_path)
      File.write(File.join(app_dir, "#{app_name}.desktop"), entry)

      File.write(File.join(app_dir, "AppRun"), <<-APPRUN)
        #!/bin/sh
        HERE="$(dirname "$(readlink -f "$0")")"
        exec "$HERE/#{File.basename(binary_path)}" "$@"
      APPRUN
      File.chmod(File.join(app_dir, "AppRun"), 0o755)

      appimagetool = find_executable("appimagetool")
      unless appimagetool
        Log.for("crystalui.packaging").warn {
          "appimagetool not found — AppDir prepared at #{app_dir}"
        }
        return app_dir
      end

      appimage = File.join(output_dir, "#{app_name}.AppImage")
      FileUtils.mkdir_p(output_dir)
      run(appimagetool, [app_dir, appimage])
      appimage
    end

    # Render a minimal debian/ control file for deb packaging helpers.
    def self.debian_control(app_name : String, version : String,
                            description : String,
                            depends : String = "libgtk-3-0, libwebkit2gtk-4.1-0") : String
      <<-CONTROL
        Package: #{app_name}
        Version: #{version}
        Section: utils
        Priority: optional
        Architecture: amd64
        Depends: #{depends}
        Maintainer: CrystalUI Contributors <noreply@example.com>
        Description: #{description}
      CONTROL
    end

    # --- tool discovery ---

    def self.find_icon_converter : String?
      {"rsvg-convert", "magick", "convert"}.find { |cmd| find_executable(cmd) }
    end

    def self.find_executable(name : String) : String?
      path_separator = {% if flag?(:win32) %} ";" {% else %} ":" {% end %}
      ENV["PATH"]?.to_s.split(path_separator).each do |dir|
        next if dir.empty?
        candidate = File.join(dir, name)
        info = File.info?(candidate)
        next unless info.try(&.file?)
        return candidate if executable_file?(candidate)
      end
      nil
    end

    # File::Info#executable? is not available on all supported Crystal
    # versions — check the POSIX permission bits directly.
    private def self.executable_file?(path : String) : Bool
      info = File.info?(path)
      return false unless info
      {% if flag?(:win32) %}
        true
      {% else %}
        (info.permissions.value & 0o111) != 0
      {% end %}
    rescue
      false
    end

    def self.run(cmd : String, args : Array(String)) : Nil
      status = Process.run(cmd, args, output: Process::Redirect::Inherit,
        error: Process::Redirect::Inherit)
      raise "#{cmd} failed with exit #{status.exit_code}" unless status.success?
    end

    def self.run_quiet(cmd : String, args : Array(String)) : Nil
      status = Process.run(cmd, args, output: Process::Redirect::Close,
        error: Process::Redirect::Close)
      raise "#{cmd} failed with exit #{status.exit_code}" unless status.success?
    end
  end
end
