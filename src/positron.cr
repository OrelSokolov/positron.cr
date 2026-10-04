require "json"
require "log"

require "./positron/event_bus"
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
# Unix-only plugins: deep_links binds unix sockets, secure_storage links
# OpenSSL. Gated so Windows builds (adapter stubs) stay dependency-free.
{% if flag?(:unix) %}
  require "./positron/plugins/deep_links/plugin"
  require "./positron/plugins/secure_storage/plugin"
{% end %}
require "./positron/tray_item"
require "./positron/icon_source"
require "./positron/web_view_config"
require "./positron/js_facade_generator"
require "./positron/bindings_generator"
require "./positron/dev/asset_server"
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
  require "./positron/adapters/macos/webview"
  require "./positron/adapters/macos/tray"
  require "./positron/adapters/macos/icon"
  require "./positron/adapters/macos/factory"
  require "./positron/event_loop/macos"
  require "./positron/desktop_host"
{% end %}

# Mobile platforms
{% if flag?(:android) %}
  require "./positron/mobile_host"
  require "./positron/adapters/android/host"
  require "./positron/adapters/android/icon"
  require "./positron/adapters/android/factory"
  require "./positron/event_loop/android"
{% end %}

{% if flag?(:ios) %}
  require "./positron/mobile_host"
  require "./positron/adapters/ios/host"
  require "./positron/adapters/ios/icon"
  require "./positron/adapters/ios/factory"
  require "./positron/event_loop/ios"
{% end %}

require "./positron/event_loop/factory"
require "./positron/application"

module Positron
  VERSION = "0.1.0"
end
