require "../src/positron"
require "../src/positron/plugins/file_picker/plugin"
require "spec"

{% if flag?(:darwin) && !flag?(:ios) %}
  describe Positron::Plugins::MacOSFilePickerAdapter do
    describe ".extensions_for" do
      it "collects explicit extensions" do
        Positron::Plugins::MacOSFilePickerAdapter.extensions_for(".txt,.md")
          .should eq(["txt", "md"])
      end

      it "maps MIME types to common extensions" do
        Positron::Plugins::MacOSFilePickerAdapter.extensions_for("text/plain,image/*")
          .should eq(["txt", "png", "jpg", "jpeg", "gif", "webp", "tiff"])
      end

      it "treats a lone star or empty value as no filtering" do
        Positron::Plugins::MacOSFilePickerAdapter.extensions_for("*").should eq([] of String)
        Positron::Plugins::MacOSFilePickerAdapter.extensions_for("").should eq([] of String)
      end

      it "ignores whitespace and unknown MIME types" do
        Positron::Plugins::MacOSFilePickerAdapter.extensions_for(" .txt , application/x-unknown ")
          .should eq(["txt"])
      end
    end
  end
{% else %}
  # The macOS adapter is only compiled on darwin targets.
{% end %}
