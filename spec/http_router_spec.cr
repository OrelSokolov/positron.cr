require "../src/positron"
require "spec"
require "json"

class NotesController < Positron::Controller
  def index(request)
    {"notes" => [{"id" => 1, "title" => "a"}, {"id" => 2, "title" => "b"}],
     "page"  => request.query["page"]? || "1"}
  end

  @[Positron::Heavy]
  def show(request)
    {"id" => request.params["id"].to_i, "title" => "note #{request.params["id"]}"}
  end

  def update(request)
    {"id" => request.params["id"].to_i, "title" => request.body["title"].as_s}
  end

  def destroy(request)
    Positron::Response.new(204, JSON.parse("null"))
  end

  def boom(request)
    raise "kaboom"
  end

  actions
end

def build_test_router
  Positron::Router.new.draw do |r|
    r.get "/api/hello" { |req| {"hello" => "world"} }
    r.get "/api/echo-name/:name" { |req| {"name" => req.params["name"]} }
    r.heavy do
      r.get "/api/burn" { |req| {"burned" => true} }
    end
    r.resources "/api/notes", NotesController
    r.get "/api/boom", NotesController, "boom"
  end
end

describe Positron::Router do
  it "matches a static route and wraps the hash as 200 JSON" do
    router = build_test_router
    response = router.handle(Positron::Request.new("GET", "/api/hello"))
    response.status.should eq(200)
    response.body["hello"].as_s.should eq("world")
  end

  it "extracts :params and parses the query string" do
    router = build_test_router
    response = router.handle(Positron::Request.new("GET", "/api/echo-name/%D0%BF%D1%80%D0%B8%D0%B2%D0%B5%D1%82"))
    response.body["name"].as_s.should eq("привет")
  end

  it "returns 404 for unknown routes" do
    router = build_test_router
    response = router.handle(Positron::Request.new("GET", "/api/nope"))
    response.status.should eq(404)
    response.body["error"].as_s.should contain("no route")
  end

  it "returns 404 when the path matches but the method does not" do
    router = build_test_router
    router.handle(Positron::Request.new("DELETE", "/api/hello")).status.should eq(404)
  end

  it "converts handler exceptions into 500 with the root cause message" do
    router = build_test_router
    response = router.handle(Positron::Request.new("GET", "/api/boom"))
    response.status.should eq(500)
    response.body["error"].as_s.should eq("kaboom")
  end

  it "marks routes inside r.heavy as heavy" do
    router = build_test_router
    route = router.match("GET", "/api/burn").not_nil![0]
    route.heavy.should be_true
  end

  it "marks block routes outside r.heavy as light" do
    router = build_test_router
    route = router.match("GET", "/api/hello").not_nil![0]
    route.heavy.should be_false
  end

  it "namespace prefixes nested routes" do
    router = Positron::Router.new.draw do |r|
      r.namespace "/api" do
        r.namespace "/v1" do
          r.get "/ping" { |req| {"pong" => true} }
        end
      end
      r.get "/outside" { |req| {"ok" => true} }
    end
    router.handle(Positron::Request.new("GET", "/api/v1/ping")).status.should eq(200)
    router.handle(Positron::Request.new("GET", "/outside")).status.should eq(200)
    router.handle(Positron::Request.new("GET", "/v1/ping")).status.should eq(404)
  end
end

