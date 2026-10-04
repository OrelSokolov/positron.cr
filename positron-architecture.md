# Positron Architecture: Host-Shim Pattern (v1.1)

## 1. Философия: Crystal — Host, Нативный Код — Shim

В традиционных гибридных фреймворках (Capacitor, Cordova, React Native) нативный слой является **хозяином** (host), а JS/Crystal — гостем. В Positron мы инвертируем это отношение:

- **Crystal Host** — единственный runtime, управляющий состоянием, бизнес-логикой, навигацией, жизненным циклом и плагинами.
- **Native Shim** — тонкий, пассивный адаптер (100–200 строк на Kotlin/Swift/C), который предоставляет Crystal доступ к OS API: WebView, System Tray, Notifications, Camera, Permissions.
- **Shim не принимает решений.** Он только выполняет команды от Crystal и пересылает OS-события обратно.

### Аналогия
Crystal Host — это ядро Linux. Native Shim — это драйверы устройств. Драйвер не решает, что делать системе. Он только транслирует команды ядра в железо и прерывания железа — в события ядра.

---

## 2. Архитектура верхнего уровня

```
┌──────────────────────────────────────────────────────────────┐
│                    Positron Host                             │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────────────┐  │
│  │ App Runtime  │ │ PluginMgr    │ │ Command Registry     │  │
│  │ (state, nav) │ │ (camera,push)│ │ (macros @[Command])  │  │
│  └──────┬───────┘ └──────┬───────┘ └──────────┬───────────┘  │
│         │                │                    │               │
│  ┌──────▼───────┐ ┌──────▼───────┐ ┌────────▼──────────┐  │
│  │ SystemTray   │ │ ActivityPort │ │ NotificationPort    │  │
│  │ Port         │ │ (lifecycle)  │ │                     │  │
│  └──────┬───────┘ └──────┬───────┘ └────────┬────────────┘  │
│         │                │                    │               │
│  ┌──────▼───────┐ ┌──────▼───────┐ ┌────────▼──────────┐  │
│  │ WebViewPort  │ │ DeepLinkPort │ │ PermissionPort      │  │
│  │ (UI surface) │ │              │ │                     │  │
│  └──────┬───────┘ └──────┬───────┘ └────────┬────────────┘  │
│         │                │                    │               │
│  ┌──────▼────────────────────────────────────▼──────────┐  │
│  │              EventBus (Internal Pub/Sub)                │  │
│  │  • Plugin-to-Plugin communication                       │  │
│  │  • OS event broadcasting                                │  │
│  │  • Decoupled state updates                              │  │
│  └────────────────────────────────────────────────────────┘  │
│         │                │                    │               │
│  ┌──────▼────────────────────────────────────▼──────────┐  │
│  │              EventLoop (Unified Dispatcher)             │  │
│  │  Desktop: libuv + GTK/NSRunLoop/Win32 integration     │  │
│  │  Mobile:  libuv + JNI/C-ABI callbacks                 │  │
│  └────────────────────────────────────────────────────────┘  │
└─────────┼────────────────┼────────────────────┼───────────────┘
          │                │                    │
          ▼                ▼                    ▼
┌──────────────────────────────────────────────────────────────┐
│              Native Shim (Platform Adapter)                 │
│  Desktop: GTK/Cocoa/Win32    Mobile: Kotlin/Swift           │
│  • Создаёт WebView по команде                               │
│  • Выполняет `evalJS`                                       │
│  • Показывает System Tray по команде                        │
│  • Запрашивает Permission по команде                         │
│  • Пересылает OS events → Crystal C callbacks               │
└──────────────────────────────────────────────────────────────┘
```

---

## 3. EventBus (Internal Pub/Sub)

EventBus — это **внутренняя нервная система** Crystal Host. Он не связан с JS bridge и не торчит наружу. Это чисто Crystal-штука для декомпозиции.

### Зачем нужен

Без EventBus получается жесткая связанность:
```crystal
# Плохо: Plugin знает про WebView напрямую
class PushPlugin
  def on_receive(payload)
    webview.eval_js("window.onPush(#{payload})")  # жесткая зависимость
  end
end
```

С EventBus — слабая связанность:
```crystal
# Хорошо: Plugin публикует событие, а кто подписан — тот реагируet
class PushPlugin
  def on_receive(payload)
    EventBus.emit("push.received", payload)
  end
end

# WebViewAdapter подписан и решает, что делать
EventBus.on("push.received") do |payload|
  webview.eval_js("window.onPush(#{payload.to_json})")
end

# SystemTray тоже может подписаться
EventBus.on("push.received") do |payload|
  tray.show_badge(1) if payload["unread"]
end
```

