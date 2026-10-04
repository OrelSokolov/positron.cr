module Positron
  module Adapters
    module Windows
      # Shared Win32 FFI bindings for the Windows adapters (webview window,
      # tray, icons, timers). Only system DLLs are referenced; the WebView
      # itself is loaded through `lib_webview.cr`.
      module Win32
        # Window messages used by the adapters.
        WM_NULL               = 0x0000
        WM_DESTROY            = 0x0002
        WM_SIZE               = 0x0005
        WM_MOVE               = 0x0003
        WM_CLOSE              = 0x0010
        WM_SETICON            = 0x0080
        WM_COMMAND            = 0x0111
        WM_TIMER              = 0x0113
        WM_WINDOWPOSCHANGED   = 0x0047
        WM_CONTEXTMENU        = 0x007B
        WM_APP                = 0x8000

        # Mouse messages delivered through the tray callback message.
        WM_LBUTTONUP  = 0x0202
        WM_RBUTTONUP  = 0x0205

        # ShowWindow commands.
        SW_HIDE      = 0
        SW_MAXIMIZE  = 3
        SW_SHOW      = 5
        SW_RESTORE   = 9

        # GetWindowLongPtr indexes and window styles.
        GWL_STYLE     = -16
        GWLP_WNDPROC  = -4
        WS_POPUP      = 0x80000000_u32
        WS_CAPTION    = 0x00C00000_u32
        WS_THICKFRAME = 0x00040000_u32
        WS_VISIBLE    = 0x10000000_u32

        # SetWindowPos flags.
        SWP_NOSIZE       = 0x0001_u32
        SWP_NOMOVE       = 0x0002_u32
        SWP_NOZORDER     = 0x0004_u32
        SWP_NOACTIVATE   = 0x0010_u32
        SWP_FRAMECHANGED = 0x0020_u32
        HWND_TOPMOST     = Pointer(Void).new(0xFFFF_FFFF_FFFF_FFFF_u64)
        HWND_NOTOPMOST   = Pointer(Void).new(0xFFFF_FFFF_FFFF_FFFE_u64)
        HWND_MESSAGE     = Pointer(Void).new(0xFFFF_FFFF_FFFF_FFFD_u64)

        # Icons.
        ICON_SMALL = 0_i64
        ICON_BIG   = 1_i64
        IMAGE_ICON = 1_u32
        LR_LOADFROMFILE = 0x0010_u32
        LR_DEFAULTSIZE  = 0x0040_u32
        IDI_APPLICATION = Pointer(UInt16).new(32512_u64)
        IDC_ARROW       = Pointer(UInt16).new(32512_u64)

        # NotifyIcon.
        NIM_ADD     = 0_u32
        NIM_MODIFY  = 1_u32
        NIM_DELETE  = 2_u32
        NIM_GETVERSION = 3_u32
        NIM_SETVERSION = 4_u32
        NIF_MESSAGE = 0x01_u32
        NIF_ICON    = 0x02_u32
        NIF_TIP     = 0x04_u32
        NIF_INFO    = 0x10_u32
        NIF_STATE   = 0x08_u32
        NIF_SHOWTIP = 0x80_u32
        NIS_HIDDEN  = 0x01_u32

        # Popup menus.
        TPM_RIGHTBUTTON = 0x0002_u32
        TPM_RETURNCMD   = 0x0100_u32
        TPM_NONOTIFY    = 0x0080_u32
        TPM_RIGHTALIGN  = 0x0008_u32
        TPM_BOTTOMALIGN = 0x0020_u32
        MIIM_STATE      = 0x0001_u32
        MIIM_ID         = 0x0020_u32
        MIIM_STRING     = 0x0040_u32
        MIIM_FTYPE      = 0x0100_u32
        MFT_SEPARATOR   = 0x0800_u32
        MFS_DISABLED    = 0x0003_u32
        MFS_CHECKED     = 0x0008_u32

        # Monitors / metrics.
        MONITOR_DEFAULTTONEAREST = 2_u32

        # Clipboard formats.
        CF_DIB          = 8_u32
        CF_UNICODETEXT  = 13_u32
        CF_HDROP        = 15_u32
        GMEM_MOVEABLE   = 0x02_u32

        # MessageBox.
        MB_OK                 = 0x0000_u32
        MB_OKCANCEL           = 0x0001_u32
        MB_ICONERROR          = 0x0010_u32
        MB_ICONWARNING        = 0x0030_u32
        MB_ICONINFORMATION    = 0x0040_u32
        IDOK                  = 1
        IDCANCEL              = 2

        # Common dialog flags (comdlg32).
        OFN_PATHMUSTEXIST     = 0x0008_u32
        OFN_FILEMUSTEXIST     = 0x1000_u32
        OFN_OVERWRITEPROMPT   = 0x0002_u32
        OFN_HIDEREADONLY      = 0x0004_u32
        OFN_NOCHANGEDIR       = 0x0008_u32

        # Window messages used by dialogs/prompt.
        WM_SETTEXT     = 0x000C
        WM_GETTEXT     = 0x000D
        WM_GETTEXTLENGTH = 0x000E
        WM_SETFONT     = 0x0030
        WM_QUIT        = 0x0012
        WM_USER        = 0x0400

        # Tray balloon notifications (lParam of the callback message).
        NIN_BALLOONSHOW       = WM_USER + 2
        NIN_BALLOONHIDE       = WM_USER + 3
        NIN_BALLOONTIMEOUT    = WM_USER + 4
        NIN_BALLOONUSERCLICK  = WM_USER + 5
        NIIF_INFO             = 0x01_u32
        NIIF_RESPECT_QUIET    = 0x80_u32

        # Child control styles.
        WS_CHILD        = 0x40000000_u32
        WS_TABSTOP      = 0x00010000_u32
        WS_BORDER       = 0x00800000_u32
        WS_EX_CONTROLPARENT = 0x00010000_u32
        ES_AUTOHSCROLL  = 0x0080_u32
        BS_DEFPUSHBUTTON = 0x0001_u32
        DEFAULT_GUI_FONT = 17

        # System metrics (virtual desktop).
        SM_XVIRTUALSCREEN  = 76
        SM_YVIRTUALSCREEN  = 77
        SM_CXVIRTUALSCREEN = 78
        SM_CYVIRTUALSCREEN = 79

        # GetDeviceCaps indexes.
        HORZSIZE   = 4
        VERTSIZE   = 6
        LOGPIXELSX = 88

        ENUM_CURRENT_SETTINGS = 0xFFFFFFFF_u32

        # Encode a Crystal string as a NUL-terminated UTF-16 buffer for the
        # wide-char Win32 APIs. The caller must keep the returned slice alive
        # for the duration of the call.
        def self.wstr(s : String) : Slice(UInt16)
          buf = Slice(UInt16).new(s.bytesize + 1) # >= code units + NUL
          units = s.to_utf16
          buf[0, units.size].copy_from(units)
          buf[units.size] = 0
          buf[0, units.size + 1]
        end

        @[Link("kernel32")]
        lib LibKernel32
          fun LoadLibraryW(name : UInt16*) : Void*
          fun GetProcAddress(module : Void*, name : UInt8*) : Void*
          fun GetModuleHandleW(name : UInt16*) : Void*
          fun GetCurrentThreadId : UInt32
        end

        @[Link("user32")]
        lib LibUser32
          struct Point
            x : Int32
            y : Int32
          end

          struct Rect
            left : Int32
            top : Int32
            right : Int32
            bottom : Int32
          end

          struct MonitorInfo
            cb_size : UInt32
            rc_monitor : Rect
            rc_work : Rect
            dw_flags : UInt32
          end

          struct WndClassExW
            cb_size : UInt32
            style : UInt32
            lpfn_wnd_proc : Void*
            cb_cls_extra : Int32
            cb_wnd_extra : Int32
            h_instance : Void*
            h_icon : Void*
            h_cursor : Void*
            hbr_background : Void*
            lpsz_menu_name : UInt16*
            lpsz_class_name : UInt16*
            h_icon_sm : Void*
          end

          fun RegisterClassExW(wc : WndClassExW*) : UInt16
          fun CreateWindowExW(ex_style : UInt32, class_name : UInt16*, window_name : UInt16*,
                              style : UInt32, x : Int32, y : Int32, w : Int32, h : Int32,
                              parent : Void*, menu : Void*, instance : Void*, param : Void*) : Void*
          fun DefWindowProcW(hwnd : Void*, msg : UInt32, wparam : UInt64, lparam : Int64) : Int64
          fun CallWindowProcW(prev : Void*, hwnd : Void*, msg : UInt32, wparam : UInt64, lparam : Int64) : Int64
          fun SetWindowLongPtrW(hwnd : Void*, index : Int32, value : Int64) : Int64
          fun GetWindowLongPtrW(hwnd : Void*, index : Int32) : Int64
          fun ShowWindow(hwnd : Void*, cmd : Int32) : Int32
          fun SetWindowPos(hwnd : Void*, after : Void*, x : Int32, y : Int32, cx : Int32, cy : Int32, flags : UInt32) : Int32
          fun GetWindowRect(hwnd : Void*, rect : Rect*) : Int32
          fun GetClientRect(hwnd : Void*, rect : Rect*) : Int32
          fun IsZoomed(hwnd : Void*) : Int32
          fun SetForegroundWindow(hwnd : Void*) : Int32
          fun MonitorFromWindow(hwnd : Void*, flags : UInt32) : Void*
          fun GetMonitorInfoW(monitor : Void*, info : Void*) : Int32
          fun GetSystemMetrics(index : Int32) : Int32
          fun PostMessageW(hwnd : Void*, msg : UInt32, wparam : UInt64, lparam : Int64) : Int32
          fun SendMessageW(hwnd : Void*, msg : UInt32, wparam : UInt64, lparam : Int64) : Int64
          fun LoadImageW(instance : Void*, name : UInt16*, type : UInt32, cx : Int32, cy : Int32, load : UInt32) : Void*
          fun LoadIconW(instance : Void*, name : UInt16*) : Void*
          fun LoadCursorW(instance : Void*, name : UInt16*) : Void*
          fun SetTimer(hwnd : Void*, id : UInt64, elapsed : UInt32, proc : Void*) : UInt64
          fun KillTimer(hwnd : Void*, id : UInt64) : Int32
          fun CreatePopupMenu : Void*
          fun DestroyMenu(menu : Void*) : Int32
          fun InsertMenuItemW(menu : Void*, item : UInt32, by_position : Int32, info : MenuItemInfoW*) : Int32
          fun TrackPopupMenu(menu : Void*, flags : UInt32, x : Int32, y : Int32, reserved : Int32, hwnd : Void*, rect : Void*) : Int32
          fun GetCursorPos(point : Point*) : Int32
          fun DestroyWindow(hwnd : Void*) : Int32

          struct MenuItemInfoW
            cb_size : UInt32
            f_mask : UInt32
            f_type : UInt32
            f_state : UInt32
            w_id : UInt32
            h_submenu : Void*
            hbmp_checked : Void*
            hbmp_unchecked : Void*
            dw_item_data : UInt64
            dw_type_data : UInt16*
            cch : UInt32
            hbmp_item : Void*
          end
        end

        @[Link("shell32")]
        lib LibShell32
          struct NotifyIconDataW
            cb_size : UInt32
            hwnd : Void*
            u_id : UInt32
            u_flags : UInt32
            u_callback_message : UInt32
            h_icon : Void*
            sz_tip : UInt16[128]
            dw_state : UInt32
            dw_state_mask : UInt32
            sz_info : UInt16[256]
            u_timeout : UInt32
            sz_info_title : UInt16[64]
            dw_info_flags : UInt32
            guid_item : UInt8[16]
            h_balloon_icon : Void*
          end

          fun Shell_NotifyIconW(msg : UInt32, data : NotifyIconDataW*) : Int32
        end

        @[Link("gdiplus")]
        lib LibGdiplus
          struct StartupInput
            gdiplus_version : UInt32
            debug_event_callback : Void*
            suppress_background_thread : Bool
            suppress_external_codecs : Bool
          end

          fun GdiplusStartup(token : Void*, input : StartupInput*, output : Void*) : Int32
          fun GdiplusShutdown(token : Void*)
          fun GdipCreateBitmapFromFile(filename : UInt16*, bitmap : Void**) : Int32
          fun GdipCreateHICONFromBitmap(bitmap : Void*, hicon : Void**) : Int32
          fun GdipCreateHBITMAPFromBitmap(bitmap : Void*, hbm : Void**, background : UInt32) : Int32
          fun GdipDisposeImage(image : Void*) : Int32
        end

        @[Link("user32")]
        lib LibUser32
          fun OpenClipboard(hwnd : Void*) : Int32
          fun CloseClipboard : Int32
          fun EmptyClipboard : Int32
          fun GetClipboardData(format : UInt32) : Void*
          fun SetClipboardData(format : UInt32, data : Void*) : Void*
          fun IsClipboardFormatAvailable(format : UInt32) : Int32
          fun MessageBoxW(hwnd : Void*, text : UInt16*, caption : UInt16*, type : UInt32) : Int32
          fun GetMessageW(msg : Msg*, hwnd : Void*, min : UInt32, max : UInt32) : Int32
          fun PeekMessageW(msg : Msg*, hwnd : Void*, min : UInt32, max : UInt32, remove : UInt32) : Int32
          fun TranslateMessage(msg : Msg*) : Int32
          fun DispatchMessageW(msg : Msg*) : Int64
          fun PostQuitMessage(code : Int32)
          fun IsDialogMessageW(hwnd : Void*, msg : Msg*) : Int32
          fun EnumDisplayMonitors(hdc : Void*, clip : Void*, cb : Void*, data : Int64) : Int32
          fun EnumDisplaySettingsW(device : UInt16*, mode : UInt32, devmode : UInt8*) : Int32
          fun GetDC(hwnd : Void*) : Void*
          fun ReleaseDC(hwnd : Void*, dc : Void*) : Int32

          struct Msg
            hwnd : Void*
            message : UInt32
            w_param : UInt64
            l_param : Int64
            time : UInt32
            pt : Point
            l_private : UInt32
          end

          struct MonitorInfoExW
            cb_size : UInt32
            rc_monitor : Rect
            rc_work : Rect
            dw_flags : UInt32
            sz_device : UInt16[32]
          end
        end

        @[Link("gdi32")]
        lib LibGdi
          fun CreateDCW(driver : UInt16*, device : UInt16*, output : UInt16*, data : Void*) : Void*
          fun DeleteDC(dc : Void*) : Int32
          fun GetDeviceCaps(hdc : Void*, index : Int32) : Int32
          fun GetStockObject(index : Int32) : Void*
          fun GetDIBits(hdc : Void*, hbm : Void*, start : UInt32, lines : UInt32,
                        bits : UInt8*, info : Void*, usage : UInt32) : Int32
          fun DeleteObject(obj : Void*) : Int32

          struct BitMapInfoHeader
            bi_size : UInt32
            bi_width : Int32
            bi_height : Int32
            bi_planes : UInt16
            bi_bit_count : UInt16
            bi_compression : UInt32
            bi_size_image : UInt32
            bi_x_pels : Int32
            bi_y_pels : Int32
            bi_clr_used : UInt32
            bi_clr_important : UInt32
          end
        end

        @[Link("kernel32")]
        lib LibKernel32
          fun GlobalAlloc(flags : UInt32, bytes : UInt64) : Void*
          fun GlobalLock(mem : Void*) : Void*
          fun GlobalUnlock(mem : Void*) : Int32
          fun GlobalSize(mem : Void*) : UInt64
        end

        @[Link("shell32")]
        lib LibShell32
          fun Shell_NotifyIconW(msg : UInt32, data : NotifyIconDataW*) : Int32
          fun SetCurrentProcessExplicitAppUserModelID(app_id : UInt16*) : Int32
          fun DragQueryFileW(drop : Void*, index : UInt32, buf : UInt16*, len : UInt32) : UInt32
        end

        @[Link("comdlg32")]
        lib LibComDlg32
          struct OpenFileNameW
            l_struct_size : UInt32
            hwnd_owner : Void*
            h_instance : Void*
            lpstr_filter : UInt16*
            lpstr_custom_filter : UInt16*
            n_max_cust_filter : UInt32
            n_filter_index : UInt32
            lpstr_file : UInt16*
            n_max_file : UInt32
            lpstr_file_title : UInt16*
            n_max_file_title : UInt32
            lpstr_initial_dir : UInt16*
            lpstr_title : UInt16*
            flags : UInt32
            n_file_offset : UInt16
            n_file_extension : UInt16
            lpstr_def_ext : UInt16*
            l_cust_data : Int64
            lpfn_hook : Void*
            lp_template_name : UInt16*
            pv_reserved : Void*
            dw_reserved : UInt32
            flags_ex : UInt32
          end

          fun GetOpenFileNameW(ofn : OpenFileNameW*) : Int32
          fun GetSaveFileNameW(ofn : OpenFileNameW*) : Int32
        end

        @[Link("shcore")]
        lib LibShCore
          fun GetDpiForMonitor(monitor : Void*, type : Int32, dpi_x : UInt32*, dpi_y : UInt32*) : Int32
        end

        # Decode a NUL-terminated UTF-16 buffer into a Crystal string.
        def self.wstr_back(ptr : UInt16*, max_units : Int32 = 32768) : String
          len = 0
          while len < max_units && ptr[len] != 0
            len += 1
          end
          String.new(Slice.new(ptr.as(UInt8*), len * 2), "UTF-16LE")
        end

        # The GDI+ token; started lazily on first PNG decoding.
        @@gdiplus_token : UInt64 = 0

        def self.gdiplus_started? : Bool
          @@gdiplus_token != 0
        end

        def self.gdiplus_start : Nil
          return if gdiplus_started?
          input = LibGdiplus::StartupInput.new
          input.gdiplus_version = 1
          token = Pointer(UInt64).malloc(1)
          if LibGdiplus.GdiplusStartup(token, pointerof(input), Pointer(Void).null) == 0
            @@gdiplus_token = token.value
          end
        end

        def self.gdiplus_stop : Nil
          return unless gdiplus_started?
          LibGdiplus.GdiplusShutdown(pointerof(@@gdiplus_token).as(Void*))
          @@gdiplus_token = 0
        end

        # Decode a PNG file into an HICON (for tray icons); nil on failure.
        def self.hicon_from_png(path : String) : Void*
          gdiplus_start
          return Pointer(Void).null unless gdiplus_started?

          filename = wstr(path)
          bitmap = Pointer(Void).null
          return Pointer(Void).null if LibGdiplus.GdipCreateBitmapFromFile(filename.to_unsafe, pointerof(bitmap)) != 0
          hicon = Pointer(Void).null
          status = LibGdiplus.GdipCreateHICONFromBitmap(bitmap, pointerof(hicon))
          LibGdiplus.GdipDisposeImage(bitmap)
          status == 0 ? hicon : Pointer(Void).null
        end
      end
    end
  end
end
