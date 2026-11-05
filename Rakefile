require "fileutils"
require "open3"
require "rbconfig"

EXAMPLES_DIR = File.expand_path("examples", __dir__)
LOGS_DIR = File.expand_path("logs", __dir__)
CRYSTAL_CMD = ENV.fetch("CRYSTAL_CMD", "crystal")
CRYSTAL_FLAGS = ENV.fetch("CRYSTAL_FLAGS", "")

ROOT = File.expand_path(__dir__)
BUILD_HELPER = File.join(ROOT, "exe", "build-example")

# The parallel pool for `rake build:examples` (memory-aware width,
# per-worker CRYSTAL_CACHE_DIR) lives in the taskforge gem (>= 0.2.0:
# entry point is Taskforge.run(commands, dir) with a plain array of
# shell strings) — see the Gemfile. Plain `rake` picks the bundle up
# automatically via bundler/setup when `bundle install` has run;
# without the gem the task falls back to the same helper script run
# sequentially, so plain checkouts keep working.
begin
  require "taskforge"
  TASKFORGE_AVAILABLE = true
rescue LoadError
  begin
    require "bundler/setup"
    require "taskforge"
    TASKFORGE_AVAILABLE = true
  # StandardError (not just LoadError/Gem::Exception): a stale bundler
  # setup can also raise e.g. Bundler::LockfileError when the lockfile
  # was written by a newer bundler than the running ruby has — the
  # sequential fallback must survive that too.
  rescue StandardError
    TASKFORGE_AVAILABLE = false
  end
end

def colorize(text, color)
  codes = { green: 32, red: 31, yellow: 33, blue: 34, gray: 90, cyan: 36 }
  "\e[#{codes[color]}m#{text}\e[0m"
end

def example_names
  Dir.children(EXAMPLES_DIR)
    .map { |name| File.join(EXAMPLES_DIR, name) }
    .select { |path| File.directory?(path) }
    .map { |path| File.basename(path) }
    .sort
end

# Runs exe/build-example for one example (build + log + status line).
def build_example(name)
  system(RbConfig.ruby, BUILD_HELPER, name)
end

# Summary from the logs the helper wrote (it truncates each log at the
# start of a build, so a stale log can never count as a success).
def examples_summary(names)
  results = names.to_h do |name|
    source = File.join("examples", name, "#{name}.cr")
    log = File.join(LOGS_DIR, "#{name}.log")
    result =
      if !File.exist?(source)
        :skipped
      elsif File.exist?(log) && File.read(log).match?(/^Exit code: 0$/)
        :success
      else
        :failed
      end
    [name, result]
  end

  success = results.count { |_, result| result == :success }
  failed = results.count { |_, result| result == :failed }
  skipped = results.count { |_, result| result == :skipped }

  puts "=" * 50
  puts "Summary: " \
       "#{colorize("#{success} success", :green)}, " \
       "#{colorize("#{failed} failed", :red)}, " \
       "#{colorize("#{skipped} skipped", :yellow)}"

  failed
end

namespace :build do
  desc "Build the positron CLI into bin/"
  task :cli do
    FileUtils.mkdir_p("bin")
    source_dir = File.expand_path(__dir__)
    sh "#{CRYSTAL_CMD} build #{CRYSTAL_FLAGS} src/positron/cli.cr -o bin/positron" \
      " --define positron_source_dir=#{source_dir.inspect}"
  end

  desc "Build the hello example as an Android APK (arm64, into android/)"
  task :android do
    sh "android/build_android.sh"
  end

  desc "Build the hello example for the iOS simulator (arm64, install + launch)"
  task :ios do
    sh "ios/build_ios.sh"
  end

  desc "macOS only: bundle the camera example into a .app (camera needs a bundled NSCameraUsageDescription)"
  task :camera_app do
    build_example("camera") # bundles + warns automatically on macOS
  end
end

namespace :build do
  desc "Build all examples and write logs to logs/ (parallel via taskforge when installed)"
  task :examples do
    puts colorize("Positron — building examples", :blue)
    puts "=" * 50

    names = example_names
    FileUtils.mkdir_p(LOGS_DIR)
    # Fresh logs up front: the summary reads them back, so a stale log
    # from an earlier run must not masquerade as a result.
    names.each { |name| File.write(File.join(LOGS_DIR, "#{name}.log"), "") }

    if TASKFORGE_AVAILABLE
      commands = names.map { |name| "#{RbConfig.ruby} #{BUILD_HELPER} #{name}" }
      begin
        Taskforge.run(commands, ROOT)
      rescue Taskforge::Pool::Error => e
        puts colorize(e.message, :red)
      end
    else
      puts colorize("taskforge not installed — building sequentially " \
                    "(bundle install enables the parallel pool)", :yellow)
      names.each { |name| build_example(name) }
    end

    exit(1) if examples_summary(names) > 0
  end
end

# --- build:<platform>:all — per-example mobile matrix ---
#
# Both pipeline scripts stage through shared build dirs (android/build +
# android/apk resp. build/ios), so the matrix runs sequentially — no
# taskforge here. The shared output path is overwritten by every example,
# so each success is fanned out under builds/<target>/<name>.[apk|app].
# A failed example doesn't stop the run; the task exits 1 after the
# summary. The block runs one build + fan-out and returns true/false.
def mobile_matrix(target)
  success = 0
  failed = []
  skipped = 0
  example_names.each do |name|
    source = File.join("examples", name, "#{name}.cr")
    unless File.exist?(source)
      puts colorize("==> #{target}: #{name} — skipped (no source)", :yellow)
      skipped += 1
      next
    end
    puts colorize("==> #{target}: #{name}", :blue)
    if yield(name, source)
      success += 1
    else
      failed << name
    end
  end

  puts "=" * 50
  puts "#{target} matrix: " \
       "#{colorize("#{success} success", :green)}, " \
       "#{colorize("#{failed.size} failed", :red)}, " \
       "#{colorize("#{skipped} skipped", :yellow)}"
  failed.each { |name| puts colorize("  failed: #{name}", :red) }
  exit(1) if failed.any?
