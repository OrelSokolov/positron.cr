module CrystalUI
  {% if flag?(:win32) %}
    alias TrayAdapter = Adapters::Windows::NotifyIconTray
  {% end %}
end
