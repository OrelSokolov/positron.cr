# Helper used by the Application#embed_directory macro.
# Walks a directory tree and prints a Crystal Hash literal mapping web paths
# ("/index.html", "/assets/app-abc.js", …) to Base64-encoded file contents —
# safe for binary files, unlike a raw String literal.
require "base64"

dir = ARGV[0].chomp("/")

files = {} of String => String
if Dir.exists?(dir)
  Dir.glob(File.join(dir, "**", "*")).sort.each do |path|
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
