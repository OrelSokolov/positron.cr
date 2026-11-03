require "../src/positron/mobile/asset_router"
require "spec"

describe Positron::Mobile::AssetRouter do
  it "serves registered paths through the handler" do
    router = Positron::Mobile::AssetRouter.new
    router.register_uri_scheme("app") do |path|
      if path == "/index.html"
        Positron::SchemeResponse.new("hello".to_slice, "text/html; charset=utf-8")
      end
    end

    response = router.serve("app", "/index.html")
    response.should_not be_nil
    String.new(response.not_nil!.bytes).should eq("hello")
  end

  it "normalizes empty and root paths to the index document" do
    router = Positron::Mobile::AssetRouter.new
    seen = [] of String
    router.register_uri_scheme("app") { |path| seen << path; nil }

    router.serve("app", "")
    router.serve("app", "/")
    router.serve("app", "/index.html?v=1#top")

    seen.should eq(["/index.html", "/index.html", "/index.html"])
  end

  it "rejects paths that escape the root" do
    router = Positron::Mobile::AssetRouter.new
    called = false
    router.register_uri_scheme("app") { |path| called = true; nil }

    router.serve("app", "/../../etc/passwd").should be_nil
    called.should be_false
  end

  it "returns nil for unregistered schemes and missing files" do
    router = Positron::Mobile::AssetRouter.new
    router.serve("app", "/index.html").should be_nil
    router.scheme_registered?("app").should be_false

    router.register_uri_scheme("app") { nil }
    router.serve("app", "/nope.html").should be_nil
    router.serve("other", "/index.html").should be_nil
  end

  it "detects MIME types by extension" do
    Positron::Mobile::AssetRouter.mime_for("/a/b.html").should eq("text/html; charset=utf-8")
    Positron::Mobile::AssetRouter.mime_for("/app.js").should eq("text/javascript; charset=utf-8")
    Positron::Mobile::AssetRouter.mime_for("/img/x.PNG").should eq("image/png")
    Positron::Mobile::AssetRouter.mime_for("/font.woff2").should eq("font/woff2")
    Positron::Mobile::AssetRouter.mime_for("/blob.unknown").should eq("application/octet-stream")
  end
end
