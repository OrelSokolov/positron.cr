require "../src/positron/ports/webview_port"
require "spec"

# Minimal concrete port exercising the close-veto hook headlessly.
class VetoTestWebView < Positron::WebViewPort
  def create(config : Positron::WebViewConfig); end

  def load_url(url : String); end

  def load_html(html : String, base_url : String? = nil); end

  def eval_js(script : String); end

  def show; end

  def hide; end

  def close; end

  def bind(name : String, &handler : String -> String); end
end

describe Positron::WebViewPort do
  it "allows close when no before_close callback is set" do
    webview = VetoTestWebView.new
    webview.before_close.should be_nil
    webview.allow_close?.should be_true
  end

  it "allows close when the callback returns true" do
    webview = VetoTestWebView.new
    webview.before_close = -> { true }
    webview.allow_close?.should be_true
  end

  it "vetoes close when the callback returns false" do
    webview = VetoTestWebView.new
    webview.before_close = -> { false }
    webview.allow_close?.should be_false
  end
end
