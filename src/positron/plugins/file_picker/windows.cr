require "log"
require "./adapter"
require "../../adapters/windows/win32"

module Positron::Plugins
  # Windows implementation of the FilePicker plugin using the classic
  # comdlg32 GetOpenFileNameW dialog.
  #
  # The dialog runs a nested modal message loop on the UI thread (the
  # plugin marshals the call there via `Host#run_on_main`), so the
  # event-loop timer tick keeps the Crystal scheduler alive while it is
  # open.
  class WindowsFilePickerAdapter < FilePickerAdapter
    include ::Positron::Adapters::Windows # Win32 FFI bindings
    def pick(accept : String) : String?
      buffer = Slice(UInt16).new(32768)

      ofn = Win32::LibComDlg32::OpenFileNameW.new
      ofn.l_struct_size = sizeof(Win32::LibComDlg32::OpenFileNameW)
      ofn.lpstr_title = Win32.wstr("Select a file").to_unsafe
      ofn.lpstr_file = buffer.to_unsafe
      ofn.n_max_file = buffer.size.to_u32!
      ofn.lpstr_filter = filter_for(accept)
      ofn.n_filter_index = 1
      ofn.flags = Win32::OFN_FILEMUSTEXIST | Win32::OFN_PATHMUSTEXIST |
                  Win32::OFN_HIDEREADONLY | Win32::OFN_NOCHANGEDIR

      if Win32::LibComDlg32.GetOpenFileNameW(pointerof(ofn)) != 0
        path = Win32.wstr_back(buffer.to_unsafe)
        path.empty? ? nil : path
      else
        nil
      end
    end

    # `accept` follows the HTML input convention: ".txt", ".txt,.md" or a
    # MIME type. Extensions become one "Supported files" filter entry;
    # anything not recognized falls back to "All files". The result is a
    # double-NUL-terminated UTF-16 pair list: "Desc\0Pattern\0\0".
    private def filter_for(accept : String) : UInt16*
      exts = accept.split(',')
        .map(&.strip)
        .select { |token| token.starts_with?('.') && token.size > 1 }
        .map { |token| token.starts_with?("*.") ? token : "*#{token}" }

      description, pattern =
        if exts.empty?
          {"All files", "*.*"}
        else
          {"Supported files", exts.join(";")}
        end

      units = [] of UInt16
      {description, pattern}.each do |part|
        units.concat(part.to_utf16.to_a)
        units << 0_u16
      end
      units << 0_u16

      slice = Slice.new(units.to_unsafe.as(UInt16*), units.size).dup
      @filters = slice # keep alive until GetOpenFileNameW returns
      slice.to_unsafe
    end

    @filters : Slice(UInt16)?
  end
end
