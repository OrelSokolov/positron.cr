module CrystalUI
  {% if flag?(:ios) %}
    alias MobileHostAdapter = Adapters::IOS::Host
  {% end %}
end
