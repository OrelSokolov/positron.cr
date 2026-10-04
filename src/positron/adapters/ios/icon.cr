module Positron
  module Adapters
    module IOS
      # iOS icon adapter.
      #
      # iOS uses PNG for app icons, notifications and status bar.
      class Icon < IconPort
        PREFERRED_FORMAT    = :png
        PREFERRED_EXTENSION = ".png"
      end
    end
  end
end
