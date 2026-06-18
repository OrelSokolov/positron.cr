module CrystalUI
  {% if flag?(:android) %}
    alias MobileHostAdapter = Adapters::Android::Host
  {% end %}
end
