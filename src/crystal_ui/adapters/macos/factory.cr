module CrystalUI
  {% if flag?(:darwin) && !flag?(:ios) %}
    alias TrayAdapter = Adapters::MacOS::StatusBarTray
  {% end %}
end
