require "log"
require "./win32"

module Positron
  module Adapters
    module Windows
      # Windows system tray adapter backed by Shell_NotifyIcon.
      #
      # A hidden message window receives the tray callbacks (WM_APP+1);
      # clicks open the menu built from the registered TrayItems via
      # TrackPopupMenu, following the pattern in getlantern/systray's
      # systray_windows.go (including the SetForegroundWindow/WM_NULL fix
      # from KB135788 so the menu closes when focus moves away).
      class NotifyIconTray < TrayPort
        TRAY_CALLBACK_MSG = Win32::WM_APP + 1
        TRAY_ICON_ID      = 1_u32
        CLASS_NAME        = "PositronTrayWindow"

        @@instance : NotifyIconTray?
        @@wndproc = ->(hwnd : Void*, msg : UInt32, wparam : UInt64, lparam : Int64) : Int64 do
          tray = @@instance
          return Win32::LibUser32.DefWindowProcW(hwnd, msg, wparam, lparam) unless tray

          case msg
          when TRAY_CALLBACK_MSG
            mouse = (lparam & 0xFFFF)
            if mouse == Win32::WM_LBUTTONUP || mouse == Win32::WM_RBUTTONUP
              tray.show_menu
            end
            0_i64
          when Win32::WM_DESTROY
            0_i64
          else
            Win32::LibUser32.DefWindowProcW(hwnd, msg, wparam, lparam)
          end
        end

        @window : Void* = Pointer(Void).null
        @items = {} of Int32 => TrayItem
        @hicon : Void* = Pointer(Void).null
        @added = false
        getter on_click : Proc(Int32, Nil) = ->(id : Int32) { }

        def initialize
        end

        def supported? : Bool
          true
        end

        def create(icon : IconSource? = nil, title : String? = nil)
          create_message_window
          @hicon = icon ? load_hicon(icon.not_nil!) : default_icon
          notify_add(title || "Positron")
          @@instance = self
        end

        def set_icon(icon : IconSource)
          hicon = load_hicon(icon)
          return if hicon.null?
          @hicon = hicon
          notify_modify_icon
        end

        # The Windows tray has no text label next to the icon.
        def set_title(title : String)
        end

        def set_tooltip(tooltip : String)
          notify_modify_tip(tooltip)
        end

        def add_or_update_item(item : TrayItem)
          @items[item.id] = item
        end

        def add_separator(id : Int32)
          @items[id] = TrayItem.new(id: id, title: "-")
        end

        def remove_item(id : Int32)
          @items.delete(id)
        end

        def show_item(id : Int32)
          @items[id].try { |item| item.hidden = false }
        end

        def hide_item(id : Int32)
          @items[id].try { |item| item.hidden = true }
        end

        def on_item_click(&block : Int32 ->)
          @on_click = block
        end

        def show
          set_icon_state(hidden: false)
        end

        def hide
          set_icon_state(hidden: true)
        end

        def quit
          if @added
            data = base_notify_data
            Win32::LibShell32.Shell_NotifyIconW(Win32::NIM_DELETE, pointerof(data))
            @added = false
          end
          unless @window.null?
            Win32::LibUser32.DestroyWindow(@window)
            @window = Pointer(Void).null
          end
        end

        # --- internals ---

        private def create_message_window : Nil
          instance = Win32::LibKernel32.GetModuleHandleW(Pointer(UInt16).null)
          class_name = Win32.wstr(CLASS_NAME)

          wc = Win32::LibUser32::WndClassExW.new
          wc.cb_size = sizeof(Win32::LibUser32::WndClassExW)
          wc.lpfn_wnd_proc = @@wndproc.pointer
          wc.h_instance = instance
          wc.h_icon = default_icon
          wc.h_cursor = Win32::LibUser32.LoadCursorW(Pointer(Void).null, Win32::IDC_ARROW)
          wc.lpsz_class_name = class_name.to_unsafe
          Win32::LibUser32.RegisterClassExW(pointerof(wc)) # failure = already registered

          @window = Win32::LibUser32.CreateWindowExW(
            0_u32, class_name.to_unsafe, class_name.to_unsafe,
            0_u32, 0, 0, 0, 0,
            Win32::HWND_MESSAGE, Pointer(Void).null, instance, Pointer(Void).null)
          if @window.null?
            Log.warn { "tray: failed to create message window" }
          end
        end

        protected def show_menu : Nil
          return if @window.null?

          menu = Win32::LibUser32.CreatePopupMenu
          begin
            position = 0_u32
            @items.each do |id, item|
              next if item.hidden
              if item.separator?
                info = menu_item(f_mask: Win32::MIIM_FTYPE | Win32::MIIM_ID, w_id: item.id)
                info.f_type = Win32::MFT_SEPARATOR
                Win32::LibUser32.InsertMenuItemW(menu, position, 1, pointerof(info))
              else
                text = Win32.wstr(item.title)
                info = menu_item(
                  f_mask: Win32::MIIM_STRING | Win32::MIIM_ID | Win32::MIIM_STATE,
                  w_id: item.id)
                info.dw_type_data = text.to_unsafe
                info.f_state |= Win32::MFS_CHECKED if item.checked
                info.f_state |= Win32::MFS_DISABLED if item.disabled
                Win32::LibUser32.InsertMenuItemW(menu, position, 1, pointerof(info))
              end
              position += 1
            end

            cursor = Win32::LibUser32::Point.new
            Win32::LibUser32.GetCursorPos(pointerof(cursor))

            # KB135788: the window must be foreground before TrackPopupMenu,
            # and eat the resulting WM_NULL afterwards, or the menu refuses
            # to dismiss when the user clicks elsewhere.
            Win32::LibUser32.SetForegroundWindow(@window)
            cmd = Win32::LibUser32.TrackPopupMenu(
              menu,
              Win32::TPM_RIGHTBUTTON | Win32::TPM_RETURNCMD | Win32::TPM_NONOTIFY |
                Win32::TPM_RIGHTALIGN | Win32::TPM_BOTTOMALIGN,
              cursor.x, cursor.y, 0, @window, Pointer(Void).null)
            Win32::LibUser32.PostMessageW(@window, Win32::WM_NULL, 0_u64, 0_i64)

            @on_click.call(cmd) if cmd != 0
          ensure
            Win32::LibUser32.DestroyMenu(menu)
          end
        end

        private def menu_item(f_mask : UInt32, w_id : Int32)
          info = Win32::LibUser32::MenuItemInfoW.new
          info.cb_size = sizeof(Win32::LibUser32::MenuItemInfoW)
          info.f_mask = f_mask
          info.w_id = w_id.to_u32!
          info
        end

        private def default_icon : Void*
          Win32::LibUser32.LoadIconW(Pointer(Void).null, Win32::IDI_APPLICATION)
        end

        # ICO from a temp file; PNG via GDI+; SVG has no native decoder —
        # fall back to the default application icon.
        private def load_hicon(icon : IconSource) : Void*
          case icon.format
          when :ico, :png
            ext = icon.format == :ico ? "ico" : "png"
            path = File.join(Dir.tempdir, "positron_tray_#{Process.pid}_#{Time.utc.to_unix_ms}.#{ext}")
            File.write(path, icon.bytes)
            hicon =
              if icon.format == :ico
                Win32::LibUser32.LoadImageW(Pointer(Void).null,
                  Win32.wstr(path).to_unsafe, Win32::IMAGE_ICON, 0, 0,
                  Win32::LR_LOADFROMFILE | Win32::LR_DEFAULTSIZE)
              else
                Win32.hicon_from_png(path)
              end
            File.delete(path) rescue nil
            hicon.null? ? default_icon : hicon
          else
            default_icon
          end
        rescue ex
          Log.warn { "tray: failed to load icon (#{icon.format}): #{ex.message}" }
          default_icon
        end

        private def base_notify_data : Win32::LibShell32::NotifyIconDataW
          data = Win32::LibShell32::NotifyIconDataW.new
          data.cb_size = sizeof(Win32::LibShell32::NotifyIconDataW)
          data.hwnd = @window
          data.u_id = TRAY_ICON_ID
          data.h_icon = @hicon
          data
        end

        private def fill_tip(data : Win32::LibShell32::NotifyIconDataW*, tip : String)
          units = Win32.wstr(tip)
          limit = {units.size - 1, 127}.min
          limit.times { |i| data.value.sz_tip[i] = units[i] }
          data.value.sz_tip[limit] = 0
        end

        private def notify_add(tip : String) : Nil
          return if @window.null?
          data = base_notify_data
          data.u_flags = Win32::NIF_MESSAGE | Win32::NIF_ICON | Win32::NIF_TIP | Win32::NIF_SHOWTIP
          data.u_callback_message = TRAY_CALLBACK_MSG
          fill_tip(pointerof(data), tip)
          @added = Win32::LibShell32.Shell_NotifyIconW(Win32::NIM_ADD, pointerof(data)) != 0
          Log.warn { "tray: Shell_NotifyIcon(NIM_ADD) failed — is Explorer running?" } unless @added
        end

        private def notify_modify_icon : Nil
          return unless @added
          data = base_notify_data
          data.u_flags = Win32::NIF_ICON
          Win32::LibShell32.Shell_NotifyIconW(Win32::NIM_MODIFY, pointerof(data))
        end

        private def notify_modify_tip(tip : String) : Nil
          return unless @added
          data = base_notify_data
          data.u_flags = Win32::NIF_TIP
          fill_tip(pointerof(data), tip)
          Win32::LibShell32.Shell_NotifyIconW(Win32::NIM_MODIFY, pointerof(data))
        end

        private def set_icon_state(hidden : Bool) : Nil
          return unless @added
          data = base_notify_data
          data.u_flags = Win32::NIF_STATE
          data.dw_state_mask = Win32::NIS_HIDDEN
          data.dw_state = hidden ? Win32::NIS_HIDDEN : 0_u32
          Win32::LibShell32.Shell_NotifyIconW(Win32::NIM_MODIFY, pointerof(data))
        end
      end
    end
  end
end
