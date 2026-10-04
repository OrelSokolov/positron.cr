module Positron
  {% if flag?(:ios) %}
    alias MobileHostAdapter = Adapters::IOS::Host
    alias IconAdapter = Adapters::IOS::Icon
  {% end %}
end
