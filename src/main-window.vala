/* -*- Mode: Vala; indent-tabs-mode: nil; tab-width: 4 -*-
 *
 * Copyright (C) 2011,2012 Canonical Ltd
 * Copyright (C) 2015-2017 Mike Gabriel <mike.gabriel@das-netzwerkteam.de>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 3 as
 * published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Authors: Robert Ancell <robert.ancell@canonical.com>
 *          Michael Terry <michael.terry@canonical.com>
 *          Mike Gabriel <mike.gabriel@das-netzwerkteam.de>
 */

public class MainWindow : Gtk.Window
{
    public MenuBar menubar;

    private List<Monitor> monitors;
    private Monitor? primary_monitor;
    private Monitor active_monitor;
    private string only_on_monitor;
    private bool monitor_setting_ok;
    private Background background;
    private Gtk.Box login_box;
    private Gtk.Box hbox;
    private Gtk.Button back_button;
    private ShutdownDialog? shutdown_dialog = null;
    private int window_size_x;
    private int window_size_y;

    public ListStack stack;

    // Menubar is smaller, but with shadow, we reserve more space
    public const int MENUBAR_HEIGHT = 32;

    construct
    {
        events |= Gdk.EventMask.POINTER_MOTION_MASK;

        var accel_group = new Gtk.AccelGroup ();
        add_accel_group (accel_group);

        var bg_color = Gdk.RGBA ();
        bg_color.parse (AGSettings.get_string (AGSettings.KEY_BACKGROUND_COLOR));
        override_background_color (Gtk.StateFlags.NORMAL, bg_color);
        get_accessible ().set_name (_("Login Screen"));
        has_resize_grip = false;
        ArcticaGreeter.add_style_class (this);

        background = new Background ();
        add (background);
        ArcticaGreeter.add_style_class (background);

        login_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        login_box.show ();
        background.add (login_box);

        /* Box for menubar shadow */
        var menubox = new Gtk.EventBox ();
        var menualign = new Gtk.Alignment (0.0f, 0.0f, 1.0f, 0.0f);
        var shadow_path = Path.build_filename (Config.PKGDATADIR,
                                               "shadow.png", null);
        var shadow_style = "";
        if (FileUtils.test (shadow_path, FileTest.EXISTS))
        {
            shadow_style = "background-image: url('%s');
                            background-repeat: repeat;".printf(shadow_path);
        }
        try
        {
            var style = new Gtk.CssProvider ();
            style.load_from_data ("* {background-color: transparent;
                                      %s
                                     }".printf(shadow_style), -1);
            var context = menubox.get_style_context ();
            context.add_provider (style,
                                  Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
        }
        catch (Error e)
        {
            debug ("Internal error loading menubox style: %s", e.message);
        }
        menubox.set_size_request (-1, MENUBAR_HEIGHT);
        menubox.show ();
        menualign.show ();
        menubox.add (menualign);
        login_box.add (menubox);
        ArcticaGreeter.add_style_class (menualign);
        ArcticaGreeter.add_style_class (menubox);

        menubar = new MenuBar (background, accel_group);
        menubar.show ();
        menualign.add (menubar);
        ArcticaGreeter.add_style_class (menubar);

        hbox = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0);
        hbox.expand = true;
        hbox.show ();
        login_box.add (hbox);

        var align = new Gtk.Alignment (0.5f, 0.5f, 0.0f, 0.0f);
        // Hack to avoid gtk 3.20's new allocate logic, which messes us up.
        align.resize_mode = Gtk.ResizeMode.QUEUE;
        align.set_size_request (grid_size, -1);
        align.margin_bottom = MENUBAR_HEIGHT; /* offset for menubar at top */
        align.show ();
        hbox.add (align);

        back_button = new FlatButton ();
        back_button.get_accessible ().set_name (_("Back"));
        Gtk.button_set_focus_on_click (back_button, false);
        var image = new Gtk.Image.from_file (Path.build_filename (Config.PKGDATADIR, "arrow_left.png", null));
        image.show ();
        back_button.set_size_request (grid_size - GreeterList.BORDER * 2, grid_size - GreeterList.BORDER * 2);

        try
        {
            var style = new Gtk.CssProvider ();
            style.load_from_data ("* {background-color: transparent;
                                      %s
                                     }".printf(shadow_style), -1);
            var context = back_button.get_style_context();
            context.add_provider (style,
                                  Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
        }
        catch (Error e)
        {
            debug ("Internal error loading back button style: %s", e.message);
        }

        back_button.add (image);
        back_button.clicked.connect (pop_list);

        align.add (back_button);

        align = new Gtk.Alignment (0.0f, 0.5f, 0.0f, 1.0f);
        align.show ();
        hbox.add (align);

        stack = new ListStack ();
        stack.show ();
        align.add (stack);

        add_user_list ();

        window_size_x = 0;
        window_size_y = 0;
        primary_monitor = null;

        only_on_monitor = AGSettings.get_string(AGSettings.KEY_ONLY_ON_MONITOR);
        monitor_setting_ok = only_on_monitor == "auto";

        if (ArcticaGreeter.singleton.test_mode)
        {
            /* Simulate an 800x600 monitor to the left of a 640x480 monitor */
            monitors = new List<Monitor> ();
            monitors.append (new Monitor (0, 0, 800, 600));
            monitors.append (new Monitor (800, 120, 640, 480));
            background.set_monitors (monitors);
            move_to_monitor (monitors.nth_data (0));
            resize (800 + 640, 600);
        }
        else
        {
            var screen = get_screen ();
            screen.monitors_changed.connect (monitors_changed_cb);
            monitors_changed_cb (screen);
        }
    }

    public void push_list (GreeterList widget)
    {
        stack.push (widget);

        if (stack.num_children > 1)
            back_button.show ();
    }

    public void pop_list ()
    {
        if (stack.num_children <= 2)
            back_button.hide ();

        stack.pop ();
    }

    public override void size_allocate (Gtk.Allocation allocation)
    {
        base.size_allocate (allocation);

        if (hbox != null)
        {
            hbox.margin_left = get_grid_offset (get_allocated_width ()) + grid_size;
            hbox.margin_right = get_grid_offset (get_allocated_width ());
            hbox.margin_top = get_grid_offset (get_allocated_height ());
            hbox.margin_bottom = get_grid_offset (get_allocated_height ());
        }
    }

    public void before_session_start()
    {
        debug ("Cleaning up menu bar related processes (i.e. orca, onboard, etc.)");
        menubar.cleanup();
    }

    public override void realize ()
    {
        base.realize ();
        Gdk.DrawingContext background_context;
        background_context = get_window().begin_draw_frame(get_window().get_visible_region());

        background.set_surface (background_context.get_cairo_context().get_target());

        get_window().end_draw_frame(background_context);
    }

    private void monitors_changed_cb (Gdk.Screen screen)
    {
        Gdk.Display display;
        display = screen.get_display();

        Gdk.Rectangle geometry;
        Gdk.Monitor primary = display.get_primary_monitor();
        geometry = primary.get_geometry();

        window_size_x = 0;
        window_size_y = 0;

        monitors = new List<Monitor> ();
        primary_monitor = null;

        for (var i = 0; i < display.get_n_monitors (); i++)
        {
            Gdk.Monitor monitor = display.get_monitor(i);
            geometry = monitor.get_geometry ();
            debug ("Monitor %d is %dx%d pixels at %d,%d", i, geometry.width, geometry.height, geometry.x, geometry.y);

            if (window_size_x < geometry.x + geometry.width)
            {
                window_size_x = geometry.x + geometry.width;
            }

            if (window_size_y < geometry.y + geometry.height)
            {
                window_size_y = geometry.y + geometry.height;
            }

            if (monitor_is_unique_position (display, i))
            {
                var greeter_monitor = new Monitor (geometry.x, geometry.y, geometry.width, geometry.height);
                var plug_name = monitor.get_model();
                monitors.append (greeter_monitor);

                if (plug_name == only_on_monitor)
                    monitor_setting_ok = true;

                if (plug_name == only_on_monitor || primary_monitor == null || primary == monitor)
                    primary_monitor = greeter_monitor;
            }
        }

        debug ("MainWindow is %dx%d pixels", window_size_x, window_size_y);

        background.set_monitors (monitors);
        resize (window_size_x, window_size_y);
        move (0, 0);
        move_to_monitor (primary_monitor);
    }

    /* Check if a monitor has a unique position */
    private bool monitor_is_unique_position (Gdk.Display display, int n)
    {
        Gdk.Rectangle g0;
        Gdk.Monitor mon0;
        mon0 = display.get_monitor(n);
        g0 = mon0.get_geometry ();

        for (var i = n + 1; i < display.get_n_monitors (); i++)
        {
            Gdk.Rectangle g1;
            Gdk.Monitor mon1;
            mon1 = display.get_monitor(i);
            g1 = mon1.get_geometry();

            if (g0.x == g1.x && g0.y == g1.y)
                return false;
        }

        return true;
    }

    public override bool motion_notify_event (Gdk.EventMotion event)
    {
        if (!monitor_setting_ok || only_on_monitor == "auto")
        {
            var x = (int) (event.x + 0.5);
            var y = (int) (event.y + 0.5);

            /* Get motion event relative to this widget */
            if (event.window != get_window ())
            {
                int w_x, w_y;
                get_window ().get_origin (out w_x, out w_y);
                x -= w_x;
                y -= w_y;
                event.window.get_origin (out w_x, out w_y);
                x += w_x;
                y += w_y;
            }

            foreach (var m in monitors)
            {
                if (x >= m.x && x <= m.x + m.width && y >= m.y && y <= m.y + m.height)
                {
                    move_to_monitor (m);
                    break;
                }
            }
        }
        return false;
    }

    private void move_to_monitor (Monitor monitor)
    {
        active_monitor = monitor;
        login_box.set_size_request (monitor.width, monitor.height);
        background.set_active_monitor (monitor);
        background.move (login_box, monitor.x, monitor.y);

        if (shutdown_dialog != null)
        {
            shutdown_dialog.set_active_monitor (monitor);
            background.move (shutdown_dialog, monitor.x, monitor.y);
        }
    }

    private void add_user_list ()
    {
        GreeterList greeter_list;
        greeter_list = new UserList (background, menubar);
        greeter_list.show ();
        ArcticaGreeter.add_style_class (greeter_list);
        push_list (greeter_list);
    }

    public override bool key_press_event (Gdk.EventKey event)
    {
        var top = stack.top ();

        if (stack.top () is UserList)
        {
            var user_list = stack.top () as UserList;
            if (!user_list.show_hidden_users)
            {
                var shift_mask = Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.MOD1_MASK;
                var control_mask = Gdk.ModifierType.SHIFT_MASK | Gdk.ModifierType.MOD1_MASK;
                var alt_mask = Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.SHIFT_MASK;
                if (((event.keyval == Gdk.Key.Shift_L || event.keyval == Gdk.Key.Shift_R) && (event.state & shift_mask) == shift_mask) ||
                    ((event.keyval == Gdk.Key.Control_L || event.keyval == Gdk.Key.Control_R) && (event.state & control_mask) == control_mask) ||
                    ((event.keyval == Gdk.Key.Alt_L || event.keyval == Gdk.Key.Alt_R) && (event.state & alt_mask) == alt_mask))
                {
                    debug ("Hidden user key combination detected");
                    user_list.show_hidden_users = true;
                    return true;
                }
            }
        }

        switch (event.keyval)
        {
        case Gdk.Key.Escape:
            if (login_box.sensitive)
                top.cancel_authentication ();
            if (shutdown_dialog != null)
                shutdown_dialog.cancel ();
            return true;
        case Gdk.Key.Page_Up:
        case Gdk.Key.KP_Page_Up:
            if (login_box.sensitive)
                top.scroll (GreeterList.ScrollTarget.START);
            return true;
        case Gdk.Key.Page_Down:
        case Gdk.Key.KP_Page_Down:
            if (login_box.sensitive)
                top.scroll (GreeterList.ScrollTarget.END);
            return true;
        case Gdk.Key.Up:
        case Gdk.Key.KP_Up:
            if (login_box.sensitive)
                top.scroll (GreeterList.ScrollTarget.UP);
            return true;
        case Gdk.Key.Down:
        case Gdk.Key.KP_Down:
            if (login_box.sensitive)
                top.scroll (GreeterList.ScrollTarget.DOWN);
            return true;
        case Gdk.Key.Left:
        case Gdk.Key.KP_Left:
            if (shutdown_dialog != null)
                shutdown_dialog.focus_prev ();
            return true;
        case Gdk.Key.Right:
        case Gdk.Key.KP_Right:
            if (shutdown_dialog != null)
                shutdown_dialog.focus_next ();
            return true;
        case Gdk.Key.F10:
            if (login_box.sensitive)
                menubar.select_first (false);
            return true;
        case Gdk.Key.PowerOff:
            show_shutdown_dialog (ShutdownDialogType.SHUTDOWN);
            return true;
        case Gdk.Key.Print:
            debug ("Taking screenshot");
            var root = Gdk.get_default_root_window ();
            var screenshot = Gdk.pixbuf_get_from_window (root, 0, 0, root.get_width (), root.get_height ());
            try
            {
                screenshot.save ("Screenshot.png", "png", null);
            }
            catch (Error e)
            {
                warning ("Failed to save screenshot: %s", e.message);
            }
            return true;
        case Gdk.Key.z:
            if (ArcticaGreeter.singleton.test_mode && (event.state & Gdk.ModifierType.MOD1_MASK) != 0)
            {
                show_shutdown_dialog (ShutdownDialogType.SHUTDOWN);
                return true;
            }
            break;
        case Gdk.Key.Z:
            if (ArcticaGreeter.singleton.test_mode && (event.state & Gdk.ModifierType.MOD1_MASK) != 0)
            {
                show_shutdown_dialog (ShutdownDialogType.RESTART);
                return true;
            }
            break;
        }

        return base.key_press_event (event);
    }

    public void set_keyboard_state ()
    {
        menubar.set_keyboard_state ();
    }

    public void show_shutdown_dialog (ShutdownDialogType type)
    {
        if (shutdown_dialog != null)
            shutdown_dialog.destroy ();

        /* Stop input to login box */
        login_box.sensitive = false;

        shutdown_dialog = new ShutdownDialog (type, background);
        shutdown_dialog.closed.connect (close_shutdown_dialog);
        background.add (shutdown_dialog);
        move_to_monitor (active_monitor);
        shutdown_dialog.visible = true;
    }

    public void close_shutdown_dialog ()
    {
        if (shutdown_dialog == null)
            return;

        shutdown_dialog.destroy ();
        shutdown_dialog = null;

        login_box.sensitive = true;
    }
}
