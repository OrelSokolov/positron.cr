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
  rescue LoadError, Gem::Exception
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

desc "Build all examples (alias for build:examples)"
task examples: "build:examples"

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
