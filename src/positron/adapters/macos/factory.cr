module Positron
  {% if flag?(:darwin) && !flag?(:ios) %}
    alias WebViewAdapter = Adapters::MacOS::WKWebView
    alias TrayAdapter = Adapters::MacOS::StatusBarTray
    alias IconAdapter = Adapters::MacOS::Icon
  {% end %}
end