### Реализация

```crystal
# src/positron/event_bus.cr
module Positron::EventBus
  alias Handler = Proc(JSON::Any, Void)
  @@subscribers = Hash(String, Array(Handler)).new { |h, k| h[k] = [] of Handler }
  @@mutex = Mutex.new

  def self.on(event : String, &handler : JSON::Any ->)
    @@mutex.synchronize do
      @@subscribers[event] << handler
    end
  end

  def self.emit(event : String, payload : JSON::Any | Hash | NamedTuple)
    json = payload.is_a?(JSON::Any) ? payload : JSON.parse(payload.to_json)
    handlers = @@mutex.synchronize { @@subscribers[event]?.dup || [] of Handler }
    handlers.each do |h|
      spawn do
        begin
          h.call(json)
        rescue ex
          Log.error { "EventBus handler error for #{event}: #{ex.message}" }
        end
      end
    end
  end

  def self.once(event : String, &handler : JSON::Any ->)
    wrapper = ->(payload : JSON::Any) do
      handler.call(payload)
      off(event, wrapper)
    end
    on(event, &wrapper)
  end

  def self.off(event : String, handler : Handler)
    @@mutex.synchronize do
      @@subscribers[event].delete(handler)
    end
  end
end
```

### Потоки событий

| Event | Publisher | Subscribers |
|---|---|---|
| `lifecycle.resume` | OS Shim → Host | PluginManager, PushPlugin, SyncPlugin |
| `lifecycle.pause` | OS Shim → Host | PluginManager (остановить таймеры), WebView (сохранить state) |
| `push.received` | PushPlugin | WebViewAdapter (eval JS), TrayAdapter (badge), NotificationAdapter (local notification) |
| `deep_link.opened` | OS Shim → Host | AppRouter (навигация), AuthPlugin (callback) |
| `permission.changed` | PermissionPlugin | CameraPlugin (включить/выключить), LocationPlugin |
| `window.focused` | Desktop Shim | AppRuntime (resume sync), TrayAdapter (убрать badge) |
| `command.invoked` | WebViewAdapter | CommandRegistry (dispatch) |
| `command.completed` | CommandRegistry | WebViewAdapter (Promise resolve), Logger |

---

## 4. EventLoop (Unified Dispatcher)

EventLoop — это **сердце** Host. Он решает проблему: Crystal использует fibers + libevent/libuv, а нативный GUI требует своего event loop (GTK main loop, NSRunLoop, Win32 GetMessage).

### Проблема

Если просто запустить `gtk_main()` или `CFRunLoopRun()`, Crystal fibers умрут — они не получат управление. Если запустить только `LibUV.run()`, GUI не отрисуется.

### Решение: Cooperative Integration

**Desktop Linux (GTK + libuv):**
```crystal
# src/positron/event_loop/linux.cr
class Positron::EventLoop::Linux
  def initialize
    @running = false
    # Получаем файловый дескриптор GTK main context
    @gtk_context = LibGTK.g_main_context_default()
  end

  def run
    @running = true

    # Интегрируем GTK с libuv через idle watcher
    # Каждый тик libuv проверяет, есть ли события GTK
    LibUV.idle_start(@idle_handle) do
      # Обрабатываем pending GTK events без блокировки
      while LibGTK.g_main_context_pending(@gtk_context) != 0
        LibGTK.g_main_context_iteration(@gtk_context, 0) # non-blocking
      end
    end

    # Запускаем libuv event loop (он управляет Crystal fibers)
    LibUV.run(LibUV::UV_RUN_DEFAULT)
  end

  def stop
    @running = false
    LibUV.stop(@loop)
  end
end
```

**Desktop macOS (NSRunLoop + libuv):**
```crystal
# src/positron/event_loop/macos.cr
class Positron::EventLoop::MacOS
  def run
    # Получаем CFRunLoop текущего потока
    @run_loop = LibCF.CFRunLoopGetCurrent()

    # Создаём CFRunLoopSource из libuv socket
    # Каждый раз, когда libuv хочет что-то обработать,
    # он сигналит через socket → CFRunLoop просыпается
    integrate_libuv_with_cfrunloop()

    # Блокируем в CFRunLoop (GUI thread)
    LibCF.CFRunLoopRun()
  end

  private def integrate_libuv_with_cfrunloop
    # Создаём pipe/socket для сигнализации
    # LibUV watcher → write to pipe → CFRunLoopSource fires → process UV events
    # Это тот же паттерн, что использует Node.js для интеграции с Cocoa
  end
end
```

