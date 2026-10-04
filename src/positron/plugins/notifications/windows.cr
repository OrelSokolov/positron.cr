require "log"
require "json"
require "./adapter"
require "../../adapters/windows/win32"

module Positron::Plugins
  # Windows implementation of system notifications using Shell_NotifyIcon
  # balloon messages (rendered as toasts in the action center on Win10/11).
  #
  # The adapter owns a hidden message window that receives the tray
  # callbacks; NIN_BALLOONUSERCLICK is routed back through the plugin's
  # `on_click` handler.
  class WindowsNotificationsAdapter < NotificationsAdapter
    include ::Positron::Adapters::Windows # Win32 FFI bindings
    Log = ::Log.for("positron.plugins.notifications")

    TRAY_CALLBACK_MSG = Win32::WM_APP + 5 # avoid the tray adapter's WM_APP+1
    TRAY_ICON_ID      = 7_u32
    CLASS_NAME        = "PositronNotifyWnd"

    @@instance : WindowsNotificationsAdapter?

    @@wndproc = ->(hwnd : Void*, msg : UInt32, wparam : UInt64, lparam : Int64) : Int64 do
      adapter = @@instance
      return Win32::LibUser32.DefWindowProcW(hwnd, msg, wparam, lparam) unless adapter

      if msg == TRAY_CALLBACK_MSG && lparam == Win32::NIN_BALLOONUSERCLICK
        adapter.handle_click
        0_i64
      elsif msg == Win32::WM_DESTROY
        0_i64
      else
        Win32::LibUser32.DefWindowProcW(hwnd, msg, wparam, lparam)
      end
    end

    @window : Void* = Pointer(Void).null
    @added = false
    @current_id : String? = nil
    @active = Set(String).new

    def initialize
      @@instance = self
      create_window
    end

    def send(id : String, title : String, body : String) : String
      ensure_icon

      data = base_data
      data.u_flags = Win32::NIF_INFO
      fill_text(pointerof(data), body, :info)
      fill_text(pointerof(data), title, :title)
      data.dw_info_flags = Win32::NIIF_INFO
      data.u_timeout = 10_000

      if Win32::LibShell32.Shell_NotifyIconW(Win32::NIM_MODIFY, pointerof(data)) == 0
        Log.warn { "Shell_NotifyIcon(NIM_MODIFY) failed — balloon not shown" }
      end

      @current_id = id
      @active << id
      id
    end

    def clear(id : String) : Bool
      return false unless @active.delete(id)
      data = base_data
      data.u_flags = Win32::NIF_INFO
      Win32::LibShell32.Shell_NotifyIconW(Win32::NIM_MODIFY, pointerof(data)) != 0
    end

    def request_permission : Bool
      true # tray balloons need no explicit permission on desktop Windows
    end

    def check_permission : Bool
      true
    end

    protected def handle_click : Nil
      if id = @current_id
        emit_click(id)
      end
    end

    # --- internals ---

    private def create_message_data : Win32::LibShell32::NotifyIconDataW
      data = Win32::LibShell32::NotifyIconDataW.new
      data.cb_size = sizeof(Win32::LibShell32::NotifyIconDataW)
      data.hwnd = @window
      data.u_id = TRAY_ICON_ID
      data
    end

    private def create_window : Nil
      instance = Win32::LibKernel32.GetModuleHandleW(Pointer(UInt16).null)
      class_name = Win32.wstr(CLASS_NAME)

      wc = Win32::LibUser32::WndClassExW.new
      wc.cb_size = sizeof(Win32::LibUser32::WndClassExW)
      wc.lpfn_wnd_proc = @@wndproc.pointer
      wc.h_instance = instance
      wc.h_cursor = Win32::LibUser32.LoadCursorW(Pointer(Void).null, Win32::IDC_ARROW)
      wc.lpsz_class_name = class_name.to_unsafe
      Win32::LibUser32.RegisterClassExW(pointerof(wc)) # failure = already registered

      # A regular hidden top-level window, NOT a message-only one:
      # Explorer's balloon/toast plumbing requires a real window to
      # associate the notification with (message-only windows make
      # Shell_NotifyIcon succeed but the balloon never shows).
      @window = Win32::LibUser32.CreateWindowExW(
        0_u32, class_name.to_unsafe, class_name.to_unsafe,
        0_u32, 0, 0, 0, 0,
        Pointer(Void).null, Pointer(Void).null, instance, Pointer(Void).null)
      Log.warn { "notifications: failed to create tray window" } if @window.null?
    end

    private def base_data : Win32::LibShell32::NotifyIconDataW
      create_message_data
    end

    # Static arrays are value types in Crystal: `data.value.sz_info[i] = x`
    # would mutate a throwaway copy. Read the struct, mutate the copy,
    # write the whole struct back through the pointer.
    private def fill_text(data : Win32::LibShell32::NotifyIconDataW*, text : String, field : Symbol) : Nil
      units = Win32.wstr(text)
      limit = {units.size - 1, field == :title ? 63 : 255}.min
      d = data.value
      if field == :title
        limit.times { |i| d.sz_info_title[i] = units[i] }
        d.sz_info_title[limit] = 0
      else
        limit.times { |i| d.sz_info[i] = units[i] }
        d.sz_info[limit] = 0
      end
      data.value = d
    end

    # The balloon rides on a tray icon: add it (with a tooltip, hidden
    # state not set — a quiet icon in the overflow area) once, lazily.
    private def ensure_icon : Nil
      return if @added || @window.null?

      data = base_data
      data.u_flags = Win32::NIF_MESSAGE | Win32::NIF_ICON | Win32::NIF_TIP | Win32::NIF_SHOWTIP
      data.u_callback_message = TRAY_CALLBACK_MSG
      data.h_icon = Win32::LibUser32.LoadIconW(Pointer(Void).null, Win32::IDI_APPLICATION)
      fill_tip(pointerof(data), "Positron")
      @added = Win32::LibShell32.Shell_NotifyIconW(Win32::NIM_ADD, pointerof(data)) != 0
      Log.warn { "Shell_NotifyIcon(NIM_ADD) failed — is Explorer running?" } unless @added

      # Win11 plumbing: opt the icon into NOTIFYICON_VERSION_4 behaviour
      # (same DWORD as u_timeout — they are a union in the C header).
      # Without this Explorer may not route balloons into the toast
      # pipeline on behalf of the icon.
      if @added
        data.u_timeout = 4_u32 # uVersion = NOTIFYICON_VERSION_4
        Win32::LibShell32.Shell_NotifyIconW(Win32::NIM_SETVERSION, pointerof(data))
      end
    end

    private def fill_tip(data : Win32::LibShell32::NotifyIconDataW*, tip : String) : Nil
      units = Win32.wstr(tip)
      limit = {units.size - 1, 127}.min
      d = data.value
      limit.times { |i| d.sz_tip[i] = units[i] }
      d.sz_tip[limit] = 0
      data.value = d
    end
  end
end
