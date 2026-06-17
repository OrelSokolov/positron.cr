module CrystalUI
  {% if flag?(:linux) && !flag?(:android) %}
    alias WebViewAdapter = Adapters::Linux::WebKitGTK
    alias TrayAdapter = Adapters::Linux::AppIndicatorTray
  {% end %}
end