**Desktop Windows (Win32 message loop + libuv):**
```crystal
# src/positron/event_loop/windows.cr
class Positron::EventLoop::Windows
  def run
    # Создаём hidden window для получения сообщений
    @hwnd = create_message_window()

    # Интегрируем libuv с Win32 через custom timer/window message
    # LibUV запущен в отдельном потоке или через GetMessage hook

    msg = LibWin32::MSG.new
    while @running
      # Non-blocking PeekMessage
      while LibWin32.PeekMessageW(pointerof(msg), nil, 0, 0, LibWin32::PM_REMOVE) != 0
        LibWin32.TranslateMessage(pointerof(msg))
        LibWin32.DispatchMessageW(pointerof(msg))
      end

      # Обрабатываем libuv events без блокировки
      LibUV.run(LibUV::UV_RUN_NOWAIT)

      # Sleep 1ms чтобы не жрать CPU
      LibC.Sleep(1)
    end
  end
end
```

**Mobile Android (Java Looper + libuv):**
```crystal
# src/positron/event_loop/android.cr
class Positron::EventLoop::Android
  def run
    # На Android нет единого event loop как на desktop.
    # UI thread имеет Looper. Crystal runtime крутится в .so,
    # но его fibers управляются libuv.

    # Решение: libuv крутится в отдельном native thread (pthread).
    # Когда нужно обновить UI — JNI вызов в Activity.runOnUiThread()

    @uv_thread = Thread.new do
      LibUV.run(LibUV::UV_RUN_DEFAULT)
    end
  end

  def emit_to_ui(&block)
    # JNI: activity.runOnUiThread(Runnable { block.call })
    JNI.run_on_ui_thread(block)
  end
end
```

**Mobile iOS (CFRunLoop + libuv):**
```crystal
# src/positron/event_loop/ios.cr
class Positron::EventLoop::IOS
  def run
    # Аналогично macOS, но внутри UIApplicationMain thread
    integrate_libuv_with_cfrunloop()
    # CFRunLoopRun() уже запущен системой, мы только интегрируемся
  end
end
```

### Factory (compile-time)

```crystal
# src/positron/event_loop/factory.cr
module Positron
  {% if flag?(:linux) && !flag?(:android) %}
    alias EventLoop = EventLoop::Linux
  {% elsif flag?(:darwin) && !flag?(:ios) %}
    alias EventLoop = EventLoop::MacOS
  {% elsif flag?(:win32) %}
    alias EventLoop = EventLoop::Windows
  {% elsif flag?(:android) %}
    alias EventLoop = EventLoop::Android
  {% elsif flag?(:ios) %}
    alias EventLoop = EventLoop::IOS
  {% end %}
end
```

---

## 5. Host API (то, что видит разработчик)

```crystal
# src/my_app.cr
class MyApp < Positron::Application
  @[Command]
  def login(email : String, password : String) : AuthResult
    # Бизнес-логика полностью в Crystal
  end

  @[Command]
  def take_photo : String
    # Crystal решает: нужна камера
    # PluginManager зовёт нативный Camera Shim
    result = plugins.camera.capture
    result.path
  end

  def on_ready
    # Crystal управляет UI
    webview.navigate("https://app.local/dashboard")

    # Crystal управляет System Tray (desktop)
    tray.show(icon: "icon.png", menu: ["Open", "Quit"])

    # Crystal управляет уведомлениями
    notifications.send(title: "Привет", body: "Приложение готово")
  end

  def on_deep_link(url : String)
    # Crystal решает, что делать с deep link
    if url.starts_with?("myapp://auth/callback")
      handle_auth_callback(url)
    end
  end

  def on_permission_result(permission : String, granted : Bool)
    # Crystal обрабатывает результат запроса прав
    if granted && permission == "camera"
      webview.eval_js("window.app.cameraAllowed()")
    end
  end
end

MyApp.new.run
```

**Важно:** Разработчик никогда не пишет `if platform == "android"`. Он пишет `plugins.camera.capture`, а Host сам маршрутизирует в нужный Shim.

---

## 6. Desktop: Host создаёт окно напрямую

На десктопе Crystal Host является **единственным процессом**.

```crystal
# Desktop Factory (compile-time)
{% if flag?(:linux) %}
  alias WebViewAdapter = Adapters::Linux::WebKitGTK
  alias TrayAdapter    = Adapters::Linux::AppIndicator
{% elsif flag?(:darwin) %}
  alias WebViewAdapter = Adapters::MacOS::WKWebView
  alias TrayAdapter    = Adapters::MacOS::NSStatusBar
{% elsif flag?(:win32) %}
  alias WebViewAdapter = Adapters::Windows::WebView2
  alias TrayAdapter    = Adapters::Windows::NotifyIcon
{% end %}
```

