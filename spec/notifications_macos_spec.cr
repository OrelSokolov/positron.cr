require "../src/positron"
require "../src/positron/plugins/notifications/plugin"
require "spec"

{% if flag?(:darwin) && !flag?(:ios) %}
  describe Positron::Plugins::MacOSNotificationsAdapter do
    it "builds an osascript notification line" do
      script = Positron::Plugins::MacOSNotificationsAdapter.notification_script(
        "Hello", "Body text")

      script.should eq(%(display notification "Body text" with title "Hello"))
    end

    it "escapes quotes and backslashes for AppleScript" do
      script = Positron::Plugins::MacOSNotificationsAdapter.notification_script(
        %(say "hi" \\ now), %(the "body"))

      script.should eq(%(display notification "the \\"body\\"" with title "say \\"hi\\" \\\\ now"))
    end
  end
{% else %}
  # The macOS adapter is only compiled on darwin targets.
{% end %}
