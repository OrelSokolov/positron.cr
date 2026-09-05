module CrystalUI
  module Adapters
    module MacOS
      # macOS icon adapter.
      #
      # NSStatusItem works best with a PNG template image.
      class Icon < IconPort
        PREFERRED_FORMAT    = :png
        PREFERRED_EXTENSION = ".png"
      end
    end
  end
end
