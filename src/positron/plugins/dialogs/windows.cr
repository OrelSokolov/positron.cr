require "log"
require "./adapter"
require "../../adapters/windows/win32"

module Positron::Plugins
  # Windows native dialogs adapter: MessageBoxW for alert/confirm and a
  # small hand-rolled window (STATIC + EDIT + two BUTTONs) for prompt —
  # Win32 has no built-in input box.
  #
  # All methods must run on the UI thread; the plugin marshals them there
  # via `Host#run_on_main`. Both MessageBoxW and the prompt's nested
  # message loop keep dispatching thread messages, so the event-loop
  # timer tick (Fiber.yield) keeps the scheduler alive while a dialog is
  # open.
  class WindowsDialogsAdapter < DialogsAdapter
    include ::Positron::Adapters::Windows # Win32 FFI bindings

    Log = ::Log.for("positron.plugins.dialogs")

    # Control ids for the prompt window.
    IDC_PROMPT_EDIT = 1001
    IDC_PROMPT_OK   = 1 # IDOK
    IDC_PROMPT_CANCEL = 2

    @@prompt_state : PromptState?
    @@prompt_proc = ->(hwnd : Void*, msg : UInt32, wparam : UInt64, lparam : Int64) : Int64 do
      state = @@prompt_state
      return Win32::LibUser32.DefWindowProcW(hwnd, msg, wparam, lparam) unless state

      case msg
      when Win32::WM_COMMAND
        case wparam & 0xFFFF
        when IDC_PROMPT_OK
          state.result = read_edit_text(state)
          Win32::LibUser32.DestroyWindow(hwnd)
        when IDC_PROMPT_CANCEL
          state.result = nil
          Win32::LibUser32.DestroyWindow(hwnd)
        end
        0_i64
      when Win32::WM_CLOSE
        state.result = nil
        Win32::LibUser32.DestroyWindow(hwnd)
        0_i64
      when Win32::WM_DESTROY
        Win32::LibUser32.PostQuitMessage(0)
        0_i64
      else
        Win32::LibUser32.DefWindowProcW(hwnd, msg, wparam, lparam)
      end
    end

    class PromptState
      property window : Void* = Pointer(Void).null
      property edit : Void* = Pointer(Void).null
      property result : String? = nil
    end

    def alert(message : String, title : String, kind : String) : Nil
      icon = case kind
             when "warning" then Win32::MB_ICONWARNING
             when "error"   then Win32::MB_ICONERROR
             else                Win32::MB_ICONINFORMATION
             end
      box(message, title, icon | Win32::MB_OK)
    end

    def confirm(message : String, title : String) : Bool
      box(message, title, Win32::MB_ICONINFORMATION | Win32::MB_OKCANCEL) == Win32::IDOK
    end

    def prompt(message : String, default : String, title : String) : String?
      show_prompt(message, default, title)
    end

    # --- internals ---

    private def box(message : String, title : String, type : UInt32) : Int32
      Win32::LibUser32.MessageBoxW(
        Pointer(Void).null,
        Win32.wstr(message).to_unsafe,
        Win32.wstr(title.empty? ? "Positron" : title).to_unsafe,
        type)
    end

    private def self.read_edit_text(state : PromptState) : String?
      return nil if state.edit.null?
      len = Win32::LibUser32.SendMessageW(state.edit, Win32::WM_GETTEXTLENGTH, 0_u64, 0_i64)
      buf = Slice(UInt16).new(len.to_i32 + 1)
      Win32::LibUser32.SendMessageW(
        state.edit, Win32::WM_GETTEXT, buf.size.to_u64!, buf.to_unsafe.address.to_i64!)
      Win32.wstr_back(buf.to_unsafe)
    end

    private def show_prompt(message : String, default : String, title : String) : String?
      state = PromptState.new
      @@prompt_state = state

      instance = Win32::LibKernel32.GetModuleHandleW(Pointer(UInt16).null)
      class_name = Win32.wstr("PositronPromptDlg")

      wc = Win32::LibUser32::WndClassExW.new
      wc.cb_size = sizeof(Win32::LibUser32::WndClassExW)
      wc.lpfn_wnd_proc = @@prompt_proc.pointer
      wc.h_instance = instance
      wc.h_cursor = Win32::LibUser32.LoadCursorW(Pointer(Void).null, Win32::IDC_ARROW)
      wc.lpsz_class_name = class_name.to_unsafe
      Win32::LibUser32.RegisterClassExW(pointerof(wc)) # failure = already registered

      width = 420
      height = 180
      screen_w = Win32::LibUser32.GetSystemMetrics(0)
      screen_h = Win32::LibUser32.GetSystemMetrics(1)
      x = (screen_w - width) // 2
      y = (screen_h - height) // 2

      state.window = Win32::LibUser32.CreateWindowExW(
        Win32::WS_EX_CONTROLPARENT, class_name.to_unsafe,
        Win32.wstr(title.empty? ? "Positron" : title).to_unsafe,
        0x00CA0000_u32, # WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU
        x, y, width, height,
        Pointer(Void).null, Pointer(Void).null, instance, Pointer(Void).null)
      return nil if state.window.null?

      font = Win32::LibGdi.GetStockObject(Win32::DEFAULT_GUI_FONT)

      label = create_child(state.window, instance, "STATIC", message,
        0x50000000_u32, 14, 12, 376, 32) # WS_CHILD | WS_VISIBLE
      state.edit = create_child(state.window, instance, "EDIT", default,
        0x50810080_u32, # WS_CHILD|WS_VISIBLE|WS_TABSTOP|WS_BORDER|ES_AUTOHSCROLL
        14, 52, 376, 24)
      ok = create_child(state.window, instance, "BUTTON", "OK",
        0x50010001_u32, # WS_CHILD|WS_VISIBLE|WS_TABSTOP|BS_DEFPUSHBUTTON
        210, 96, 88, 28, id: IDC_PROMPT_OK)
      cancel = create_child(state.window, instance, "BUTTON", "Cancel",
        0x50010000_u32, 306, 96, 88, 28, id: IDC_PROMPT_CANCEL)

      {label, state.edit, ok, cancel}.each do |control|
        Win32::LibUser32.SendMessageW(control, Win32::WM_SETFONT, font.address.to_u64!, 1_i64)
      end

      Win32::LibUser32.ShowWindow(state.window, Win32::SW_SHOW)
      Win32::LibUser32.SetForegroundWindow(state.window)

      # Nested modal loop; WM_QUIT from WM_DESTROY ends it. WM_TIMER keeps
      # flowing (Fiber.yield ticks), so other fibers stay responsive.
      msg = Win32::LibUser32::Msg.new
      while Win32::LibUser32.GetMessageW(pointerof(msg), Pointer(Void).null, 0, 0) > 0
        if Win32::LibUser32.IsDialogMessageW(state.window, pointerof(msg)) == 0
          Win32::LibUser32.TranslateMessage(pointerof(msg))
          Win32::LibUser32.DispatchMessageW(pointerof(msg))
        end
      end

      result = state.result
      @@prompt_state = nil
      result
    end

    private def create_child(parent : Void*, instance : Void*, klass : String, text : String,
                             style : UInt32, x : Int32, y : Int32, w : Int32, h : Int32,
                             id : Int32 = 0) : Void*
      hwnd = Win32::LibUser32.CreateWindowExW(
        0_u32, Win32.wstr(klass).to_unsafe, Win32.wstr(text).to_unsafe,
        style, x, y, w, h,
        parent, Pointer(Void).new(id.to_u64!), instance, Pointer(Void).null)
      hwnd
    end
  end
end
