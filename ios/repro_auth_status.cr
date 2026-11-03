# Variant matrix for the +[AVCaptureDevice
# authorizationStatusForMediaType:] segfault reproducer (see
# `ios/repro_auth_status.sh` for the build/run recipe).
#
# One variant per process run (a crashing variant kills the process):
#   VARIANT=1  fixed 6-arg objc_msgSend (the positron path — baseline)
#   VARIANT=2  exact-arity is NOT expressible here — one `fun` per C
#              symbol program-wide (see adapters/ios/objc.cr), so this
#              repeats the baseline
#   VARIANT=3  NSInvocation: methodSignatureForSelector: + invoke
#   VARIANT=4  fixed 6-arg msgSend with a long (non-tagged) NSString arg
#   VARIANT=5  method_invoke (class_getClassMethod + method_invoke)
#   VARIANT=6  newer selector spelling (authorizationStatusForAVMediaType:)
#   VARIANT=7  classification probe: systemPreferredCamera (non-TCC)
# Every run also plants a heap canary before the call and verifies it
# after, to detect heap corruption. Log: /private/tmp/repro_auth.log.
#
# Findings (iOS 26.5 sim, patched-Crystal toolchain, 2026-11):
#   * variants 1,3,4,5,6 (every path that EXECUTES the TCC
#     authorization IMP) fault; variant 7 (non-TCC class method)
#     returns cleanly with the canary intact;
#   * the fault reproduces with and without libSimCamInject, before
#     UIApplicationMain and inside a running app, from the main fiber
#     and from spawned fibers;
#   * every post-mortem print is itself broken in this stdlib build:
#     unhandled-exception printing faults at `self.class` (jump table
#     with a garbage type id — deterministic 0xf3900d29), so none of
#     these crashes produce a readable backtrace;
#   * the same API works in the clang-built egui.cr binary.
# Conclusion: only the TCC-path methods are unusable from a
# pure-Crystal-ObjC binary on this toolchain; the plugin skips the
# optional pre-check (iOS raises the TCC prompt at device-input
# creation anyway) — see the NOTE in plugins/camera/ios.cr.

@[Link("objc")]
lib LibObjC
  fun objc_getClass(name : UInt8*) : Void*
  fun sel_registerName(str : UInt8*) : Void*
  fun class_getClassMethod(cls : Void*, name : Void*) : Void*
  fun object_getClass(obj : Void*) : Void*
end

@[Link("objc")]
lib LibMsg
  fun msg6 = objc_msgSend(recv : Void*, cmd : Void*, a1 : Void*, a2 : Void*, a3 : Void*, a4 : Void*) : Void*
end

# `method_invoke` trampoline: same ABI as the method it invokes.
@[Link("objc")]
lib LibInvoke
  fun method_invoke_class = method_invoke(receiver : Void*, method : Void*, a2 : Void*, a3 : Void*, a4 : Void*) : Void*
end

def rlog(msg : String) : Nil
  File.open("/private/tmp/repro_auth.log", "a") { |f| f.puts msg }
end

def rcls(name : String) : Void*
  LibObjC.objc_getClass(name)
end

def rsel(name : String) : Void*
  LibObjC.sel_registerName(name)
end

def rnsstr(s : String) : Void*
  LibMsg.msg6(rcls("NSString"), rsel("stringWithUTF8String:"),
    s.to_unsafe.as(Void*), Pointer(Void).null, Pointer(Void).null, Pointer(Void).null)
end

def canary_ok?(canary : Array(Int32)) : Bool
  canary.each_with_index { |v, i| return false if v != i + 1 }
  true
end

variant = ENV["VARIANT"]? || "1"
rlog "=== variant #{variant} (pid #{Process.pid}) ==="

cls = rcls("AVCaptureDevice")
sel = rsel("authorizationStatusForMediaType:")
canary = Array.new(1024) { |i| i + 1 }
rlog "setup ok, calling"

case variant
when "1"
  str = rnsstr("video")
  ret = LibMsg.msg6(cls, sel, str, Pointer(Void).null, Pointer(Void).null, Pointer(Void).null)
  rlog "ret=#{ret.address}"
when "2"
  # exact-arity direct call is not expressible here (one declaration
  # per C symbol program-wide) — reuse baseline with a fresh string
  str = rnsstr("video")
  ret = LibMsg.msg6(cls, sel, str, Pointer(Void).null, Pointer(Void).null, Pointer(Void).null)
  rlog "ret=#{ret.address}"
when "3"
  sig = LibMsg.msg6(cls, rsel("methodSignatureForSelector:"), sel, Pointer(Void).null, Pointer(Void).null, Pointer(Void).null)
  rlog "sig=#{sig.address}"
  inv = LibMsg.msg6(rcls("NSInvocation"), rsel("invocationWithMethodSignature:"), sig, Pointer(Void).null, Pointer(Void).null, Pointer(Void).null)
  LibMsg.msg6(inv, rsel("setTarget:"), cls, Pointer(Void).null, Pointer(Void).null, Pointer(Void).null)
  LibMsg.msg6(inv, rsel("setSelector:"), sel, Pointer(Void).null, Pointer(Void).null, Pointer(Void).null)
  LibMsg.msg6(inv, rsel("invoke"), Pointer(Void).null, Pointer(Void).null, Pointer(Void).null, Pointer(Void).null)
  buf = Pointer(Int64).malloc(1)
  LibMsg.msg6(inv, rsel("getReturnValue:"), buf.as(Void*), Pointer(Void).null, Pointer(Void).null, Pointer(Void).null)
  rlog "invocation ret=#{buf.value}"
when "4"
  str = rnsstr("video_long_string_that_is_definitely_not_tagged_0123456789")
  ret = LibMsg.msg6(cls, sel, str, Pointer(Void).null, Pointer(Void).null, Pointer(Void).null)
  rlog "ret=#{ret.address}"
when "6"
  # newer spelling of the API (AVMediaType-typed)
  sel6 = rsel("authorizationStatusForAVMediaType:")
  ret = LibMsg.msg6(cls, sel6, rnsstr("video"), Pointer(Void).null, Pointer(Void).null, Pointer(Void).null)
  rlog "ret=#{ret.address}"
when "7"
  # non-TCC class method returning an object — classification probe
  ret = LibMsg.msg6(cls, rsel("systemPreferredCamera"), Pointer(Void).null, Pointer(Void).null, Pointer(Void).null, Pointer(Void).null)
  rlog "systemPreferredCamera=#{ret.address}"
when "5"
  m = LibObjC.class_getClassMethod(cls, sel)
  rlog "method=#{m.address}"
  ret = LibInvoke.method_invoke_class(cls, m, rnsstr("video"), Pointer(Void).null, Pointer(Void).null)
  rlog "method_invoke ret=#{ret.address}"
end

rlog "call survived, canary ok=#{canary_ok?(canary)}"
rlog "=== variant #{variant} DONE ==="
