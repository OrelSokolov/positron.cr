require "log"
require "base64"
require "json"
require "./adapter"
require "../../adapters/windows/win32"

module Positron::Plugins
  # Windows implementation of the Clipboard plugin using the Win32 clipboard.
  #
  # Text uses CF_UNICODETEXT, files use CF_HDROP, images are exposed as BMP
  # (CF_DIB wrapped into a BITMAPFILEHEADER — no encoder needed) and written
  # from PNG/other decodable formats via GDI+.
  class WindowsClipboardAdapter < ClipboardAdapter
    include ::Positron::Adapters::Windows # Win32 FFI bindings
    Log = ::Log.for("positron.plugins.clipboard")

    def read_text : String?
      with_clipboard do
        handle = Win32::LibUser32.GetClipboardData(Win32::CF_UNICODETEXT)
        next nil if handle.null?
        ptr = Win32::LibKernel32.GlobalLock(handle).as(UInt16*)
        next nil if ptr.null?
        text = Win32.wstr_back(ptr)
        Win32::LibKernel32.GlobalUnlock(handle)
        text
      end
    end

    def read_image : {mime: String, data: Bytes}?
      with_clipboard do
        handle = Win32::LibUser32.GetClipboardData(Win32::CF_DIB)
        next nil if handle.null?
        locked = Win32::LibKernel32.GlobalLock(handle).as(UInt8*)
        next nil if locked.null?
        size = Win32::LibKernel32.GlobalSize(handle).to_i32
        bmp = dib_to_bmp(Slice.new(locked, size))
        Win32::LibKernel32.GlobalUnlock(handle)
        bmp.try { |bytes| {mime: "image/bmp", data: bytes} }
      end
    end

    def read_files : Array(String)
      with_clipboard do
        handle = Win32::LibUser32.GetClipboardData(Win32::CF_HDROP)
        next [] of String if handle.null?

        count = Win32::LibShell32.DragQueryFileW(handle, 0xFFFFFFFF_u32, Pointer(UInt16).null, 0)
        files = [] of String
        count.times do |i|
          len = Win32::LibShell32.DragQueryFileW(handle, i.to_u32!, Pointer(UInt16).null, 0)
          buf = Slice(UInt16).new(len.to_i32 + 1)
          Win32::LibShell32.DragQueryFileW(handle, i.to_u32!, buf.to_unsafe, buf.size.to_u32!)
          files << Win32.wstr_back(buf.to_unsafe)
        end
        files
      end || [] of String
    end

    def has_text? : Bool
      Win32::LibUser32.IsClipboardFormatAvailable(Win32::CF_UNICODETEXT) != 0
    end

    def has_image? : Bool
      Win32::LibUser32.IsClipboardFormatAvailable(Win32::CF_DIB) != 0
    end

    def has_files? : Bool
      Win32::LibUser32.IsClipboardFormatAvailable(Win32::CF_HDROP) != 0
    end

    def write_text(text : String) : Bool
      with_clipboard do
        Win32::LibUser32.EmptyClipboard
        units = Win32.wstr(text)
        handle = Win32::LibKernel32.GlobalAlloc(Win32::GMEM_MOVEABLE, units.bytesize.to_u64)
        next false if handle.null?
        dest = Win32::LibKernel32.GlobalLock(handle).as(UInt16*)
        if dest.null?
          next false
        else
          units.copy_to(Slice.new(dest, units.size))
          Win32::LibKernel32.GlobalUnlock(handle)
          Win32::LibUser32.SetClipboardData(Win32::CF_UNICODETEXT, handle)
          true
        end
      end || false
    end

    def write_image(base64 : String, mime : String) : Bool
      bytes = Base64.decode(base64)
      path = File.join(Dir.tempdir, "positron_clip_#{Process.pid}_#{Time.utc.to_unix_ms}.img")
      File.write(path, bytes)

      Win32.gdiplus_start
      return false unless Win32.gdiplus_started?

      filename = Win32.wstr(path)
      bitmap = Pointer(Void).null
      if Win32::LibGdiplus.GdipCreateBitmapFromFile(filename.to_unsafe, pointerof(bitmap)) != 0
        File.delete(path) rescue nil
        return false
      end

      hbm = Pointer(Void).null
      status = Win32::LibGdiplus.GdipCreateHBITMAPFromBitmap(bitmap, pointerof(hbm), 0_u32)
      Win32::LibGdiplus.GdipDisposeImage(bitmap)
      File.delete(path) rescue nil
      return false if status != 0

      put_dib_from_hbitmap(hbm)
    rescue ex
      Log.warn { "write_image failed: #{ex.message}" }
      false
    end

    # --- internals ---

    # Open/empty/close the clipboard around a block; `next` inside returns
    # from the block. Returns nil/false when the clipboard is unavailable
    # (another window may hold it — retry a few times, as is customary).
    private def with_clipboard(&block)
      opened = false
      10.times do
        if Win32::LibUser32.OpenClipboard(Pointer(Void).null) != 0
          opened = true
          break
        end
        sleep 10.milliseconds
      end

      unless opened
        Log.warn { "OpenClipboard failed (busy)" }
        return nil
      end

      begin
        yield
      ensure
        Win32::LibUser32.CloseClipboard
      end
    end

    # Wrap a raw CF_DIB (BITMAPINFO + pixels) into a .bmp file image.
    private def dib_to_bmp(dib : Slice(UInt8)) : Bytes?
      return nil if dib.size < 40
      header = dib.to_unsafe.as(Win32::LibGdi::BitMapInfoHeader*)

      bi_size = header.value.bi_size
      return nil unless bi_size >= 40 && bi_size <= dib.size
      palette_entries =
        if header.value.bi_clr_used > 0
          header.value.bi_clr_used
        elsif header.value.bi_bit_count <= 8
          1_u32 << header.value.bi_bit_count
        else
          0_u32
        end
      offset = 14 + bi_size + palette_entries * 4

      out = Bytes.new(14 + dib.size - bi_size + bi_size) # 14 + full dib
      # BITMAPFILEHEADER: "BM", size, reserved, offset.
      out[0] = 0x42_u8 # B
      out[1] = 0x4D_u8 # M
      total = 14 + dib.size
      out[4, 4].copy_from(pointerof(total).as(UInt8*), 4)
      out[10, 4].copy_from(pointerof(offset).as(UInt8*), 4)
      out[14, dib.size].copy_from(dib)
      out
    end

    # Convert an HBITMAP into CF_DIB via GetDIBits and put it on the
    # clipboard. Ownership of the HGLOBAL transfers to the clipboard.
    private def put_dib_from_hbitmap(hbm : Void*) : Bool
      dc = Win32::LibUser32.GetDC(Pointer(Void).null)

      info = Pointer(UInt8).malloc(40 + 1024) # BITMAPINFOHEADER + palette room
      header = info.as(Win32::LibGdi::BitMapInfoHeader*)
      header.value.bi_size = 40

      # Query the bitmap dimensions first (null bits pointer).
      if Win32::LibGdi.GetDIBits(dc, hbm, 0, 0, Pointer(UInt8).null, info, 0) == 0
        Win32::LibUser32.ReleaseDC(Pointer(Void).null, dc)
        Win32::LibGdi.DeleteObject(hbm)
        return false
      end

      height = header.value.bi_height.abs
      stride = (header.value.bi_width * header.value.bi_bit_count + 31) // 32 * 4
      bits_size = stride * height

      handle = Win32::LibKernel32.GlobalAlloc(Win32::GMEM_MOVEABLE, (40 + bits_size).to_u64)
      if handle.null?
        Win32::LibUser32.ReleaseDC(Pointer(Void).null, dc)
        Win32::LibGdi.DeleteObject(hbm)
        return false
      end

      locked = Win32::LibKernel32.GlobalLock(handle).as(UInt8*)
      locked.copy_from(info, 40)
      ok = Win32::LibGdi.GetDIBits(dc, hbm, 0, height, locked + 40, info, 0) != 0
      Win32::LibKernel32.GlobalUnlock(handle)
      Win32::LibUser32.ReleaseDC(Pointer(Void).null, dc)
      Win32::LibGdi.DeleteObject(hbm)

      return false unless ok

      with_clipboard do
        Win32::LibUser32.EmptyClipboard
        next false if Win32::LibUser32.SetClipboardData(Win32::CF_DIB, handle).null?
        true
      end == true
    end
  end
end
