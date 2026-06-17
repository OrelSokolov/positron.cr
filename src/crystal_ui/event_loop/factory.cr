module CrystalUI
  # Compile-time alias that selects the native event loop integration
  # for the current platform. We cannot name it `EventLoop` because that
  # identifier is already used as the containing module namespace.
  {% if flag?(:linux) && !flag?(:android) %}
    alias PlatformEventLoop = EventLoop::Linux
  {% elsif flag?(:darwin) && !flag?(:ios) %}
    alias PlatformEventLoop = EventLoop::MacOS
  {% elsif flag?(:win32) %}
    alias PlatformEventLoop = EventLoop::Windows
  {% elsif flag?(:android) %}
    alias PlatformEventLoop = EventLoop::Android
  {% elsif flag?(:ios) %}
    alias PlatformEventLoop = EventLoop::IOS
  {% end %}
end
