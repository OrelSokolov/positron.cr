# Helper used by the Application#embed_directory macro.
# Walks a directory tree and prints a Crystal Hash literal mapping web paths
# ("/index.html", "/assets/app-abc.js", …) to Base64-encoded file contents —
# safe for binary files, unlike a raw String literal.
require "base64"

# Normalize to forward slashes: File.join produces backslashes on
# Windows, and Dir.glob patterns with backslashes match nothing there
# (regular File.* paths accept both, only the glob is picky).
dir = ARGV[0].chomp("/").gsub('\\', "/")

files = {} of String => String
if Dir.exists?(dir)
  Dir.glob("#{dir}/**/*").sort.each do |path|
    next unless File.file?(path)
    rel = "/#{path[(dir.size + 1)..]}"
    files[rel] = Base64.strict_encode(File.read(path))
  end
end

if files.empty?
  STDERR.puts "error: no files found under #{dir} — embed a built directory, not an empty or missing one"
  exit 1
end

puts files.inspect
