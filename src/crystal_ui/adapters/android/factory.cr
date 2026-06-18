module CrystalUI
  {% if flag?(:android) %}
    alias MobileHostAdapter = Adapters::Android::Host
    alias IconAdapter = Adapters::Android::Icon
  {% end %}
end
