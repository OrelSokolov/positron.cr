require "../../src/positron"

# Camera demo — live preview through the OS WebView.
#
# The frontend is served over the custom `app://` scheme from a tree
# embedded at compile time (`embed_directory` + WebViewPort#
# register_uri_scheme). That matters for media APIs: a custom scheme is
# a secure context, while pages loaded with `load_html` have an opaque
# origin and expose no `navigator.mediaDevices` at all.
#
# Capture comes in two flavours, picked at runtime:
#   - web (`getUserMedia` / `enumerateDevices` / `applyConstraints`) —
#     the host's part is granting the WebView's permission requests
#     (see the WebKitGTK `permission-request` handler in the Linux
#     adapter; every grant is broadcast as `permission.requested` and
#     logged live below);
#   - native (the camera plugin, real on iOS) — the host captures
#     in-process through AVFoundation and the frontend pulls frames
#     over this `app://` scheme (`/native-frame`, 12-byte header +
#     RGBA). WKWebView runs getUserMedia in XPC processes the app
#     cannot reach, so on iOS this is the only working path.
class CameraDemoApp < Positron::Application
  # The frontend tree, "/"-rooted. `embed_directory` paths resolve from
  # the compiler's working directory (the repo root, like `rake
  # build:examples` and CI run it).
  embed_directory "examples/camera/frontend"
  # Icon accessors (icon_source etc.) for the window and tray.
  embed_application_files(__DIR__, "../../assets/crystal-icon")

  def configure_plugins
    use Positron::Plugins::Camera
  end

  def on_ready
    webview.register_uri_scheme("app") do |path|
      serve_app_file(path)
    end

    webview.create(Positron::WebViewConfig.new(
      title: "Positron Camera Demo",
      width: 960,
      height: 640,
      icon: icon_source(:svg)
    ))

    webview.bind("crystal") do |json|
      host.dispatch(json)
    end

    webview.load_url("app://camera/application.html")
  end

  # --- embedded frontend serving (app:// scheme) ---

  private def serve_app_file(path : String) : Positron::SchemeResponse?
    return serve_native_frame if path == "/native-frame"
    path = "/index.html" if path.blank? || path == "/"
    bytes = embedded_file?(path) || return nil

    # HTML gets the Positron JS runtime + state hydration injected —
    # the same substitution the dev asset server performs for served
    # pages, so Positron.on(...) works in embedded mode too.
    if path.ends_with?(".html")
      html = String.new(bytes)
        .sub("{{RUNTIME_JS}}", app_runtime_js)
        .sub("{{HYDRATE_JS}}", app_hydrate_js)
        .sub("{{ICON_HTML}}", embedded_icon_html)
      return Positron::SchemeResponse.new(html.to_slice, "text/html; charset=utf-8")
    end

    Positron::SchemeResponse.new(bytes, mime_for(path))
  end

  private def app_runtime_js : String
    facade = Positron::JSFacadeGenerator.new(plugins.to_a)
    facade.runtime_js
  end

  private def app_hydrate_js : String
    facade = Positron::JSFacadeGenerator.new(plugins.to_a)
    snapshot = host.try(&.state_manager.snapshot)
    return facade.hydrate_js(JSON.parse("{}").as_h) unless snapshot
    facade.hydrate_js(snapshot)
  end

  # Latest native-capture frame: 12-byte header (magic "PRFA" +
  # u32 LE width/height) + RGBA bytes. Empty body = no frame yet (the
  # frontend keeps polling).
  private def serve_native_frame : Positron::SchemeResponse?
    camera = plugins["camera"]?.as?(Positron::Plugins::Camera)
    return Positron::SchemeResponse.new(Bytes.empty, "application/octet-stream") unless camera

    if frame = camera.adapter.latest_frame
      header = Positron::Plugins::Camera.frame_header(frame[:width], frame[:height])
      bytes = Bytes.new(header.size + frame[:bytes].size)
      header.copy_to(bytes)
      frame[:bytes].copy_to(bytes + header.size)
      Positron::SchemeResponse.new(bytes, "application/octet-stream")
    else
      Positron::SchemeResponse.new(Bytes.empty, "application/octet-stream")
    end
  end

  private def mime_for(path : String) : String
    case File.extname(path)
    when ".html" then "text/html; charset=utf-8"
    when ".css"  then "text/css; charset=utf-8"
    when ".js"   then "application/javascript; charset=utf-8"
    when ".svg"  then "image/svg+xml"
    when ".png"  then "image/png"
    else              "application/octet-stream"
    end
  end
end

CameraDemoApp.new.run