```crystal
class Positron::DesktopHost
  @webview : WebViewAdapter
  @tray : TrayAdapter

  def run
    @webview.create(title: "MyApp", width: 1200, height: 800)
    @webview.bind("crystal") { |json| dispatch(json) }
    @webview.navigate("https://app.local")

    @tray.create(icon: "icon.png")
    @tray.on_click { @webview.show }

    # Нативный event loop (GTK/Cocoa/Win32) — блокирует
    @webview.run_event_loop
  end
end
```

---

## 7. Mobile Android: Host через JNI

### 7.1. Архитектура

```
Android OS
  ├─ MainActivity.kt (Shim — 80 строк)
  │   ├─ onCreate() → создаёт WebView + загружает libcrystal.so
  │   ├─ onResume() → JNI.crystal_event("lifecycle", "resume")
  │   ├─ onPause()  → JNI.crystal_event("lifecycle", "pause")
  │   ├─ onNewIntent() → JNI.crystal_event("deep_link", url)
  │   ├─ onRequestPermissionsResult() → JNI.crystal_event("permission", ...)
  │   └─ onReceivePush() → JNI.crystal_event("push", payload)
  │
  ├─ PositronBridge.kt (JNI Executor — 60 строк)
  │   ├─ evalJs(script)      ← вызывается из Crystal
  │   ├─ showNotification()  ← вызывается из Crystal
  │   ├─ requestPermission() ← вызывается из Crystal
  │   └─ startCameraIntent() ← вызывается из Crystal
  │
  └─ libcrystal.so (Crystal Host)
      ├─ crystal_init(activity, webview) → создаёт Application
      ├─ crystal_dispatch(json) → CommandRegistry
      ├─ crystal_event(name, payload) → PluginManager → EventBus
      └─ crystal_eval_js_response(id, result) → Promise resolve
```

### 7.2. Kotlin Shim (полный шаблон)

```kotlin
// gen/android/app/src/main/java/com/positron/shim/MainActivity.kt
package com.positron.shim

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.core.app.ActivityCompat

class MainActivity : Activity() {
    private lateinit var webView: WebView
    private lateinit var bridge: PositronBridge

    companion object {
        init {
            System.loadLibrary("crystal")
        }
    }

    // ==== OS ENTRY POINT ====
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        webView = WebView(this).apply {
            settings.javaScriptEnabled = true
            webViewClient = WebViewClient()
        }
        setContentView(webView)

        // Передаём управление Crystal Host
        bridge = PositronBridge(this, webView)
        nativeInit(bridge, webView)
    }

    // ==== LIFECYCLE SHIM ====
    override fun onResume() {
        super.onResume()
        nativeEvent("lifecycle", "{"state":"resume"}")
    }

    override fun onPause() {
        super.onPause()
        nativeEvent("lifecycle", "{"state":"pause"}")
    }

    override fun onDestroy() {
        super.onDestroy()
        nativeEvent("lifecycle", "{"state":"destroy"}")
    }

    // ==== DEEP LINK SHIM ====
    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        val url = intent?.data?.toString() ?: return
        nativeEvent("deep_link", "{"url":"$url"}")
    }

    // ==== PERMISSION SHIM ====
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        val json = buildString {
            append("{"code":$requestCode,"permissions":[")
            permissions.joinTo(this, ",") { ""$it"" }
            append("],"results":[")
            grantResults.joinTo(this, ",")
            append("]}")
        }
        nativeEvent("permission_result", json)
    }

    // ==== JNI INTERFACE ====
    private external fun nativeInit(bridge: PositronBridge, webView: WebView)
    private external fun nativeEvent(name: String, payload: String)
}
```

```kotlin
// gen/android/app/src/main/java/com/positron/shim/PositronBridge.kt
package com.positron.shim

import android.app.Activity
import android.webkit.WebView
import androidx.core.app.ActivityCompat

// Этот класс — пассивный Executor. Он только выполняет команды от Crystal.
class PositronBridge(private val activity: Activity, private val webView: WebView) {

    // Вызывается из Crystal через JNI
    fun evalJs(script: String) {
        activity.runOnUiThread {
            webView.evaluateJavascript(script, null)
        }
    }

    // Вызывается из Crystal
    fun requestPermission(permission: String) {
        ActivityCompat.requestPermissions(activity, arrayOf(permission), 0)
    }

    // Вызывается из Crystal
    fun showNotification(title: String, body: String) {
        // ... Android NotificationManager
    }

    // Вызывается из Crystal
    fun startCameraIntent() {
        // ... Intent(MediaStore.ACTION_IMAGE_CAPTURE)
    }

    // Вызывается из Crystal
    fun setStatusBarColor(color: String) {
        // ... Window.setStatusBarColor
    }

    // Вызывается из Crystal
    fun shareText(text: String) {
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "text/plain"
            putExtra(Intent.EXTRA_TEXT, text)
        }
        activity.startActivity(Intent.createChooser(intent, null))
    }
}
```

