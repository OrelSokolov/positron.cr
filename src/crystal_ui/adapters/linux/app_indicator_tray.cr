require "log"

module CrystalUI
  module Adapters
    module Linux
      # Linux system tray adapter backed by Ayatana AppIndicator.
      #
      # Mirrors the design of getlantern/systray's systray_linux.c:
      # all GTK mutations are dispatched to the GTK main thread via
      # g_idle_add, and menu items are tracked in a linked list so
      # submenus, checkboxes and updates work correctly.
      class AppIndicatorTray < TrayPort
        APP_INDICATOR_CATEGORY_APPLICATION_STATUS = 0

        @indicator : Void*
        @menu : Void*
        @items = Hash(Int32, TrayItem).new
        @nodes = Hash(Int32, MenuItemNode).new
        @next_id = 0
        getter on_click : Proc(Int32, Nil) = ->(id : Int32) { }
        @temp_icon_path : String? = nil
        @mutex = Mutex.new

        struct MenuItemNode
          getter widget : Void*
          getter signal_id : UInt64

          def initialize(@widget : Void*, @signal_id : UInt64)
          end
        end

        def initialize
          @indicator = Pointer(Void).null
          @menu = Pointer(Void).null
        end

        def supported? : Bool
          true
        end

        def create(icon : IconSource? = nil, title : String? = nil)
          # Use g_object_new(APP_INDICATOR_TYPE, ...) instead of the deprecated
          # app_indicator_new(), matching getlantern/systray's fix.
          @indicator = LibGObject.g_object_new(
            LibAppIndicator.app_indicator_get_type,
            "id", "crystal-ui",
            "category", "ApplicationStatus",
            "icon-name", "",
            Pointer(Void).null
          )
          @menu = LibGTK.gtk_menu_new
          LibAppIndicator.app_indicator_set_menu(@indicator, @menu)

          set_icon(icon) if icon
          set_title(title) if title
        end

        def show
          LibAppIndicator.app_indicator_set_status(
            @indicator,
            LibAppIndicator::APP_INDICATOR_STATUS_ACTIVE
          )
        end

        def hide
          LibAppIndicator.app_indicator_set_status(
            @indicator,
            LibAppIndicator::APP_INDICATOR_STATUS_PASSIVE
          )
        end

        def set_icon(icon : IconSource)
          if icon.ico?
            Log.warn { "ICO icons are not supported by the Linux tray adapter; ignoring" }
            return
          end

          data = icon.bytes.dup
          Box.box({self, data, icon.format}).tap do |box|
            LibGLib.g_idle_add(
              ->(ptr : Void*) {
                tuple = Box(Tuple(AppIndicatorTray, Bytes, Symbol)).unbox(ptr)
                tuple[0].do_set_icon(tuple[1], tuple[2])
                0 # G_SOURCE_REMOVE
              }.pointer.as(Void*),
              box
            )
          end
        end

        def set_title(title : String)
          Box.box({self, title}).tap do |box|
            LibGLib.g_idle_add(
              ->(ptr : Void*) {
                tuple = Box(Tuple(AppIndicatorTray, String)).unbox(ptr)
                tuple[0].do_set_title(tuple[1])
                0
              }.pointer.as(Void*),
              box
            )
          end
        end

        def set_tooltip(tooltip : String)
          # AppIndicator does not support tooltips on the icon itself.
        end

        def add_or_update_item(item : TrayItem)
          @mutex.synchronize { @items[item.id] = item.dup }
          Box.box({self, item}).tap do |box|
            LibGLib.g_idle_add(
              ->(ptr : Void*) {
                tuple = Box(Tuple(AppIndicatorTray, TrayItem)).unbox(ptr)
                tuple[0].do_add_or_update_item(tuple[1])
                0
              }.pointer.as(Void*),
              box
            )
          end
        end

        def add_separator(id : Int32)
          Box.box({self, id}).tap do |box|
            LibGLib.g_idle_add(
              ->(ptr : Void*) {
                tuple = Box(Tuple(AppIndicatorTray, Int32)).unbox(ptr)
                tuple[0].do_add_separator(tuple[1])
                0
              }.pointer.as(Void*),
              box
            )
          end
        end

        def remove_item(id : Int32)
          @mutex.synchronize { @items.delete(id) }
          Box.box({self, id}).tap do |box|
            LibGLib.g_idle_add(
              ->(ptr : Void*) {
                tuple = Box(Tuple(AppIndicatorTray, Int32)).unbox(ptr)
                tuple[0].do_hide_item(tuple[1])
                0
              }.pointer.as(Void*),
              box
            )
          end
        end

        def show_item(id : Int32)
          Box.box({self, id}).tap do |box|
            LibGLib.g_idle_add(
              ->(ptr : Void*) {
                tuple = Box(Tuple(AppIndicatorTray, Int32)).unbox(ptr)
                tuple[0].do_show_item(tuple[1])
                0
              }.pointer.as(Void*),
              box
            )
          end
        end

        def hide_item(id : Int32)
          Box.box({self, id}).tap do |box|
            LibGLib.g_idle_add(
              ->(ptr : Void*) {
                tuple = Box(Tuple(AppIndicatorTray, Int32)).unbox(ptr)
                tuple[0].do_hide_item(tuple[1])
                0
              }.pointer.as(Void*),
              box
            )
          end
        end

        def on_item_click(&block : Int32 ->)
          @on_click = block
        end

        def quit
          LibGLib.g_idle_add(
            ->(ptr : Void*) {
              tray = ptr.as(AppIndicatorTray*).value
              tray.do_quit
              0
            }.pointer.as(Void*),
            self.as(Void*)
          )
        end

        protected def do_set_icon(icon_bytes : Bytes, format : Symbol)
          cleanup_temp_icon

          ext = case format
                when :svg then "svg"
                when :png then "png"
                else           "bin"
                end

          path = File.join(Dir.tempdir, "crystalui_icon_XXXXXX.#{ext}")
          fd = LibC.mkstemp(path)
          return if fd == -1

          written = LibC.write(fd, icon_bytes.to_unsafe, icon_bytes.size)
          LibC.close(fd)

          if written == icon_bytes.size
            @temp_icon_path = path
            LibAppIndicator.app_indicator_set_icon_full(@indicator, path, "")
            LibAppIndicator.app_indicator_set_attention_icon_full(@indicator, path, "")
          else
            LibC.unlink(path)
          end
        end

        protected def do_set_title(title : String)
          LibAppIndicator.app_indicator_set_title(@indicator, title)
          LibAppIndicator.app_indicator_set_label(@indicator, title, "")
        end

        protected def do_add_or_update_item(item : TrayItem)
          return if item.separator?

          if node = @nodes[item.id]?
            LibGTK.gtk_menu_item_set_label(node.widget, item.title)

            if item.checkable
              LibGObject.g_signal_handler_block(node.widget, node.signal_id)
              LibGTK.gtk_check_menu_item_set_active(node.widget, item.checked ? 1 : 0)
              LibGObject.g_signal_handler_unblock(node.widget, node.signal_id)
            end
          else
            widget = if item.checkable
                       LibGTK.gtk_check_menu_item_new_with_label(item.title)
                     else
                       LibGTK.gtk_menu_item_new_with_label(item.title)
                     end

            ctx = Box.box({self, item.id})
            handler = ->(widget : Void*, data : Void*) do
              tuple = Box(Tuple(AppIndicatorTray, Int32)).unbox(data)
              tuple[0].on_click.call(tuple[1])
            end

            signal_id = LibGObject.g_signal_connect_data(
              widget,
              "activate",
              handler.pointer.as(Void*),
              ctx.as(Void*),
              nil,
              0
            )

            parent_menu = if item.parent_id > 0
                            parent_node = @nodes[item.parent_id]?
                            if parent_node
                              submenu = LibGTK.gtk_menu_item_get_submenu(parent_node.widget)
                              if submenu.null?
                                submenu = LibGTK.gtk_menu_new
                                LibGTK.gtk_menu_item_set_submenu(parent_node.widget, submenu)
                              end
                              submenu
                            else
                              @menu
                            end
                          else
                            @menu
                          end

            LibGTK.gtk_menu_shell_append(parent_menu, widget)
            @nodes[item.id] = MenuItemNode.new(widget: widget, signal_id: signal_id)
          end

          if node = @nodes[item.id]?
            LibGTK.gtk_widget_set_sensitive(node.widget, item.disabled ? 0 : 1)
            LibGTK.gtk_widget_show(node.widget)
          end

          LibGTK.gtk_widget_show_all(@menu)
        end

        protected def do_add_separator(id : Int32)
          separator = LibGTK.gtk_separator_menu_item_new
          LibGTK.gtk_menu_shell_append(@menu, separator)
          LibGTK.gtk_widget_show(separator)
          @nodes[id] = MenuItemNode.new(widget: separator, signal_id: 0_u64)
        end

        protected def do_hide_item(id : Int32)
          if node = @nodes[id]?
            LibGTK.gtk_widget_hide(node.widget)
          end
        end

        protected def do_show_item(id : Int32)
          if node = @nodes[id]?
            LibGTK.gtk_widget_show(node.widget)
          end
        end

        protected def do_quit
          cleanup_temp_icon
          hide
          LibGTK.gtk_main_quit
        end

        private def cleanup_temp_icon
          if path = @temp_icon_path
            LibC.unlink(path) if File.exists?(path)
            @temp_icon_path = nil
          end
        end

        @[Link("ayatana-appindicator3")]
        lib LibAppIndicator
          APP_INDICATOR_STATUS_PASSIVE   = 0
          APP_INDICATOR_STATUS_ACTIVE    = 1
          APP_INDICATOR_STATUS_ATTENTION = 2

          fun app_indicator_get_type : UInt64
          fun app_indicator_set_status(self : Void*, status : Int32)
          fun app_indicator_set_menu(self : Void*, menu : Void*)
          fun app_indicator_set_icon_full(self : Void*, icon_name : LibC::Char*, icon_desc : LibC::Char*)
          fun app_indicator_set_attention_icon_full(self : Void*, icon_name : LibC::Char*, icon_desc : LibC::Char*)
          fun app_indicator_set_title(self : Void*, title : LibC::Char*)
          fun app_indicator_set_label(self : Void*, label : LibC::Char*, guide : LibC::Char*)
        end

        @[Link("gtk-3")]
        lib LibGTK
          fun gtk_menu_new : Void*
          fun gtk_menu_item_new_with_label(label : LibC::Char*) : Void*
          fun gtk_check_menu_item_new_with_label(label : LibC::Char*) : Void*
          fun gtk_check_menu_item_set_active(widget : Void*, active : Int32)
          fun gtk_menu_item_set_label(widget : Void*, label : LibC::Char*)
          fun gtk_menu_item_get_submenu(widget : Void*) : Void*
          fun gtk_menu_item_set_submenu(widget : Void*, submenu : Void*)
          fun gtk_separator_menu_item_new : Void*
          fun gtk_menu_shell_append(menu_shell : Void*, child : Void*)
          fun gtk_widget_show(widget : Void*)
          fun gtk_widget_show_all(widget : Void*)
          fun gtk_widget_hide(widget : Void*)
          fun gtk_widget_set_sensitive(widget : Void*, sensitive : Int32)
          fun gtk_main_quit
        end

        @[Link("glib-2.0")]
        lib LibGLib
          fun g_idle_add(func : Void*, data : Void*) : UInt32
        end

        @[Link("gobject-2.0")]
        lib LibGObject
          fun g_object_new(object_type : UInt64, ...) : Void*

          fun g_signal_connect_data(
            instance : Void*,
            detailed_signal : LibC::Char*,
            c_handler : Void*,
            data : Void*,
            destroy_data : Void*,
            connect_flags : Int32,
          ) : UInt64

          fun g_signal_handler_block(instance : Void*, handler_id : UInt64)
          fun g_signal_handler_unblock(instance : Void*, handler_id : UInt64)
        end
      end
    end
  end
end
