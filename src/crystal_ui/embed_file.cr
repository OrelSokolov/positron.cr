# Helper used by the embed_application_files macro.
# Reads a file and prints its contents as a Crystal string literal.
puts File.read(ARGV[0]).inspect
