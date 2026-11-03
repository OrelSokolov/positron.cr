require "log"
require "../../adapters/ios/objc"
require "./adapter"

module Positron::Plugins
  # CoreMedia / CoreVideo / libdispatch C entry points used by the
  # adapter below (new symbols — no clash with the one-fun-per-C-symbol
  # rule). Everything Objective-C still goes through `Adapters::IOS::ObjC`.
  @[Link(framework: "CoreMedia")]
  lib LibCoreMedia
    fun CMSampleBufferGetImageBuffer(sample_buffer : Void*) : Void*
  end

  @[Link(framework: "CoreVideo")]
  lib LibCoreVideo
    fun CVPixelBufferRetain(pixel_buffer : Void*) : Void*
    fun CVPixelBufferRelease(pixel_buffer : Void*) : Int32
    fun CVPixelBufferGetWidth(pixel_buffer : Void*) : UInt64
    fun CVPixelBufferGetHeight(pixel_buffer : Void*) : UInt64
    fun CVPixelBufferGetBytesPerRow(pixel_buffer : Void*) : UInt64
    fun CVPixelBufferGetBaseAddress(pixel_buffer : Void*) : Void*
    fun CVPixelBufferLockBaseAddress(pixel_buffer : Void*, lock_flags : UInt64) : Int32
    fun CVPixelBufferUnlockBaseAddress(pixel_buffer : Void*, unlock_flags : UInt64) : Int32
  end

  # dispatch_* lives in libSystem on darwin targets (no extra @[Link]).
  lib LibDispatch
    fun dispatch_queue_create(label : UInt8*, attr : Void*) : Void*
  end

  # iOS camera adapter: in-process AVFoundation capture driven through
  # the pure-Crystal ObjC runtime layer (`Adapters::IOS::ObjC`) — the
  # same WebKit-wiring rules apply here (no hand-rolled objc_msgSend).
  #
  # Why in-process: WKWebView runs `getUserMedia` capture in the
  # WebContent/GPU XPC processes, so a `DYLD_INSERT_LIBRARIES` virtual
  # camera (e.g. SimulatorCamera) never reaches it. Native capture in
  # the app process sees the injected device on the simulator (and the
  # real camera on hardware).
  #
  # Frame flow is PULL-based: the sample-buffer delegate only parks the
  # newest CVPixelBuffer in an atomic slot; `latest_frame` (called on
  # the host/GUI thread from the app's URI-scheme handler) converts
  # BGRA→RGBA and hands the bytes to the frontend.
  class IOSCameraAdapter < CameraAdapter
    @session : Pointer(Void) = Pointer(Void).null
    @output : Pointer(Void) = Pointer(Void).null
    @delegate : Pointer(Void) = Pointer(Void).null
    @queue : Pointer(Void) = Pointer(Void).null

    def initialize
    end

    def supported? : Bool
      true
    end

    def devices : Array({id: String, label: String})
      list = [] of {id: String, label: String}
      each_device { |d| list << device_entry(d) }
      if list.empty?
        # Simulator quirk (Xcode 26+): the injected virtual camera
        # answers `defaultDeviceWithMediaType:` but leaves discovery
        # sessions empty — fall back so the picker still shows it.
        if d = default_device
          list << device_entry(d)
        end
      end
      list
    end

    def start(device_id : String?, width : Int32, height : Int32) : String?
      stop
      # NOTE: +[AVCaptureDevice authorizationStatusForMediaType:] (and
      # the newer authorizationStatusForAVMediaType: spelling) segfault
      # when executed from a pure-Crystal-ObjC binary on this toolchain
      # — every calling convention dies inside the TCC authorization
      # IMP, while non-TCC class methods of the same class
      # (defaultDeviceWithMediaType:, systemPreferredCamera, …) answer
      # cleanly. Fully reproduced and classified in
      # ios/repro_auth_status.{cr,sh}. The pre-check is optional — iOS
      # raises the TCC prompt by itself when the device input is
      # created — so it is skipped.

      dev = Pointer(Void).null
      if device_id && !device_id.empty?
        dev = Adapters::IOS::ObjC.send1(Adapters::IOS::ObjC.cls("AVCaptureDevice"), Adapters::IOS::ObjC.sel("deviceWithUniqueID:"), Adapters::IOS::ObjC.nsstr(device_id))
      end
      dev = discover_first if dev.null?
      dev = default_device if dev.null?
      return "no camera device" if dev.null?

      err_buf = Pointer(Pointer(Void)).malloc(1)
      err_buf.value = Pointer(Void).null
      input = Adapters::IOS::ObjC.send2(Adapters::IOS::ObjC.cls("AVCaptureDeviceInput"), Adapters::IOS::ObjC.sel("deviceInputWithDevice:error:"), dev, err_buf.as(Void*))
      if input.null?
        err = err_buf.value
        detail = err.null? ? "?" : (Adapters::IOS::ObjC.to_s(Adapters::IOS::ObjC.send0(err, Adapters::IOS::ObjC.sel("localizedDescription"))) || "?")
        return "device input: #{detail}"
      end

      session = Adapters::IOS::ObjC.send0(Adapters::IOS::ObjC.cls("AVCaptureSession"), Adapters::IOS::ObjC.sel("new"))
      preset = preset_for(width, height)
      if Adapters::IOS::ObjC.send1_b(session, Adapters::IOS::ObjC.sel("canSetSessionPreset:"), Adapters::IOS::ObjC.nsstr(preset))
        Adapters::IOS::ObjC.send1(session, Adapters::IOS::ObjC.sel("setSessionPreset:"), Adapters::IOS::ObjC.nsstr(preset))
      end
      Adapters::IOS::ObjC.send1(session, Adapters::IOS::ObjC.sel("addInput:"), input)

      output = Adapters::IOS::ObjC.send0(Adapters::IOS::ObjC.cls("AVCaptureVideoDataOutput"), Adapters::IOS::ObjC.sel("new"))
      # videoSettings = @{kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA}
      # — the constant's string value is @"PixelFormatType", the pixel
      # format is 'BGRA' = 0x42475241.
      dict = Adapters::IOS::ObjC.send0(Adapters::IOS::ObjC.cls("NSMutableDictionary"), Adapters::IOS::ObjC.sel("dictionary"))
      number = Adapters::IOS::ObjC.send1(Adapters::IOS::ObjC.cls("NSNumber"), Adapters::IOS::ObjC.sel("numberWithInt:"), Adapters::IOS::ObjC.int_arg(0x42475241))
      Adapters::IOS::ObjC.send2(dict, Adapters::IOS::ObjC.sel("setObject:forKey:"), number, Adapters::IOS::ObjC.nsstr("PixelFormatType"))
      Adapters::IOS::ObjC.send1(output, Adapters::IOS::ObjC.sel("setVideoSettings:"), dict)
      Adapters::IOS::ObjC.send1(output, Adapters::IOS::ObjC.sel("setAlwaysDiscardsLateVideoFrames:"), Adapters::IOS::ObjC.bool_arg(true))
      Adapters::IOS::ObjC.send1(session, Adapters::IOS::ObjC.sel("addOutput:"), output)

      delegate = build_capture_delegate
      queue = LibDispatch.dispatch_queue_create("positron.camera", Pointer(Void).null)
      Adapters::IOS::ObjC.send2(output, Adapters::IOS::ObjC.sel("setSampleBufferDelegate:queue:"), delegate, queue)
      Log.info { "camera: session configured, starting" }
      # startRunning blocks for the HW spin-up (~1s in the simulator);
      # acceptable once per start from the command fiber.
      Adapters::IOS::ObjC.send0(session, Adapters::IOS::ObjC.sel("startRunning"))
      Log.info { "camera: session running" }

      @session, @output, @delegate, @queue = session, output, delegate, queue
      nil
    end

    def stop : Nil
      unless @session.null?
        Adapters::IOS::ObjC.send0(@session, Adapters::IOS::ObjC.sel("stopRunning"))
        Adapters::IOS::ObjC.send2(@output, Adapters::IOS::ObjC.sel("setSampleBufferDelegate:queue:"),
          Pointer(Void).null, Pointer(Void).null)
      end
      @session = @output = Pointer(Void).null
      if pb = @@slot.swap(Pointer(Void).null)
        LibCoreVideo.CVPixelBufferRelease(pb)
      end
    end

    def latest_frame : {width: Int32, height: Int32, bytes: Bytes}?
      pb = @@slot.swap(Pointer(Void).null)
      return nil if pb.null?

      begin
        width = LibCoreVideo.CVPixelBufferGetWidth(pb).to_i32
        height = LibCoreVideo.CVPixelBufferGetHeight(pb).to_i32
        return nil if width <= 0 || height <= 0

        bytes_per_row = LibCoreVideo.CVPixelBufferGetBytesPerRow(pb)
        LibCoreVideo.CVPixelBufferLockBaseAddress(pb, 1) # kCVPixelBufferLock_ReadOnly
        base = LibCoreVideo.CVPixelBufferGetBaseAddress(pb).as(UInt8*)
        bytes = Bytes.new(width.to_i64 * height * 4)

        height.times do |y|
          in_row = base + y.to_i64 * bytes_per_row
          out_row = y.to_i64 * width * 4
          width.times do |x|
            i4 = x * 4
            o = out_row + i4
            bytes[o] = in_row[i4 + 2]     # R <- B slot (BGRA → RGBA)
            bytes[o + 1] = in_row[i4 + 1] # G
            bytes[o + 2] = in_row[i4]     # B
            bytes[o + 3] = 255
          end
        end

        {width: width, height: height, bytes: bytes}
      ensure
        LibCoreVideo.CVPixelBufferUnlockBaseAddress(pb, 1)
        LibCoreVideo.CVPixelBufferRelease(pb)
      end
    end

    # --- Internals ---

    # The latest retained CVPixelBufferRef, shared between the capture
    # queue and the GUI thread. Pointer-sized atomic swap only — no
    # lock, no allocation.
    @@slot = Atomic(Pointer(Void)).new(Pointer(Void).null)

    # Sample-buffer delegate IMP. Runs on the capture queue's OWN thread
    # — a foreign thread for the Crystal runtime: only pointer-sized
    # operations here, no allocation, no fibers, no GC-managed objects,
    # or Boehm GC crashes.
    @@capture_imp : Proc(Void*, Void*, Void*, Void*, Void*, Nil) = ->(_self : Void*, _cmd : Void*, _output : Void*, sample_buffer : Void*, _connection : Void*) {
      pb = LibCoreMedia.CMSampleBufferGetImageBuffer(sample_buffer)
      unless pb.null?
        LibCoreVideo.CVPixelBufferRetain(pb)
        if old = @@slot.swap(pb)
          LibCoreVideo.CVPixelBufferRelease(old)
        end
      end
    }

    private def build_capture_delegate : Pointer(Void)
      objc_class = Adapters::IOS::ObjC.new_class("PositronAVCaptureDelegate")
      Adapters::IOS::ObjC.add_protocol(objc_class, "AVCaptureVideoDataOutputSampleBufferDelegate")
      Adapters::IOS::LibObjC.class_addMethod(
        objc_class,
        Adapters::IOS::ObjC.sel("captureOutput:didOutputSampleBuffer:fromConnection:"),
        @@capture_imp.not_nil!.pointer.as(Void*),
        "v@:@@@")
      Adapters::IOS::ObjC.send0(objc_class, Adapters::IOS::ObjC.sel("new"))
    end

    private def each_device(& : Pointer(Void) -> Nil) : Nil
      types = Adapters::IOS::ObjC.send0(Adapters::IOS::ObjC.cls("NSMutableArray"), Adapters::IOS::ObjC.sel("array"))
      Adapters::IOS::ObjC.send1(types, Adapters::IOS::ObjC.sel("addObject:"), Adapters::IOS::ObjC.nsstr("AVCaptureDeviceTypeBuiltInWideAngleCamera"))
      Adapters::IOS::ObjC.send1(types, Adapters::IOS::ObjC.sel("addObject:"), Adapters::IOS::ObjC.nsstr("AVCaptureDeviceTypeExternal"))
      session = Adapters::IOS::ObjC.send3(Adapters::IOS::ObjC.cls("AVCaptureDeviceDiscoverySession"),
        Adapters::IOS::ObjC.sel("discoverySessionWithDeviceTypes:mediaType:position:"),
        types, Adapters::IOS::ObjC.nsstr("video"), Adapters::IOS::ObjC.int_arg(0)) # position: unspecified
      devices = Adapters::IOS::ObjC.send0(session, Adapters::IOS::ObjC.sel("devices"))
      count = Adapters::IOS::ObjC.send0_i(devices, Adapters::IOS::ObjC.sel("count"))
      count.times do |i|
        yield Adapters::IOS::ObjC.send1(devices, Adapters::IOS::ObjC.sel("objectAtIndex:"), Adapters::IOS::ObjC.int_arg(i))
      end
    end

    private def discover_first : Pointer(Void)
      found = Pointer(Void).null
      each_device do |d|
        found = d if found.null?
      end
      found
    end

    private def default_device : Pointer(Void)
      if cls = Adapters::IOS::ObjC.cls?("AVCaptureDevice")
        Adapters::IOS::ObjC.send1(cls, Adapters::IOS::ObjC.sel("defaultDeviceWithMediaType:"), Adapters::IOS::ObjC.nsstr("video"))
      else
        Pointer(Void).null
      end
    end

    private def device_entry(dev : Pointer(Void)) : {id: String, label: String}
      {
        id:    Adapters::IOS::ObjC.to_s(Adapters::IOS::ObjC.send0(dev, Adapters::IOS::ObjC.sel("uniqueID"))) || "",
        label: Adapters::IOS::ObjC.to_s(Adapters::IOS::ObjC.send0(dev, Adapters::IOS::ObjC.sel("localizedName"))) || "Camera",
      }
    end

    private def preset_for(width : Int32, height : Int32) : String
      if width <= 640 || height <= 480
        "AVCaptureSessionPreset640x480"
      elsif width <= 1280 || height <= 720
        "AVCaptureSessionPreset1280x720"
      else
        "AVCaptureSessionPresetHigh"
      end
    end
  end
end