### 7.3. Crystal Host (Android)

```crystal
# src/positron/adapters/android/host.cr
@[Link("crystal_android")] # libcrystal.so
lib LibJNI
  fun crystal_android_init(activity : Void*, webview : Void*) : Void*
  fun crystal_android_dispatch(ctx : Void*, json : LibC::Char*) : Void
  fun crystal_android_event(ctx : Void*, name : LibC::Char*, payload : LibC::Char*) : Void
end

class Positron::AndroidHost
  @ctx : Void*
  @bridge : AndroidBridge

  def initialize(activity_ptr : Void*, webview_ptr : Void*)
    @ctx = LibJNI.crystal_android_init(activity_ptr, webview_ptr)
    @bridge = AndroidBridge.new(activity_ptr, webview_ptr)
  end

  # ==== OS EVENTS (Kotlin → Crystal) ====
  def on_event(name : String, payload : String)
    case name
    when "lifecycle"
      handle_lifecycle(JSON.parse(payload))
    when "deep_link"
      app.on_deep_link(payload)
    when "permission_result"
      handle_permission(JSON.parse(payload))
    when "push"
      app.plugins.push.on_receive(JSON.parse(payload))
    end
  end

  # ==== COMMANDS TO SHIM (Crystal → Kotlin) ====
  def eval_js(script : String)
    @bridge.eval_js(script)
  end

  def request_permission(name : String)
    @bridge.request_permission(name)
  end

  def show_notification(title : String, body : String)
    @bridge.show_notification(title, body)
  end
end

# FFI-обёртка над PositronBridge Kotlin-классом
class Positron::AndroidBridge
  @activity : Void*
  @webview : Void*

  def initialize(activity : Void*, webview : Void*)
    @activity = activity
    @webview = webview
  end

  def eval_js(script : String)
    # JNI вызов: PositronBridge.evalJs(script)
    JNI.call_void_method(@bridge_obj, "evalJs", script)
  end

  def request_permission(name : String)
    JNI.call_void_method(@bridge_obj, "requestPermission", name)
  end
end
```

### 7.4. C Entry Points (линкуются с libcrystal.so)

```crystal
# src/positron/entry/android.cr
# Эти функции видны из JNI

@[Extern]
fun crystal_android_init(activity : Void*, webview : Void*) : Void*
  host = Positron::AndroidHost.new(activity, webview)
  Positron::Context.store(host)
  host.as(Void*)
end

@[Extern]
fun crystal_android_dispatch(ctx : Void*, json : LibC::Char*) : Void
  host = Positron::Context.retrieve(ctx)
  request = JSON.parse(String.new(json))
  response = host.dispatch_command(request)
  host.eval_js("window.__positronResolve(#{request["id"]}, #{response.to_json})")
end

@[Extern]
fun crystal_android_event(ctx : Void*, name : LibC::Char*, payload : LibC::Char*) : Void
  host = Positron::Context.retrieve(ctx)
  host.on_event(String.new(name), String.new(payload))
end
```

---

## 8. Mobile iOS: Host через C-ABI

### 8.1. Архитектура

```
iOS OS
  ├─ AppDelegate.swift / ViewController.swift (Shim — 80 строк)
  │   ├─ application(_:didFinishLaunchingWithOptions:) 
  │   │   → создаёт WKWebView + загружает libCrystal.a
  │   ├─ applicationDidBecomeActive() → crystal_event("lifecycle", "resume")
  │   ├─ applicationDidEnterBackground() → crystal_event("lifecycle", "pause")
  │   ├─ application(_:openURL:) → crystal_event("deep_link", url)
  │   └─ userNotificationCenter(_:didReceive:) → crystal_event("push", payload)
  │
  ├─ CrystalExecutor.swift (C-ABI Executor — 60 строк)
  │   ├─ evalJs(script)      ← вызывается из Crystal
  │   ├─ requestPermission() ← вызывается из Crystal
  │   ├─ showNotification()  ← вызывается из Crystal
  │   └─ hapticFeedback()    ← вызывается из Crystal
  │
  └─ libCrystal.a (Crystal Host)
      ├─ crystal_ios_init(webview, viewController) → создаёт Application
      ├─ crystal_ios_dispatch(json) → CommandRegistry
      └─ crystal_ios_event(name, payload) → PluginManager → EventBus
```

