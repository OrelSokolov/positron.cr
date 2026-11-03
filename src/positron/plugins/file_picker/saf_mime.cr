module Positron::Plugins
  # SAF MIME mapping shared by the Android pickers (platform-pure so
  # the translation is headless-testable; SAF filters by MIME type,
  # not glob).
  module SafMime
    # Common extensions → MIME types.
    MIME = {
      "txt" => "text/plain", "md" => "text/plain", "json" => "application/json",
      "csv" => "text/csv", "pdf" => "application/pdf", "zip" => "application/zip",
      "png" => "image/png", "jpg" => "image/jpeg", "jpeg" => "image/jpeg",
      "gif" => "image/gif", "webp" => "image/webp", "bmp" => "image/bmp",
      "svg" => "image/svg+xml", "mp3" => "audio/mpeg", "ogg" => "audio/ogg",
      "wav" => "audio/x-wav", "mp4" => "video/mp4", "webm" => "video/webm",
    }

    # Translates the `accept` filter (HTML <input type="file">
    # convention) into the single MIME type a SAF intent accepts: bare
    # MIME items pass through, extension items map through MIME;
    # mixed/unknown filters fall back to */*.
    def self.mime_for(accept : String) : String
      mimes = accept.split(",").map do |raw|
        item = raw.strip.downcase
        next nil if item.empty? || item == "*"
        if item.includes?('/')
          item
        elsif item.starts_with?('.')
          MIME[item[1..]]?
        end
      end.compact.uniq
      mimes.size == 1 ? mimes.first : "*/*"
    end
  end
end
