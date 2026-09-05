module CrystalUI
  module Adapters
    module Linux
      # Linux icon adapter.
      #
      # GTK can render SVG directly, so SVG is the preferred source format.
      class Icon < IconPort
        PREFERRED_FORMAT    = :svg
        PREFERRED_EXTENSION = ".svg"
      end
    end
  end
end