### 8.2. Swift Shim (полный шаблон)

```swift
// gen/ios/MyApp/AppDelegate.swift
import UIKit
import WebKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?
    var crystalHost: OpaquePointer? // указатель на Crystal Host

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        window = UIWindow(frame: UIScreen.main.bounds)

        let viewController = ViewController()
        window?.rootViewController = viewController
        window?.makeKeyAndVisible()

        // Передаём управление Crystal Host
        crystalHost = crystal_ios_init(viewController.webView, viewController)

        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        crystal_ios_event(crystalHost, "lifecycle", "{"state":"resume"}")
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        crystal_ios_event(crystalHost, "lifecycle", "{"state":"pause"}")
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        let json = "{"url":"\(url.absoluteString)"}"
        crystal_ios_event(crystalHost, "deep_link", json)
        return true
    }
}
```

```swift
// gen/ios/MyApp/ViewController.swift
import UIKit
import WebKit

class ViewController: UIViewController, WKScriptMessageHandler {
    var webView: WKWebView!
    var crystalExecutor: CrystalExecutor!

    override func viewDidLoad() {
        super.viewDidLoad()

        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "crystal")

        webView = WKWebView(frame: view.bounds, configuration: config)
        view.addSubview(webView)

        // Executor — пассивный инструмент Crystal Host
        crystalExecutor = CrystalExecutor(webView: webView, viewController: self)
    }

    // ==== BRIDGE: JS → Swift → Crystal ====
    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        let body = message.body as! String
        // Пересылаем в Crystal Host
        crystal_ios_dispatch(crystalHost, body)
    }
}
```

```swift
// gen/ios/MyApp/CrystalExecutor.swift
import UIKit
import WebKit
import UserNotifications

// Пассивный Executor. Только выполняет команды от Crystal.
class CrystalExecutor {
    let webView: WKWebView
    let viewController: UIViewController

    init(webView: WKWebView, viewController: UIViewController) {
        self.webView = webView
        self.viewController = viewController
    }

    // Вызывается из Crystal через C-ABI
    func evalJs(_ script: String) {
        DispatchQueue.main.async {
            self.webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }

    // Вызывается из Crystal
    func requestPermission(_ name: String) {
        switch name {
        case "camera":
            AVCaptureDevice.requestAccess(for: .video) { granted in
                let json = "{"permission":"camera","granted":\(granted)}"
                crystal_ios_event(crystalHost, "permission_result", json)
            }
        case "notifications":
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                let json = "{"permission":"notifications","granted":\(granted)}"
                crystal_ios_event(crystalHost, "permission_result", json)
            }
        default: break
        }
    }

    // Вызывается из Crystal
    func showNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    // Вызывается из Crystal
    func hapticFeedback(style: String) {
        let type: UIImpactFeedbackGenerator.FeedbackStyle
        switch style {
        case "light": type = .light
        case "medium": type = .medium
        case "heavy": type = .heavy
        default: type = .medium
        }
        let generator = UIImpactFeedbackGenerator(style: type)
        generator.impactOccurred()
    }

    // Вызывается из Crystal
    func share(_ text: String) {
        let activity = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        viewController.present(activity, animated: true)
    }
}
```

### 8.3. Crystal Host (iOS)

```crystal
# src/positron/adapters/ios/host.cr
@[Link(framework: "WebKit")]
@[Link(framework: "UIKit")]
@[Link(framework: "UserNotifications")]
lib LibIOS
  fun crystal_ios_init(webview : Void*, viewController : Void*) : Void*
  fun crystal_ios_dispatch(ctx : Void*, json : LibC::Char*) : Void
  fun crystal_ios_event(ctx : Void*, name : LibC::Char*, payload : LibC::Char*) : Void
end

class Positron::IOSHost
  @ctx : Void*
  @executor : IOSExecutor

  def initialize(webview_ptr : Void*, vc_ptr : Void*)
    @ctx = LibIOS.crystal_ios_init(webview_ptr, vc_ptr)
    @executor = IOSExecutor.new(webview_ptr, vc_ptr)
  end

  def on_event(name : String, payload : String)
    case name
    when "lifecycle"      then handle_lifecycle(JSON.parse(payload))
    when "deep_link"      then app.on_deep_link(payload)
    when "permission_result" then handle_permission(JSON.parse(payload))
    when "push"           then app.plugins.push.on_receive(JSON.parse(payload))
    end
  end

  def eval_js(script : String)
    @executor.eval_js(script)
  end

  def request_permission(name : String)
    @executor.request_permission(name)
  end

  def show_notification(title : String, body : String)
    @executor.show_notification(title, body)
  end

  def haptic(style : String)
    @executor.haptic(style)
  end
end
```

