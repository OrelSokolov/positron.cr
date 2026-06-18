module CrystalUI
  {% if flag?(:darwin) && !flag?(:ios) %}
    alias WebViewAdapter = Adapters::MacOS::WKWebView
    alias TrayAdapter = Adapters::MacOS::StatusBarTray
  {% end %}
end
