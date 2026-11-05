require "log"
require "../adapters/android/shim"

# Android entry point: the C shim (`android/positron_shim.c`)
# pthread_creates this function after the Activity passed its WebView
# and bridge over. It boots the Crystal runtime on this fresh host
# thread, runs the program toplevel (which registers the application
# through `Positron::EntryAndroid.app`), then drives the mobile host
# and its pump until the Activity is destroyed.
#
# `Application#run` is intentionally not called: on mobile the native
# shim owns the lifecycle (see Application#run).
module Positron
  module EntryAndroid
    Log = ::Log.for("positron.entry.android")

    # The Application subclass to instantiate on the host thread,
    # registered from the program toplevel:
    #
    #   {% if flag?(:android) %}
    #     Positron::EntryAndroid.app(HelloApp)
    #   {% else %}
    #     HelloApp.new.run
    #   {% end %}
    #
    @@app_class : (Positron::Application.class)?

    def self.app(klass : Positron::Application.class) : Nil
      @@app_class = klass
    end

    def self.app_class : (Positron::Application.class)?
      @@app_class
    end
  end
end

fun positron_android_host_main(arg : Void*) : Void*
  # Boot Crystal on this thread (the pattern proven by the egui.cr
  # android port): the runtime, the fiber scheduler and the GC bind to
  # the thread every Crystal callback will run on. Steps report to
  # logcat (tag "positron") — stdout/stderr go to /dev/null on Android.
  boot_log = ->(msg : String) { Positron::Adapters::Android::LibShim.positron_shim_log(msg.to_unsafe) }

  boot_log.call("host: gc.init")
  GC.init

  # ndk_translation (arm64 app on an x86_64 emulator) hides guest
  # stack/register roots from Boehm — every collection would free live
  # objects. Disable automatic collection before anything allocates.
  translated = File.exists?("/system/lib64/libndk_translation.so") ||
               File.exists?("/system/lib/libndk_translation.so")
  GC.disable if translated
  boot_log.call("host: gc ready (translated=#{translated})")

  Crystal.init_runtime
  boot_log.call("host: runtime ready")

  # A valid argv is REQUIRED: PROGRAM_NAME/ARGV lazily dereference
  # __crystal_main's parameters; (0, null) segfaults on first use.
  # Call __crystal_main directly, NOT Crystal.main — the latter runs
  # at_exit handlers and exits, which would kill the Activity process
  # the moment the toplevel returns.
  prog = "positron"
  argv = Pointer(Pointer(UInt8)).malloc(1)
  argv[0] = prog.to_unsafe
  LibCrystalMain.__crystal_main(1, argv)
  boot_log.call("host: toplevel done")

  app_class = Positron::EntryAndroid.app_class
  unless app_class
    Positron::EntryAndroid::Log.error { "no app registered: call Positron::EntryAndroid.app(AppClass) at the program toplevel" }
    boot_log.call("host: ERROR no app registered")
    return Pointer(Void).null
  end

  begin
    app = app_class.new
    # Application#run does this on desktop before the host boots; on
    # Android the shim owns the lifecycle, so plugin registration must
    # happen here — Host#initialize binds plugins and the frontend
    # facade is generated from them.
    app.configure_plugins
    host = Positron::Adapters::Android::Host.new(app)
    boot_log.call("host: starting pump")
    host.run
    boot_log.call("host: pump stopped")
  rescue ex
    Positron::EntryAndroid::Log.error(exception: ex) { "android host crashed" }
    boot_log.call("host: CRASH #{ex.message}")
    ex.backtrace.try &.each { |line| boot_log.call(line) }
  end

  Pointer(Void).null
end