### 8.4. C Entry Points (libCrystal.a)

```crystal
# src/positron/entry/ios.cr
@[Extern]
fun crystal_ios_init(webview : Void*, viewController : Void*) : Void*
  host = Positron::IOSHost.new(webview, viewController)
  Positron::Context.store(host)
  host.as(Void*)
end

@[Extern]
fun crystal_ios_dispatch(ctx : Void*, json : LibC::Char*) : Void
  host = Positron::Context.retrieve(ctx)
  request = JSON.parse(String.new(json))
  response = host.dispatch_command(request)
  host.eval_js("window.__positronResolve(#{request["id"]}, #{response.to_json})")
end

@[Extern]
fun crystal_ios_event(ctx : Void*, name : LibC::Char*, payload : LibC::Char*) : Void
  host = Positron::Context.retrieve(ctx)
  host.on_event(String.new(name), String.new(payload))
end
```

---

## 9. Plugin System (универсальный)

```crystal
# src/positron/plugin.cr
abstract class Positron::Plugin
  abstract def name : String
  abstract def supported_platforms : Array(Symbol)

  def on_event(event : String, payload : JSON::Any)
    # override in subclass
  end
end

# Пример: Camera Plugin
class Positron::Plugins::Camera < Positron::Plugin
  def name; "camera" end
  def supported_platforms; [:desktop, :android, :ios] end

  @[Command]
  def capture : PhotoResult
    case platform
    when :android
      host.as(AndroidHost).executor.start_camera_intent
    when :ios
      host.as(IOSHost).executor.start_camera_intent
    when :desktop
      host.as(DesktopHost).webview.open_file_dialog(accept: "image/*")
    end
    # ... async result через event
  end
end
```

---

## 10. CLI: Генерация нативных проектов

```bash
# Инициализация
$ positron init my-app
> Создано my-app/
> Создано my-app/src/my_app.cr
> Создано my-app/frontend/

# Добавление mobile
$ cd my-app
$ positron mobile init
> Создано gen/android/ (Gradle проект с Kotlin Shim)
> Создано gen/ios/ (Xcode проект с Swift Shim)

# Сборка
$ positron build --target android
> 1. Cross-compile Crystal → libcrystal.so (NDK)
> 2. Copy .so → gen/android/app/jniLibs/arm64-v8a/
> 3. Generate assets from frontend/dist
> 4. ./gradlew assembleRelease
> 5. Output: my-app.apk

$ positron build --target ios
> 1. Cross-compile Crystal → libCrystal.a (iOS SDK)
> 2. Copy .a → gen/ios/Frameworks/
> 3. xcodebuild -scheme MyApp -destination 'generic/platform=iOS'
> 4. Output: MyApp.ipa
```

---

## 11. Сравнение с Electron

### 11.1. Архитектура процессов

