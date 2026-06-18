module CrystalUI
  {% if flag?(:win32) %}
    alias WebViewAdapter = Adapters::Windows::WebView2
    alias TrayAdapter = Adapters::Windows::NotifyIconTray
  {% end %}
end
