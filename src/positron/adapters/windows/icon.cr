module Positron
  module Adapters
    module Windows
      # Windows icon adapter.
      #
      # Windows NotifyIcon and window frame expect ICO. PNG is accepted as a
      # fallback by some APIs, so the embed macro will fall back to PNG/SVG
      # if no ICO file is provided.
      class Icon < IconPort
        PREFERRED_FORMAT    = :ico
        PREFERRED_EXTENSION = ".ico"
      end
    end
  end
end
