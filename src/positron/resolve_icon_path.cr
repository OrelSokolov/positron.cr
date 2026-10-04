# Compile-time helper used by embed_application_files.
#
# Arguments:
#   1. base path without extension (e.g. /app/assets/icon)
#   2. preferred extension (e.g. .ico)
#   3..N. fallback extensions (e.g. .png .svg)
#
# Prints the resolved file path on the first line and its extension on the
# second line. Exits with an error if none of the candidates exist.

base = ARGV[0]
preferred = ARGV[1]
fallbacks = ARGV[2..-1]

candidates = [base + preferred] + fallbacks.map { |ext| base + ext }

path = candidates.find { |p| File.exists?(p) }

unless path
  STDERR.puts "Positron: icon not found. Tried:\n  #{candidates.join("\n  ")}"
  exit 1
end

puts path
puts File.extname(path)
