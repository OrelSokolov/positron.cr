module Positron
  # Cross-platform icon descriptor.
  #
  # Different native APIs expect different raw formats (SVG for GTK,
  # ICO/PNG for Windows NotifyIcon, PNG/template for macOS NSStatusBar).
  # The adapter is responsible for converting the source bytes to a native
  # handle when necessary.
  struct IconSource
    getter bytes : Bytes
    getter format : Symbol

    def initialize(@bytes : Bytes, @format : Symbol = :png)
    end

    def svg? : Bool
      @format == :svg
    end

    def png? : Bool
      @format == :png
    end

    def ico? : Bool
      @format == :ico
    end
  end
end
