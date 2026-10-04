require "../src/positron/packaging"
require "spec"
require "file_utils"

describe Positron::Packaging do
  it "renders a .desktop entry with schemes and icon" do
    entry = Positron::Packaging.desktop_entry(
      app_id: "myapp",
      name: "My App",
      exec: "/usr/bin/myapp",
      icon: "myapp",
      comment: "Does things",
      schemes: ["myapp"]
    )

    entry.should contain("[Desktop Entry]")
    entry.should contain("Name=My App")
    entry.should contain("Exec=/usr/bin/myapp")
    entry.should contain("Icon=myapp")
    entry.should contain("Comment=Does things")
    entry.should contain("Terminal=false")
    entry.should contain("MimeType=x-scheme-handler/myapp;")
    entry.should contain("StartupWMClass=myapp")
  end

  it "renders a .desktop entry without optional fields" do
    entry = Positron::Packaging.desktop_entry(
      app_id: "myapp", name: "My App", exec: "myapp")

    entry.should_not contain("Comment=")
    entry.should_not contain("MimeType=")
  end

  it "generates hicolor icons when a converter is available" do
    converter = Positron::Packaging.find_icon_converter
    next pending!("no icon converter (rsvg-convert/imagemagick) installed") unless converter

    dir = File.join(Dir.tempdir, "positron-pack-spec-#{Random::Secure.hex(6)}")
    FileUtils.mkdir_p(dir)
    master = File.join(dir, "icon.svg")
    File.write(master, %(<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><rect width="64" height="64" fill="#0af"/></svg>))

    written = Positron::Packaging.generate_hicolor_icons(master, dir, [16, 48])

    written.size.should eq(2)
    written.each do |path|
      File.exists?(path).should be_true
      File.size(path).should be > 0
    end
    written[0].should contain("16x16")

    FileUtils.rm_rf(dir)
  end

  it "builds an AppDir scaffold around a binary" do
    dir = File.join(Dir.tempdir, "positron-appdir-spec-#{Random::Secure.hex(6)}")
    FileUtils.mkdir_p(dir)
    binary = File.join(dir, "myapp")
    File.write(binary, "#!/bin/sh\ntrue\n")
    File.chmod(binary, 0o755)
    icon = File.join(dir, "myapp.png")
    File.write(icon, "png")

    entry = Positron::Packaging.desktop_entry(
      app_id: "myapp", name: "My App", exec: "myapp")

    result = Positron::Packaging.build_appdir("myapp", binary, icon, entry,
      output_dir: File.join(dir, "dist"))

    app_dir = File.join(dir, "dist", "myapp.AppDir")
    File.exists?(File.join(app_dir, "AppRun")).should be_true
    File.exists?(File.join(app_dir, "myapp.desktop")).should be_true
    File.exists?(File.join(app_dir, "usr", "bin")).should be_true
    # Exec bits are POSIX-only: win32 File.info reports 0o666/0o444 for
    # regular files regardless of chmod, so skip the assertion there.
    {% if flag?(:unix) %}
      ((File.info(File.join(app_dir, "AppRun")).permissions.value & 0o111) != 0).should be_true
    {% end %}
    # Without appimagetool the scaffold itself is returned.
    result.should eq(app_dir)

    FileUtils.rm_rf(dir)
  end

  it "renders a debian control file" do
    control = Positron::Packaging.debian_control(
      "myapp", "1.2.3", "A Positron application")

    control.should contain("Package: myapp")
    control.should contain("Version: 1.2.3")
    control.should contain("Depends: libgtk-3-0, libwebkit2gtk-4.1-0")
    control.should contain("Description: A Positron application")
  end
end
