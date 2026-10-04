module Positron
  {% if flag?(:win32) %}
    alias WebViewAdapter = Adapters::Windows::WebView2
    alias TrayAdapter = Adapters::Windows::NotifyIconTray
    alias IconAdapter = Adapters::Windows::Icon
  {% end %}
end
