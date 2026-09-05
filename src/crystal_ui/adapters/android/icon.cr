module CrystalUI
  module Adapters
    module Android
      # Android icon adapter.
      #
      # Android resources and notifications use PNG.
      class Icon < IconPort
        PREFERRED_FORMAT    = :png
        PREFERRED_EXTENSION = ".png"
      end
    end
  end
end
