require "log"
require "./adapter"
require "../../adapters/macos/objc"

module Positron::Plugins
  # macOS implementation of system notifications using
  # UNUserNotificationCenter (macOS 10.14+), driven through the
  # pure-Crystal ObjC runtime layer (`adapters/macos/objc.cr`).
  #
  # Details worth knowing:
  #
  #   * UNUserNotificationCenter derives its "bundle proxy" from
  #     `NSBundle.mainBundle`. A bare binary (no .app bundle with an
  #     Info.plist) makes `currentNotificationCenter` throw
  #     NSInternalInconsistencyException — and usernotificationsd would
  #     reject the client anyway. For that case the adapter falls back
  #     to a scripted backend: `osascript display notification`, which
  #     posts through Script Editor's identity and needs no bundle or
  #     signature (dev mode; no click callbacks, no clear).
  #   * The async UNUserNotificationCenter APIs take ObjC blocks, which
  #     this adapter builds by hand (see `LibBlock`): global block
  #     literals capture no state, so a heap struct per handler with
  #     BLOCK_IS_GLOBAL set and an NSBlock-subclass isa is a valid,
  #     immortal block object.
  #   * UN completion handlers run on a background queue while the
  #     command fiber polls class-level atomics (`spin`) — blocking the
  #     main thread cannot deadlock the UN callbacks.
  #   * The delegate answers `willPresent` with banner|list|sound so
  #     notifications show while the app is frontmost, and
  #     `didReceiveNotificationResponse` feeds `notification.clicked`.
  class MacOSNotificationsAdapter < NotificationsAdapter
    LOG = Log.for("positron.plugins.notifications")

    private OBJC = Positron::Adapters::MacOS::ObjC
    private LIB_OBJC = Positron::Adapters::MacOS::LibObjC

    # UNAuthorizationOptionBadge | .Sound | .Alert
    AUTH_OPTIONS = 1 | 2 | 4

    # UNNotificationPresentationOptionSound | .List | .Banner (macOS 11+)
    FOREGROUND_OPTIONS = 2 | 8 | 16

    DID_RECEIVE_SELECTOR = "userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:"
    WILL_PRESENT_SELECTOR = "userNotificationCenter:willPresentNotification:withCompletionHandler:"

    # enum flags from Block_private.h
    BLOCK_IS_GLOBAL = 1 << 28

    # Block literal layout (Block_private.h). Global blocks keep no
    # captured state, so this is all there is to it; see `make_block`.
    lib LibBlock
      struct Layout
        isa : Void*
        flags : Int32
        unused : Int32
        invoke : Void*
        descriptor : Void*
      end

      struct Descriptor
        unused : UInt64
        size : UInt64
        copy_helper : Void*
        dispose_helper : Void*
      end
    end

    @center : Void*?
    @center_opened = false
    @scripted = false
    @delegate_obj : Void*?
    @auth_block_obj : Void*?
    @settings_block_obj : Void*?
    @added_block_obj : Void*?

    @@instance : MacOSNotificationsAdapter?

    # Wait state shared with the UN completion blocks (see class docs).
    @@auth_state = Atomic(Int32).new(0) # 0 = pending, 1 = done
    @@auth_granted = false
    @@settings_state = Atomic(Int32).new(0)
    @@settings_status = 0

    # IMPs installed on the delegate class and invoke functions of the
    # block literals; class vars keep them alive for the process
    # lifetime.
    @@did_receive_imp : Proc(Void*, Void*, Void*, Void*, Void*, Nil)?
    @@will_present_imp : Proc(Void*, Void*, Void*, Void*, Void*, Nil)?
    @@auth_imp : Proc(Void*, UInt8, Void*, Nil)?
    @@settings_imp : Proc(Void*, Void*, Nil)?
    @@added_imp : Proc(Void*, Nil)?
    @@imps_ready = false

    def initialize
      install_imps
    end

    def send(id : String, title : String, body : String) : String
      center = notification_center
      if center.nil? || center.null?
        script_send(title, body)
        return id
      end

      OBJC.with_autorelease_pool do
        content = OBJC.send0(
          OBJC.send0(OBJC.cls("UNMutableNotificationContent"), OBJC.sel("alloc")),
          OBJC.sel("init"))
        OBJC.send1(content, OBJC.sel("setTitle:"), OBJC.nsstr(title))
        OBJC.send1(content, OBJC.sel("setBody:"), OBJC.nsstr(body))
        request = OBJC.send3(
          OBJC.cls("UNNotificationRequest"),
          OBJC.sel("requestWithIdentifier:content:trigger:"),
          OBJC.nsstr(id), content, Pointer(Void).null)
        OBJC.send2(center, OBJC.sel("addNotificationRequest:withCompletionHandler:"),
          request, added_block)
      end
      id
    end

    def clear(id : String) : Bool
      center = notification_center
      return false if center.nil? || center.null?

      OBJC.with_autorelease_pool do
        identifiers = OBJC.send1(OBJC.cls("NSArray"), OBJC.sel("arrayWithObject:"), OBJC.nsstr(id))
        OBJC.send1(center, OBJC.sel("removePendingNotificationRequestsWithIdentifiers:"), identifiers)
        OBJC.send1(center, OBJC.sel("removeDeliveredNotificationsWithIdentifiers:"), identifiers)
      end
      true
    end

    def request_permission : Bool
      center = notification_center
      return true if scripted? # scripted backend needs no permission
      return false if center.nil? || center.null?

      @@auth_state.set(0)
      @@auth_granted = false
      OBJC.send2(center, OBJC.sel("requestAuthorizationWithOptions:completionHandler:"),
        OBJC.int_arg(AUTH_OPTIONS), auth_block)
      spin { break if @@auth_state.get == 1 }
      @@auth_state.get == 1 && @@auth_granted
    end

    def check_permission : Bool
      center = notification_center
      return true if scripted? # scripted backend needs no permission
      return false if center.nil? || center.null?

      @@settings_state.set(0)
      OBJC.send1(center, OBJC.sel("getNotificationSettingsWithCompletionHandler:"), settings_block)
      spin { break if @@settings_state.get == 1 }
      return false unless @@settings_state.get == 1

      # UNAuthorizationStatus: 0 notDetermined, 1 denied, 2 authorized,
      # 3 provisional, 4 ephemeral.
      {2, 3, 4}.includes?(@@settings_status)
    end

    # --- Internals ---

    protected def handle_click(response : Void*) : Nil
      notification = OBJC.send0(response, OBJC.sel("notification"))
      request = OBJC.send0(notification, OBJC.sel("request"))
      identifier = OBJC.to_s(OBJC.send0(request, OBJC.sel("identifier")))
      emit_click(identifier || "")
    end

    private def install_imps : Nil
      return if @@imps_ready
      @@imps_ready = true

      @@did_receive_imp = ->(_objc_self : Void*, _cmd : Void*, _center : Void*, response : Void*, handler : Void*) {
        adapter = @@instance
        adapter.try(&.handle_click(response))
        adapter.try(&.call_void_block(handler))
      }
      @@will_present_imp = ->(_objc_self : Void*, _cmd : Void*, _center : Void*, _notification : Void*, handler : Void*) {
        @@instance.try(&.call_options_block(handler, FOREGROUND_OPTIONS.to_i64))
      }
      @@auth_imp = ->(_block : Void*, granted : UInt8, _error : Void*) {
        @@auth_granted = granted != 0
        @@auth_state.set(1)
      }
      @@settings_imp = ->(_block : Void*, settings : Void*) {
        @@settings_status = OBJC.send0_i(settings, OBJC.sel("authorizationStatus")).to_i32
        @@settings_state.set(1)
      }
      @@added_imp = ->(_block : Void*) { }
    end

    # Lazily opens (and caches) the notification center, installing the
    # click delegate. Returns nil when the process is not running from an
    # app bundle or the framework is unavailable — both make
    # UNUserNotificationCenter unusable — after switching the adapter to
    # the scripted osascript fallback (dev mode).
    private def notification_center : Void*?
      return @center if @center_opened
      @center_opened = true

      unless bundle_backed?
        @scripted = true
        LOG.info { "bare binary (no .app bundle) — notifications fall back to osascript (dev mode); " \
                   "run from a signed bundle (positron package --install) for native banners and click callbacks" }
        @center = nil
        return nil
      end

      # UserNotifications is not linked at build time; load it so the
      # UN* classes register with the ObjC runtime.
      LibC.dlopen("/System/Library/Frameworks/UserNotifications.framework/UserNotifications",
        LibC::RTLD_LAZY)
      center_class = OBJC.cls?("UNUserNotificationCenter")
      if center_class.nil?
        LOG.warn { "UNUserNotificationCenter unavailable (macOS < 10.14?) — notifications disabled" }
        @center = nil
        return nil
      end

      center = OBJC.send0(center_class, OBJC.sel("currentNotificationCenter"))
      install_delegate(center) unless center.null?
      @center = center
      center
    end

    # UNUserNotificationCenter throws NSInternalInconsistencyException
    # ("bundle proxy is nil") when mainBundle has no bundle identifier.
    private def bundle_backed? : Bool
      bundle = OBJC.send0(OBJC.cls("NSBundle"), OBJC.sel("mainBundle"))
      ident = OBJC.to_s(OBJC.send0(bundle, OBJC.sel("bundleIdentifier")))
      !ident.to_s.empty?
    end

    # --- Scripted dev fallback ---
    #
    # `display notification` posts through Script Editor's identity, so
    # it works from a bare dev binary with no bundle or signature.
    # Limitations: no click callbacks (on_click never fires) and
    # notifications cannot be cleared by id.

    private def scripted? : Bool
      @scripted
    end

    private def script_send(title : String, body : String) : Nil
      status = Process.run("osascript", ["-e", self.class.notification_script(title, body)],
        output: Process::Redirect::Close, error: Process::Redirect::Close)
      unless status.success?
        LOG.warn { "osascript notification exited with #{status.exit_code}" }
      end
    rescue ex
      LOG.warn { "osascript notification failed: #{ex.message}" }
    end

    # Builds the AppleScript line; exposed for specs. Title and body are
    # escaped as AppleScript string literals.
    def self.notification_script(title : String, body : String) : String
      %(display notification #{applescript_string(body)} with title #{applescript_string(title)})
    end

    private def self.applescript_string(s : String) : String
      '"' + s.gsub('\\', "\\\\").gsub('"', "\\\"") + '"'
    end

    private def install_delegate(center : Void*) : Nil
      @@instance = self
      delegate_class = OBJC.new_class("PositronNotificationCenterDelegate")
      LIB_OBJC.class_addMethod(
        delegate_class, OBJC.sel(DID_RECEIVE_SELECTOR),
        @@did_receive_imp.not_nil!.pointer.as(Void*), "v@:@@@")
      LIB_OBJC.class_addMethod(
        delegate_class, OBJC.sel(WILL_PRESENT_SELECTOR),
        @@will_present_imp.not_nil!.pointer.as(Void*), "v@:@@@")
      OBJC.add_protocol(delegate_class, "UNUserNotificationCenterDelegate")
      @delegate_obj = OBJC.send0(delegate_class, OBJC.sel("new"))
      OBJC.send1(center, OBJC.sel("setDelegate:"), @delegate_obj.not_nil!)
    end

    private def auth_block : Void*
      @auth_block_obj ||= make_block(@@auth_imp.not_nil!.pointer)
    end

    private def settings_block : Void*
      @settings_block_obj ||= make_block(@@settings_imp.not_nil!.pointer)
    end

    private def added_block : Void*
      # addNotificationRequest's errorHandler takes an NSError* argument;
    # the extra register argument is ignored by the no-arg invoke.
      @added_block_obj ||= make_block(@@added_imp.not_nil!.pointer)
    end

    # Class used as isa for the hand-built global blocks. The block
    # runtime short-circuits on BLOCK_IS_GLOBAL in the flags before ever
    # comparing isa (`_Block_copy` / `_Block_release`), and objc
    # retain/release only need a valid class — so an NSBlock subclass is
    # all it takes. (_NSConcreteGlobalBlock itself is not resolvable via
    # dlsym on modern macOS and does not link from Crystal objects.)
    #
    # The block memory is Crystal-GC allocated and immortal by design,
    # so `dealloc` is a no-op: when a holder (e.g. an objc-set property)
    # drops its last reference, the runtime must not free() it.
    @@block_class : Void*?
    @@block_dealloc_imp : Proc(Void*, Void*, Nil)?

    private def block_class : Void*
      @@block_class ||= begin
        objc_class = OBJC.new_class("PositronGlobalBlock", "NSBlock")
        @@block_dealloc_imp = ->(_objc_self : Void*, _cmd : Void*) { }
        LIB_OBJC.class_addMethod(
          objc_class, OBJC.sel("dealloc"),
          @@block_dealloc_imp.not_nil!.pointer.as(Void*), "v@:")
        objc_class
      end
    end

    private def make_block(invoke : Void*) : Void*
      descriptor = Pointer(LibBlock::Descriptor).malloc(1)
      descriptor.value.unused = 0
      descriptor.value.size = sizeof(LibBlock::Layout)
      descriptor.value.copy_helper = Pointer(Void).null
      descriptor.value.dispose_helper = Pointer(Void).null

      block = Pointer(LibBlock::Layout).malloc(1)
      block.value.isa = block_class
      block.value.flags = BLOCK_IS_GLOBAL
      block.value.unused = 0
      block.value.invoke = invoke
      block.value.descriptor = descriptor.as(Void*)
      block.as(Void*)
    end

    protected def call_void_block(block : Void*) : Nil
      return if block.null?
      fn = Proc(Void*, Nil).new(block.as(LibBlock::Layout*).value.invoke, Pointer(Void).null)
      fn.call(block)
    end

    protected def call_options_block(block : Void*, options : Int64) : Nil
      return if block.null?
      fn = Proc(Void*, Int64, Nil).new(block.as(LibBlock::Layout*).value.invoke, Pointer(Void).null)
      fn.call(block, options)
    end

    # Blocks the calling fiber (the main thread) in short sleeps while
    # the UN completion block — which runs on a background queue — sets
    # the awaited flag. `break` inside the block stops early. The
    # generous default: the OS shows the permission prompt as a banner
    # the user may take a while to click.
    private def spin(timeout_seconds : Int32 = 60) : Nil
      ts = LibC::Timespec.new(tv_sec: 0, tv_nsec: 20_000_000)
      deadline = Time.instant + timeout_seconds.seconds
      while Time.instant < deadline
        yield
        LibC.nanosleep(pointerof(ts), Pointer(LibC::Timespec).null)
      end
    end
  end
end
