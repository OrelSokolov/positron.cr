require "log"
require "./adapter"
require "../../adapters/windows/win32"

module Positron::Plugins
  # Windows implementation of the SaveFileDialog plugin using comdlg32
  # GetSaveFileNameW.
  class WindowsSaveFileDialogAdapter < SaveFileDialogAdapter
    include ::Positron::Adapters::Windows # Win32 FFI bindings
    def save(suggested_name : String) : String?
      buffer = Slice(UInt16).new(32768)
      units = Win32.wstr(suggested_name)
      buffer[0, units.size].copy_from(units) unless suggested_name.empty?

      ofn = Win32::LibComDlg32::OpenFileNameW.new
      ofn.l_struct_size = sizeof(Win32::LibComDlg32::OpenFileNameW)
      ofn.lpstr_title = Win32.wstr("Save file").to_unsafe
      ofn.lpstr_file = buffer.to_unsafe
      ofn.n_max_file = buffer.size.to_u32!
      ofn.lpstr_filter = all_files_filter
      ofn.n_filter_index = 1
      ofn.flags = Win32::OFN_OVERWRITEPROMPT | Win32::OFN_PATHMUSTEXIST |
                  Win32::OFN_HIDEREADONLY | Win32::OFN_NOCHANGEDIR

      if Win32::LibComDlg32.GetSaveFileNameW(pointerof(ofn)) != 0
        path = Win32.wstr_back(buffer.to_unsafe)
        path.empty? ? nil : path
      else
        nil
      end
    end

    # "All files\0*.*\0\0" as UTF-16.
    private def all_files_filter : UInt16*
      units = [] of UInt16
      {"All files", "*.*"}.each do |part|
        units.concat(part.to_utf16.to_a)
        units << 0_u16
      end
      units << 0_u16

      slice = Slice.new(units.to_unsafe.as(UInt16*), units.size).dup
      @filters = slice
      slice.to_unsafe
    end

    @filters : Slice(UInt16)?
  end
end
