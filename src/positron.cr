require "json"
require "log"

require "./positron/event_bus"
require "./positron/async_work"
require "./positron/http_router"
{% if compare_versions(Crystal::VERSION, "1.21.0") >= 0 %}
  require "./positron/async_work_parallel"
{% else %}
  require "./positron/async_work_fallback"
{% end %}
require "./positron/command_registry"
require "./positron/state_manager"
require "./positron/plugin"
require "./positron/plugins/logger"
require "./positron/plugins/preferences/plugin"
require "./positron/plugins/clipboard/plugin"
require "./positron/plugins/file_picker/plugin"
require "./positron/plugins/save_file_dialog/plugin"
require "./positron/plugins/theme/plugin"
require "./positron/plugins/display/plugin"
require "./positron/plugins/window/plugin"
require "./positron/plugins/filesystem/plugin"
require "./positron/plugins/dialogs/plugin"
require "./positron/plugins/lifecycle/plugin"
require "./positron/plugins/permissions/plugin"
require "./positron/plugins/camera/plugin"
# Unix-only plugins: deep_links binds unix sockets, secure_storage links
# OpenSSL. Gated so Windows builds (adapter stubs) stay dependency-free.
# deep_links (AF_UNIX, Win10+) and secure_storage (Crystal's OpenSSL
# bindings ship as DLLs on Windows) both work on Windows now. Android:
# deep_links works (bionic AF_UNIX); secure_storage stays out until the
# Android Keystore adapter lands (no OpenSSL linked into the APK). iOS:
# same story — no OpenSSL in the sim/device link, Keychain adapter is
# future work.
{% if flag?(:unix) || flag?(:win32) %}
  require "./positron/plugins/deep_links/plugin"
{% end %}
{% if (flag?(:unix) && !flag?(:android) && !flag?(:ios)) || flag?(:win32) %}
  require "./positron/plugins/secure_storage/plugin"
{% end %}
require "./positron/tray_item"
require "./positron/icon_source"
require "./positron/web_view_config"
require "./positron/js_facade_generator"
require "./positron/bindings_generator"
# Dev asset server pulls http/server (→ OpenSSL linkage); iOS links no
# OpenSSL — embedded assets only.
{% unless flag?(:ios) %}
  require "./positron/dev/asset_server"
{% end %}
require "./positron/ports/event_loop_port"
require "./positron/ports/webview_port"
require "./positron/ports/tray_port"
require "./positron/ports/icon_port"
require "./positron/host"

# Desktop platforms
{% if flag?(:linux) && !flag?(:android) %}
  require "./positron/adapters/linux/webkit_gtk"
  require "./positron/adapters/linux/app_indicator_tray"
  require "./positron/adapters/linux/icon"
  require "./positron/adapters/linux/factory"
  require "./positron/event_loop/linux"
  require "./positron/desktop_host"
{% end %}

{% if flag?(:win32) %}
  require "./positron/adapters/windows/win32"
  require "./positron/adapters/windows/lib_webview"
  require "./positron/adapters/windows/webview2"
  require "./positron/adapters/windows/tray"
  require "./positron/adapters/windows/icon"
  require "./positron/adapters/windows/factory"
  require "./positron/event_loop/windows"
  require "./positron/desktop_host"
{% end %}

{% if flag?(:darwin) && !flag?(:ios) %}
  require "./positron/adapters/macos/objc"
  require "./positron/adapters/macos/webview"
  require "./positron/adapters/macos/tray"
  require "./positron/adapters/macos/icon"
  require "./positron/adapters/macos/factory"
  require "./positron/event_loop/macos"
  require "./positron/desktop_host"
{% end %}

# Mobile platforms
{% if flag?(:android) %}
  require "./positron/mobile/queue"
  require "./positron/mobile/asset_router"
  require "./positron/mobile_host"
  require "./positron/adapters/android/icon"
  require "./positron/adapters/android/factory"
  require "./positron/adapters/android/jni"
  require "./positron/adapters/android/shim"
  require "./positron/adapters/android/webview"
  require "./positron/adapters/android/host"
  require "./positron/event_loop/android"
  require "./positron/entry/android"
{% end %}

{% if flag?(:ios) %}
  # iOS follows the desktop model, not the Android one: Crystal owns
  # the main thread (the iOS/ driver calls crystal_main_entry from C),
  # the event loop hands the process to UIApplicationMain and the
  # adapters build the UIWindow/WKWebView from the app delegate. No
  # mobile_host/C-seam plumbing is involved.
  require "./positron/adapters/ios/objc"
  require "./positron/adapters/ios/webview"
  require "./positron/adapters/ios/tray"
  require "./positron/adapters/ios/icon"
  require "./positron/adapters/ios/factory"
  require "./positron/event_loop/ios"
  require "./positron/desktop_host"
{% end %}

require "./positron/event_loop/factory"
require "./positron/application"

module Positron
  VERSION = "0.2.0"
end