describe Positron::Router do
  it "resources maps the five RESTful actions" do
    router = build_test_router
    router.handle(Positron::Request.new("GET", "/api/notes")).tap do |res|
      res.status.should eq(200)
      res.body["notes"].as_a.size.should eq(2)
      res.body["page"].as_s.should eq("1")
    end
    router.handle(Positron::Request.new("GET", "/api/notes?page=3")).body["page"].as_s.should eq("3")
    router.handle(Positron::Request.new("GET", "/api/notes/7")).tap do |res|
      res.status.should eq(200)
      res.body["id"].as_i.should eq(7)
    end
    body = JSON.parse(%({"title": "changed"}))
    router.handle(Positron::Request.new("PUT", "/api/notes/7", body: body)).tap do |res|
      res.body["title"].as_s.should eq("changed")
    end
    router.handle(Positron::Request.new("DELETE", "/api/notes/7")).status.should eq(204)
  end

  it "auto-detects @[Heavy] controller actions at registration" do
    NotesController.heavy_action?("show").should be_true
    NotesController.heavy_action?("index").should be_false
    router = build_test_router
    router.match("GET", "/api/notes/1").not_nil![0].heavy.should be_true
    router.match("GET", "/api/notes").not_nil![0].heavy.should be_false
  end

  it "runs heavy routes on the parallel worker pool (not the caller fiber)" do
    router = build_test_router
    caller = Fiber.current
    executed_on = Channel(Fiber?).new(1)
    # Replace the burn handler with one that reports its fiber.
    router.add_route("get", "/api/fiber-probe",
      Positron::Router::BlockHandler.new { |req|
        executed_on.send(Fiber.current)
        Positron::Response.new(200, JSON.parse(%({"ok": true})))
      }, heavy: true)
    response = router.handle(Positron::Request.new("GET", "/api/fiber-probe"))
    response.status.should eq(200)
    worker = executed_on.receive
    worker.should_not eq(caller)
  end

  it "middleware can short-circuit with a response" do
    router = build_test_router
    Positron::Router.use do |req|
      next nil unless req.path == "/api/hello"
      Positron::Response.new(418, JSON.parse(%({"error": "teapot"})))
    end
    begin
      router.handle(Positron::Request.new("GET", "/api/hello")).status.should eq(418)
      router.handle(Positron::Request.new("GET", "/api/notes")).status.should eq(200)
    ensure
      Positron::Router.middleware.clear
    end
  end
end

describe "virtual HTTP envelope" do
  it "routes type:http through the app router and resolves with {status, body}" do
    app = TestHttpApp.new
    host = HttpSpecHost.new(app)
    envelope = {
      "type" => "http", "id" => "req-1", "method" => "GET",
      "path" => "/api/hello?x=1", "body" => {} of String => JSON::Any,
    }.to_json
    js = host.dispatch_now(envelope)
    js.should start_with("window.__positronResolve(")
    js.should contain(%("status":200))
    js.should contain(%("hello":"world"))
  end

  it "resolves (not rejects) with 404 for unknown routes" do
    host = HttpSpecHost.new(TestHttpApp.new)
    envelope = %({"type":"http","id":"r2","method":"GET","path":"/api/missing"})
    js = host.dispatch_now(envelope)
    js.should contain("true")
    js.should contain(%("status":404))
  end
end

class TestHttpApp < Positron::Application
  def on_ready; end

  def application_html : String
    ""
  end

  def draw_routes(router)
    router.get "/api/hello" { |req| {"hello" => "world"} }
  end
end

class NullHttpWebView < Positron::WebViewPort
  def create(config : Positron::WebViewConfig); end
  def load_url(url : String); end
  def load_html(html : String, base_url : String? = nil); end
  def eval_js(script : String); end
  def show; end
  def hide; end
  def close; end
  def bind(name : String, &handler : String -> String); end
end

class NullHttpTray < Positron::TrayPort
  def supported? : Bool
    false
  end

  def create(icon : Positron::IconSource? = nil, title : String? = nil); end
  def set_icon(icon : Positron::IconSource); end
  def set_title(title : String); end
  def set_tooltip(tooltip : String); end
  def add_or_update_item(item : Positron::TrayItem); end
  def add_separator(id : Int32); end
  def remove_item(id : Int32); end
  def show_item(id : Int32); end
  def hide_item(id : Int32); end
  def on_item_click(&block : Int32 ->); end
  def show; end
  def hide; end
  def quit; end
end

class HttpSpecHost < Positron::Host
  getter webview : Positron::WebViewPort
  getter tray : Positron::TrayPort

  def initialize(app : Positron::Application)
    @webview = NullHttpWebView.new
    @tray = NullHttpTray.new
    super(app)
  end

  def eval_js(script : String); end

  def run_on_main(&block : ->) : Nil
    block.call
  end

  def run; end

  def stop; end
end
