module CrystalUI
  # Platform-agnostic icon contract.
  #
  # Different OS APIs expect different raw icon formats (SVG for GTK,
  # ICO/PNG for Windows NotifyIcon, PNG/template for macOS NSStatusBar).
  # This port declares the preferred source format and extension for the
  # current platform. The compile-time `embed_application_files` macro uses
  # it to pick the right icon asset automatically.
  class IconPort
    PREFERRED_FORMAT = :svg
    PREFERRED_EXTENSION = ".svg"
  end
end