| | **Electron** | **Positron** |
|---|---|---|
| **Процессы** | Main Process (Node.js) + Renderer Process (Chromium per window) + GPU Process | **Single Process** (Crystal Host) + WebView (UI surface) |
| **IPC** | Named pipes между процессами. Structured Clone Algorithm. | **In-memory** (zero-copy). FFI callback или direct function call. |
| **Сериализация** | Structured Clone (ограниченные типы) | JSON (универсально) или shared memory для бинарных данных |
| **Event Loop** | Node.js libuv + Chromium message loop integration (сложная интеграция двух loop'ов) | Единый EventLoop (libuv + нативный GUI loop cooperative integration) |
| **Размер** | 150–300 MB (bundles Chromium + Node.js) | **5–15 MB** (system WebView + Crystal runtime) |
| **Память** | Высокая (Chromium per window) | Низкая (один WebView, нативный runtime) |
| **Startup** | 2–5 секунд | **200–500 мс** |
| **Язык бэкенда** | JavaScript (Node.js) | Crystal (compiled, type-safe, no GC pauses) |
| **Безопасность** | Renderer sandbox optional. Main process — полный доступ. | WebView sandboxed by OS. Crystal Host — compiled, no eval. |
| **Multi-window** | Отдельный Renderer process per window | Один Host, несколько WebView (легковесно) |

### 11.2. Кто круче в чём

#### Electron круче:

1. **Ecosystem.** 100000+ npm пакетов. Любая интеграция — есть библиотека.
2. **Developer Experience.** `npm install electron`, `npm start`, и ты в игре. DevTools из коробки.
3. **Browser Compatibility.** Bundles Chromium — ты знаешь точную версию движка. Не нужно тестировать под 10 версий WebView.
4. **Desktop-only фичи.** Native menus, global shortcuts, auto-updater, crash reporter — всё встроено и battle-tested.
5. **Зрелость.** 10+ лет, используется VS Code, Slack, Discord, Figma. Документация огромная.
6. **Debugging.** Chrome DevTools для renderer, Node.js debugger для main process. Два мира — два дебаггера.

#### Positron круче:

1. **Размер.** 10–20x меньше бинарника. Это критично для distribution и обновлений.
2. **Память.** Нет overhead от Chromium per window. Один WebView + легкий runtime.
3. **Скорость запуска.** Нативный код стартует мгновенно. Нет инициализации Node.js + Chromium.
4. **Единый процесс.** Нет IPC-головной боли. Нет structured clone limitations. Прямой вызов функций.
5. **Типизация.** Crystal — статически типизирован. Ошибки на этапе компиляции, а не в рантайме.
6. **Производительность бэкенда.** Compiled код быстрее JS для CPU-bound задач (криптография, обработка данных).
7. **Единый язык.** Бэкенд и "native logic" на одном языке. Не нужно переключаться между JS и C++ или Rust.
8. **EventBus + EventLoop.** Встроенная decoupled архитектура. Electron не имеет встроенного event bus — разработчик изобретает сам.
9. **Mobile-ready архитектура.** Electron не поддерживает mobile. Positron изначально спроектирован для desktop + mobile (iOS/Android).
10. **Предсказуемость памяти.** Crystal без GC-pauses ( Boehm GC в Crystal есть, но он более предсказуем, чем V8 GC в Node.js + Chromium).

### 11.3. Когда что выбирать

**Выбирай Electron, если:**
- Ты делаешь сложный desktop-only инструмент (IDE, дизайнер, редактор).
- Тебе нужны bleeding-edge web APIs (WebGL2, WebGPU, File System Access API).
- Команда — чистые JS-разработчики.
- Нужна интеграция с огромным количеством Node.js модулей.
- Ты не боишься 200 MB бандла.

**Выбирай Positron, если:**
- Ты делаешь легковесное приложение (калькулятор, чат, тулза, SaaS-wrapper).
- Тебе важен размер и скорость запуска (distribution, обновления, low-end devices).
- Ты хочешь один язык для всего (Crystal бэкенд + Crystal desktop + mobile).
- Ты делаешь embedded или IoT (маленький footprint, нативный код).
- Тебе нужна mobile поддержка (iOS/Android) из той же кодбазы.
- Ты ненавидишь IPC и хочешь прямой вызов функций.

---

## 12. Roadmap

| Фаза | Срок | Цель |
|------|------|------|
| **1. Desktop MVP** | 2–3 мес | Linux (WebKitGTK) + Windows (WebView2) + macOS (WKWebView). Рабочее окно, JS↔Crystal bridge, System Tray, EventLoop, EventBus. |
| **2. Mobile Shim** | +2 мес | Android Kotlin Shim + iOS Swift Shim. Crystal Host управляет WebView, lifecycle, permissions через EventBus. |
| **3. Plugin SDK** | +1 мес | Camera, Push, Biometric, Share. Унифицированный Plugin API + EventBus integration. |
| **4. CLI & DX** | +1 мес | `positron init`, `build`, `dev`. Генерация нативных проектов. |
| **5. Product Launch** | +2 мес | Зубряк на Positron. Dogfooding. Публикация на GitHub. |

---

## 13. Принципы, которые нельзя нарушать

1. **Crystal Host — единственный источник правды.** Shim не принимает решений.
2. **Shim — тонкий.** Если Kotlin/Swift файл больше 200 строк — архитектура сломана.
3. **Zero platform `if` в бизнес-логике.** Только в Adapters и Plugin implementations.
4. **Compile-time dispatch.** `{% if flag?(:android) %}` для выбора адаптера, не runtime `if`.
5. **Bridge — JSON-RPC.** Все вызовы через единый канал: `{"id": 1, "cmd": "greet", "args": {}}`.
6. **OS Events — всегда в Host.** `onResume`, `onPush`, `onDeepLink` — обрабатываются в Crystal через EventBus.
7. **EventBus для decoupling.** Никакой прямой связи Plugin ↔ WebView. Только события.
8. **EventLoop cooperative.** Не блокировать GUI thread. LibUV + native loop integration.

---

*Документ версии 1.1. Готов к реализации.*
