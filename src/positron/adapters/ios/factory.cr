module Positron
  {% if flag?(:ios) %}
    alias WebViewAdapter = Adapters::IOS::WKWebView
    alias TrayAdapter = Adapters::IOS::NullTray
    alias IconAdapter = Adapters::IOS::Icon
  {% end %}
end
