require "json"
require "log"

require "./crystal_ui/event_bus"
require "./crystal_ui/command_registry"
require "./crystal_ui/state_manager"
require "./crystal_ui/plugin"
require "./crystal_ui/plugins/logger"
require "./crystal_ui/plugins/preferences/plugin"
require "./crystal_ui/plugins/clipboard/plugin"
require "./crystal_ui/plugins/file_picker/plugin"
require "./crystal_ui/plugins/save_file_dialog/plugin"
require "./crystal_ui/plugins/theme/plugin"
require "./crystal_ui/plugins/display/plugin"
require "./crystal_ui/plugins/window/plugin"
require "./crystal_ui/plugins/filesystem/plugin"
require "./crystal_ui/plugins/dialogs/plugin"
require "./crystal_ui/plugins/lifecycle/plugin"
require "./crystal_ui/plugins/permissions/plugin"
# Unix-only plugins: deep_links binds unix sockets, secure_storage links
# OpenSSL. Gated so Windows builds (adapter stubs) stay dependency-free.
{% if flag?(:unix) %}
  require "./crystal_ui/plugins/deep_links/plugin"
  require "./crystal_ui/plugins/secure_storage/plugin"
{% end %}
require "./crystal_ui/tray_item"
require "./crystal_ui/icon_source"
require "./crystal_ui/web_view_config"
require "./crystal_ui/js_facade_generator"
require "./crystal_ui/bindings_generator"
require "./crystal_ui/dev/asset_server"
require "./crystal_ui/ports/event_loop_port"
require "./crystal_ui/ports/webview_port"
require "./crystal_ui/ports/tray_port"
require "./crystal_ui/ports/icon_port"
require "./crystal_ui/host"

# Desktop platforms
{% if flag?(:linux) && !flag?(:android) %}
  require "./crystal_ui/adapters/linux/webkit_gtk"
  require "./crystal_ui/adapters/linux/app_indicator_tray"
  require "./crystal_ui/adapters/linux/icon"
  require "./crystal_ui/adapters/linux/factory"
  require "./crystal_ui/event_loop/linux"
  require "./crystal_ui/desktop_host"
{% end %}

{% if flag?(:win32) %}
  require "./crystal_ui/adapters/windows/webview2"
  require "./crystal_ui/adapters/windows/tray"
  require "./crystal_ui/adapters/windows/icon"
  require "./crystal_ui/adapters/windows/factory"
  require "./crystal_ui/event_loop/windows"
  require "./crystal_ui/desktop_host"
{% end %}

{% if flag?(:darwin) && !flag?(:ios) %}
  require "./crystal_ui/adapters/macos/webview"
  require "./crystal_ui/adapters/macos/tray"
  require "./crystal_ui/adapters/macos/icon"
  require "./crystal_ui/adapters/macos/factory"
  require "./crystal_ui/event_loop/macos"
  require "./crystal_ui/desktop_host"
{% end %}

# Mobile platforms
{% if flag?(:android) %}
  require "./crystal_ui/mobile_host"
  require "./crystal_ui/adapters/android/host"
  require "./crystal_ui/adapters/android/icon"
  require "./crystal_ui/adapters/android/factory"
  require "./crystal_ui/event_loop/android"
{% end %}

{% if flag?(:ios) %}
  require "./crystal_ui/mobile_host"
  require "./crystal_ui/adapters/ios/host"
  require "./crystal_ui/adapters/ios/icon"
  require "./crystal_ui/adapters/ios/factory"
  require "./crystal_ui/event_loop/ios"
{% end %}

require "./crystal_ui/event_loop/factory"
require "./crystal_ui/application"

module CrystalUI
  VERSION = "0.1.0"
end
