module Positron
  {% if flag?(:linux) && !flag?(:android) %}
    alias WebViewAdapter = Adapters::Linux::WebKitGTK
    alias TrayAdapter = Adapters::Linux::AppIndicatorTray
    alias IconAdapter = Adapters::Linux::Icon
  {% end %}
end
