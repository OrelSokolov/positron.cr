source "https://rubygems.org"

# Parallel examples build: `rake build:examples` runs every example
# through a memory-aware worker pool (width from cores + MemAvailable +
# measured peak compiler RSS, per-worker CRYSTAL_CACHE_DIR).
# The gems are published on GitHub only — git sources, not RubyGems.
gem "rake"
gem "sysmonitor", git: "https://github.com/OrelSokolov/sysmonitor.git"
gem "taskforge", git: "https://github.com/OrelSokolov/taskforge.git"