end

def pretty_label(name)
  name.split("_").map(&:capitalize).join(" ")
end

namespace :build do
  namespace :android do
    desc "Build every example as an Android APK (arm64; APKs fan into builds/android/)"
    task :all do
      mobile_matrix("android") do |name, source|
        next false unless system(
          {"APP" => source, "APP_ID" => "crystal.positron.#{name}",
           "APP_LABEL" => pretty_label(name)},
          "android/build_android.sh"
        )
        FileUtils.mkdir_p(File.join("builds", "android"))
        FileUtils.cp("android/positron.apk", File.join("builds", "android", "#{name}.apk"))
        puts colorize("    builds/android/#{name}.apk", :gray)
        true
      end
    end
  end

  namespace :ios do
    desc "Build every example for the iOS simulator (arm64, no launch; bundles fan into builds/ios/)"
    task :all do
      mobile_matrix("ios") do |name, source|
        next false unless system(
          {"APP_BUNDLE_ID" => "cr.positron.#{name}",
           "APP_DISPLAY_NAME" => pretty_label(name), "LAUNCH" => "0"},
          "ios/build_ios.sh", source
        )
        dest = File.join("builds", "ios", "#{name}.app")
        FileUtils.mkdir_p(File.join("builds", "ios"))
        FileUtils.rm_rf(dest)
        FileUtils.cp_r("build/ios/positron_app.app", dest)
        puts colorize("    builds/ios/#{name}.app", :gray)
        true
      end
    end
  end
end

desc "Build all examples (alias for build:examples)"
task examples: "build:examples"

# --- run:<platform>:<example> — build + install + launch on a device ---
#
# iOS (simulator): every example runs — the plugin factories all have
# iOS branches (real adapters or stubs), verified by building the whole
# matrix. Bundle ids are per-example (cr.positron.<name>), so several
# examples can coexist in the simulator.
#
# Android (device/emulator): every example runs too — package ids are
# per-example (crystal.positron.<name>) and the APK pipeline works on
# Linux and macOS hosts (see android/build_android.sh). With no device
# attached, the first AVD is booted automatically.
namespace :run do
  namespace :ios do
    example_names.each do |name|
      desc "Build, install and launch '#{name}' in the iOS simulator"
      task name do
        env = {
          "APP_BUNDLE_ID" => "cr.positron.#{name}",
          "APP_DISPLAY_NAME" => name.split("_").map(&:capitalize).join(" "),
        }
        sh(env, "ios/build_ios.sh examples/#{name}/#{name}.cr")
      end
    end
  end

  namespace :android do
    example_names.each do |name|
      desc "Build, install and launch '#{name}' on the Android device/emulator"
      task name do
        env = {
          "APP" => "examples/#{name}/#{name}.cr",
          "APP_ID" => "crystal.positron.#{name}",
          "APP_LABEL" => name.split("_").map(&:capitalize).join(" "),
        }
        sh(env, "android/build_android.sh")

        sdk = android_sdk
        adb = File.join(sdk, "platform-tools", "adb")
        android_ensure_device(sdk, adb)
        sh "#{adb} install -r android/positron.apk"
        sh "#{adb} shell am start -n crystal.positron.#{name}/com.positron.shim.PositronActivity"
      end
    end
  end
end

# The Android SDK: ANDROID_SDK when set, else the per-OS default
# (~/android-sdk on Linux, ~/Library/Android/sdk — the Android Studio
# location — on macOS).
def android_sdk
  return ENV["ANDROID_SDK"] if ENV["ANDROID_SDK"]
  mac_default = File.expand_path("~/Library/Android/sdk")
  return mac_default if File.directory?(mac_default)
  File.expand_path("~/android-sdk")
end

# No device attached → boot the first AVD and wait for the system to
# finish booting (bounded — an emulator cold boot takes a while).
def android_ensure_device(sdk, adb)
  devices = `#{adb} devices`.split("\n")[1..].to_a
          .count { |line| line =~ /\tdevice$/ }
  return if devices.positive?

  avds = `#{File.join(sdk, "emulator", "emulator")} -list-avds 2>/dev/null`.split("\n").map(&:strip).reject(&:empty?)
  abort "no Android device attached and no AVD found in #{sdk}" if avds.empty?

  avd = avds.first
  puts colorize("no device attached — booting AVD '#{avd}'", :yellow)
  spawn(File.join(sdk, "emulator", "emulator"), "-avd", avd,
    "-no-snapshot-load", "-no-boot-anim",
    out: File::NULL, err: File::NULL)

  120.times do
    sleep 5
    booted = `#{adb} shell getprop sys.boot_completed 2>/dev/null`.strip
    return if booted == "1"
  end
  abort "AVD '#{avd}' did not finish booting within 10 minutes"
end

desc "Run the test suite"
task :spec do
  sh "#{CRYSTAL_CMD} spec"
end

task :test => :spec

desc "Check formatting without modifying files (as CI would)"
task :format_check do
  sh "#{CRYSTAL_CMD} tool format --check src spec"
end

desc "Fast pre-commit verification: format check + specs"
task :precommit => [:format_check, :spec]

desc "Install the git hooks from .githooks/ (sets core.hooksPath)"
task :hooks_install do
  sh "git config core.hooksPath .githooks"
  puts "Git hooks installed from .githooks/ (pre-commit runs 'rake precommit')"
end
