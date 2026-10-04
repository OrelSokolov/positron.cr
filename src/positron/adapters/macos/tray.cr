require "log"
require "./objc"

module Positron
  module Adapters
    module MacOS
      # macOS system tray adapter backed by NSStatusBar / NSStatusItem.
      #
      # Mirrors the AppIndicator adapter's behaviour: menu items are
      # tracked by id, checkable items toggle on click, submenus follow
      # TrayItem#parent_id. Clicks arrive as target-action on a
      # dynamically registered NSObject ("PositronTrayTarget") whose IMP
      # dispatches through the item tag. All AppKit calls happen on the
      # main thread, which is also the Crystal fiber thread — no
      # marshalling needed.
      class StatusBarTray < TrayPort
        ACTION_SELECTOR = "positronTrayAction:"

        @status_bar : Void*?
        @status_item : Void*?
        @menu : Void*?
        @items = Hash(Int32, TrayItem).new
        @nodes = Hash(Int32, Void*).new # id -> NSMenuItem
        @target_obj : Void*?
        getter on_click : Proc(Int32, Nil) = ->(id : Int32) { }

        @@action_imp : Proc(Void*, Void*, Void*, Nil)?

        def initialize
        end

        def supported? : Bool
          true
        end

        def create(icon : IconSource? = nil, title : String? = nil)
          App.ensure_app

          ObjC.with_autorelease_pool do
            @status_bar = ObjC.send0(ObjC.cls("NSStatusBar"), ObjC.sel("systemStatusBar"))
            # NSVariableStatusItemLength (-1.0): float argument → NSInvocation.
            @status_item = ObjC::Call
              .new(@status_bar.not_nil!, "statusItemWithLength:")
              .double(2, -1.0)
              .invoke
              .ret_ptr

            @target_obj ||= build_target
            @menu = ObjC.send1(
              ObjC.send0(ObjC.cls("NSMenu"), ObjC.sel("alloc")),
              ObjC.sel("initWithTitle:"), ObjC.nsstr(title || "Positron"))
            # Items must obey setEnabled: instead of AppKit's auto-enable
            # heuristics (which would grey out everything target-less).
            ObjC.send1(@menu.not_nil!, ObjC.sel("setAutoenablesItems:"), ObjC.bool_arg(false))
            ObjC.send1(@status_item.not_nil!, ObjC.sel("setMenu:"), @menu.not_nil!)

            set_icon(icon) if icon
            set_title(title) if title
          end
        end

        def set_icon(icon : IconSource)
          if icon.ico?
            Log.warn { "ICO icons are not supported by the macOS tray adapter; ignoring" }
            return
          end
          return unless status_item?

          image = ObjC.send1(
            ObjC.send0(ObjC.cls("NSImage"), ObjC.sel("alloc")),
            ObjC.sel("initWithData:"), ObjC.nsdata(icon.bytes))
          if image.null?
            Log.warn { "macOS tray: NSImage could not decode the icon data" }
            return
          end
          ObjC.send1(image, ObjC.sel("setTemplate:"), ObjC.bool_arg(false))
          # The button retains the image; balance our alloc reference.
          ObjC.send1(button, ObjC.sel("setImage:"), image)
          ObjC.send0(image, ObjC.sel("release"))
        end

        def set_title(title : String)
          return unless status_item?
          ObjC.send1(button, ObjC.sel("setTitle:"), ObjC.nsstr(title))
        end

        def set_tooltip(tooltip : String)
          return unless status_item?
          ObjC.send1(button, ObjC.sel("setToolTip:"), ObjC.nsstr(tooltip))
        end

        def add_or_update_item(item : TrayItem)
          return if item.separator?

          @items[item.id] = item.dup
          return unless menu_created?

          if node = @nodes[item.id]?
            apply_item_state(node, item)
          else
            node = ObjC.send3(
              ObjC.send0(ObjC.cls("NSMenuItem"), ObjC.sel("alloc")),
              ObjC.sel("initWithTitle:action:keyEquivalent:"),
              ObjC.nsstr(item.title),
              ObjC.sel(ACTION_SELECTOR),
              ObjC.nsstr(""))
            ObjC.send1(node, ObjC.sel("setTarget:"), @target_obj.not_nil!)
            ObjC.send1(node, ObjC.sel("setTag:"), ObjC.int_arg(item.id))
            ObjC.send1(parent_menu_for(item.parent_id), ObjC.sel("addItem:"), node)
            @nodes[item.id] = node
            apply_item_state(node, item)
          end
        end

        def add_separator(id : Int32)
          return unless menu_created?
          separator = ObjC.send0(ObjC.cls("NSMenuItem"), ObjC.sel("separatorItem"))
          ObjC.send1(separator, ObjC.sel("setTag:"), ObjC.int_arg(id))
          ObjC.send1(@menu.not_nil!, ObjC.sel("addItem:"), separator)
          @nodes[id] = separator
        end

        def remove_item(id : Int32)
          @items.delete(id)
          if (node = @nodes.delete(id)) && !node.null?
            owner = ObjC.send0(node, ObjC.sel("menu"))
            ObjC.send1(owner, ObjC.sel("removeItem:"), node) unless owner.null?
          end
        end

        def show_item(id : Int32)
          if node = @nodes[id]?
            ObjC.send1(node, ObjC.sel("setHidden:"), ObjC.bool_arg(false))
          end
        end

        def hide_item(id : Int32)
          if node = @nodes[id]?
            ObjC.send1(node, ObjC.sel("setHidden:"), ObjC.bool_arg(true))
          end
        end

        def on_item_click(&block : Int32 ->)
          @on_click = block
        end

        def show
          if item = @status_item
            ObjC.send1(item, ObjC.sel("setVisible:"), ObjC.bool_arg(true)) if responds?(item, "setVisible:")
          end
        end

        def hide
          if item = @status_item
            ObjC.send1(item, ObjC.sel("setVisible:"), ObjC.bool_arg(false)) if responds?(item, "setVisible:")
          end
        end

        def quit
          if (bar = @status_bar) && (item = @status_item)
            ObjC.send1(bar, ObjC.sel("removeStatusItem:"), item)
          end
          @status_item = nil
        end

        # --- Internals ---

        protected def handle_action(sender : Void*) : Nil
          id = ObjC.send0_i(sender, ObjC.sel("tag")).to_i32
          item = @items[id]?

          # NSMenuItem does not auto-toggle; keep the checked state here.
          if item && item.checkable
            item.checked = !item.checked
            @items[id] = item
            if node = @nodes[id]?
              ObjC.send1(node, ObjC.sel("setState:"), ObjC.int_arg(item.checked ? 1 : 0))
            end
          end

          @on_click.call(id)
        end

        private def button : Void*
          ObjC.send0(@status_item.not_nil!, ObjC.sel("button"))
        end

        private def status_item? : Bool
          !@status_item.nil? && !@status_item.not_nil!.null?
        end

        private def menu_created? : Bool
          !@menu.nil? && !@menu.not_nil!.null?
        end

        private def responds?(obj : Void*, selector : String) : Bool
          ObjC.send1_b(obj, ObjC.sel("respondsToSelector:"), ObjC.sel(selector))
        end

        # Items with parent_id land in the parent's submenu (created on
        # demand); everything else goes on the root menu.
        private def parent_menu_for(parent_id : Int32) : Void*
          return @menu.not_nil! unless parent_id > 0
          parent = @nodes[parent_id]?
          return @menu.not_nil! if parent.nil?

          submenu = ObjC.send0(parent, ObjC.sel("submenu"))
          if submenu.null?
            submenu = ObjC.send1(
              ObjC.send0(ObjC.cls("NSMenu"), ObjC.sel("alloc")),
              ObjC.sel("initWithTitle:"), ObjC.nsstr(""))
            ObjC.send1(parent, ObjC.sel("setSubmenu:"), submenu)
          end
          submenu
        end

        private def apply_item_state(node : Void*, item : TrayItem) : Nil
          ObjC.send1(node, ObjC.sel("setTitle:"), ObjC.nsstr(item.title))
          ObjC.send1(node, ObjC.sel("setState:"), ObjC.int_arg((item.checkable && item.checked) ? 1 : 0))
          ObjC.send1(node, ObjC.sel("setEnabled:"), ObjC.bool_arg(!item.disabled))
          ObjC.send1(node, ObjC.sel("setHidden:"), ObjC.bool_arg(item.hidden))
          ObjC.send1(node, ObjC.sel("setToolTip:"), ObjC.nsstr(item.tooltip)) unless item.tooltip.empty?
        end

        # NSObject receiving menu item target-action clicks.
        private def build_target : Void*
          objc_class = ObjC.new_class("PositronTrayTarget")

          @@action_imp = ->(objc_self : Void*, _cmd : Void*, sender : Void*) {
            tray = ObjC.target_for(objc_self).as?(StatusBarTray)
            tray.try(&.handle_action(sender))
          }
          LibObjC.class_addMethod(
            objc_class, ObjC.sel(ACTION_SELECTOR),
            @@action_imp.not_nil!.pointer.as(Void*), "v@:@")

          target = ObjC.send0(objc_class, ObjC.sel("new"))
          ObjC.bind_target(target, self)
          target
        end
      end
    end
  end
end
