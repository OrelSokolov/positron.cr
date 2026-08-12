require "fileutils"
require "open3"

EXAMPLES_DIR = File.expand_path("examples", __dir__)
LOGS_DIR = File.expand_path("logs", __dir__)
CRYSTAL_CMD = ENV.fetch("CRYSTAL_CMD", "crystal")
CRYSTAL_FLAGS = ENV.fetch("CRYSTAL_FLAGS", "")

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

def build_example(name)
  # Use relative paths so the same command works both locally and inside
  # containerized build environments (e.g. docker run -w /app).
  source = File.join("examples", name, "#{name}.cr")
  output = File.join("examples", name, name)
  log_path = File.join(LOGS_DIR, "#{name}.log")

  unless File.exist?(source)
    puts colorize("[SKIP] #{name}: source file not found", :yellow)
    return :skipped
  end

  FileUtils.mkdir_p(LOGS_DIR)
  File.write(log_path, "")

  command = "#{CRYSTAL_CMD} build #{CRYSTAL_FLAGS} #{source} -o #{output}"
  puts colorize("  Building #{name}...", :cyan)

  start_time = Time.now
  stdout, stderr, status = Open3.capture3(command)
  elapsed = Time.now - start_time

  File.write(log_path, <<~LOG)
    Command: #{command}
    Started: #{start_time}
    Elapsed: #{elapsed.round(3)}s
    Exit code: #{status.exitstatus}

    --- stdout ---
    #{stdout}

    --- stderr ---
    #{stderr}
  LOG

  if status.success?
    puts colorize("  [SUCCESS] #{name} (#{elapsed.round(2)}s)", :green)
    :success
  else
    puts colorize("  [FAILED]  #{name} (#{elapsed.round(2)}s)", :red)
    puts colorize("            log: #{log_path}", :gray)
    :failed
  end
end

namespace :build do
  desc "Build all examples sequentially and write logs to logs/"
  task :examples do
    puts colorize("CrystalUI — building examples", :blue)
    puts "=" * 50

    results = example_names.to_h { |name| [name, build_example(name)] }

    success = results.count { |_, result| result == :success }
    failed = results.count { |_, result| result == :failed }
    skipped = results.count { |_, result| result == :skipped }

    puts "=" * 50
    puts "Summary: " \
      "#{colorize("#{success} success", :green)}, " \
      "#{colorize("#{failed} failed", :red)}, " \
      "#{colorize("#{skipped} skipped", :yellow)}"

    exit(failed > 0 ? 1 : 0)
  end
end

desc "Build all examples (alias for build:examples)"
task examples: "build:examples"

desc "Run the test suite"
task :spec do
  sh "#{CRYSTAL_CMD} spec"
end

task :test => :spec
