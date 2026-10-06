using Gtk;

namespace Singularity.Apps.Help {

    public class HelpApp : Singularity.Application {

        public HelpApp () {
            Object (application_id: "dev.sinty.help", flags: ApplicationFlags.HANDLES_OPEN);
        }

        protected override void startup () {
            base.startup ();
            var provider = new CssProvider ();
            provider.load_from_string (CSS);
            StyleContext.add_provider_for_display (Gdk.Display.get_default (), provider, STYLE_PROVIDER_PRIORITY_USER + 1);
            var menu = new GLib.Menu ();
            var file_menu = new GLib.Menu ();
            file_menu.append (_("Close Window"), "win.close");
            file_menu.append (_("Quit"), "app.quit");
            menu.append_submenu (_("File"), file_menu);
            var edit_menu = new GLib.Menu ();
            var e1 = new GLib.Menu ();
            e1.append (_("Find"), "win.find");
            edit_menu.append_section (null, e1);
            var e2 = new GLib.Menu ();
            e2.append (_("Settings"), "app.settings");
            edit_menu.append_section (null, e2);
            menu.append_submenu (_("Edit"), edit_menu);
            var view_menu = new GLib.Menu ();
            view_menu.append (_("Show Sidebar"), "win.sidebar");
            menu.append_submenu (_("View"), view_menu);
            var go_menu = new GLib.Menu ();
            var g1 = new GLib.Menu ();
            g1.append (_("Back"), "win.back");
            g1.append (_("Forward"), "win.forward");
            g1.append (_("Home"), "win.home");
            go_menu.append_section (null, g1);
            if (Environment.find_program_in_path ("man") != null) {
                var g2 = new GLib.Menu ();
                g2.append (_("Command Manuals"), "win.manuals");
                go_menu.append_section (null, g2);
            }
            menu.append_submenu (_("Go"), go_menu);
            set_menubar (menu);
            var quit_action = new SimpleAction ("quit", null);
            quit_action.activate.connect (() => quit ());
            add_action (quit_action);
            var settings_action = new SimpleAction ("settings", null);
            settings_action.activate.connect (() => {
                try {
                    Singularity.Shell.ShellService shell = Bus.get_proxy_sync (BusType.SESSION, "dev.sinty.desktop", "/dev/sinty/Shell");
                    shell.open_app_settings ("dev.sinty.help");
                } catch (Error e) {
                    warning ("Failed to open settings: %s", e.message);
                }
            });
            add_action (settings_action);
            set_accels_for_action ("app.quit", { "<Control>q" });
            set_accels_for_action ("app.settings", { "<Control>comma" });
            set_accels_for_action ("win.close", { "<Control>w" });
            set_accels_for_action ("win.find", { "<Control>f" });
            set_accels_for_action ("win.sidebar", { "F9" });
            set_accels_for_action ("win.back", { "<Alt>Left" });
            set_accels_for_action ("win.forward", { "<Alt>Right" });
            set_accels_for_action ("win.home", { "<Alt>Home" });
        }

        private HelpWindow ensure_window () {
            var window = get_active_window () as HelpWindow;
            if (window == null) window = new HelpWindow (this);
            window.present ();
            return window;
        }

        public override void activate () {
            ensure_window ();
        }

        public void show_uri (string uri) {
            ensure_window ().open_uri (uri);
        }

        public void show_search (string text) {
            ensure_window ().search_for (text);
        }

        public override void open (File[] files, string hint) {
            var window = ensure_window ();
            foreach (var f in files) window.open_uri (f.get_uri ());
        }

        private const string CSS = """
.help-view {
    background-color: @view_bg_color;
}

.help-page {
    margin: 64px 32px 48px 32px;
}

.help-title {
    font-size: 30px;
    font-weight: 800;
    margin-bottom: 2px;
}

.help-lead {
    font-size: 16px;
    opacity: 0.7;
    margin-bottom: 8px;
}

.help-h2 {
    font-size: 20px;
    font-weight: 700;
    margin-top: 14px;
}

.help-h3 {
    font-size: 16px;
    font-weight: 700;
    margin-top: 8px;
}

.help-text {
    font-size: 15px;
    line-height: 1.5;
}

.help-crumb {
    padding: 2px 10px;
    margin-left: -10px;
    border-radius: 99px;
    font-weight: 600;
}

.help-crumb, .help-crumb label {
    color: @accent_color;
}

.help-bullet {
    min-width: 6px;
    min-height: 6px;
    border-radius: 99px;
    background-color: @accent_color;
    margin-top: 11px;
}

.help-step {
    min-width: 22px;
    min-height: 22px;
    border-radius: 99px;
    background-color: alpha(@accent_bg_color, 0.16);
    color: @accent_color;
    font-weight: 700;
    font-size: 13px;
}

.help-term-name {
    font-family: monospace;
    font-size: 14px;
}

.help-code-box {
    border-radius: 12px;
    background-color: alpha(@window_fg_color, 0.06);
}

.help-code {
    font-family: monospace;
    font-size: 13px;
    padding: 12px 14px;
}

.help-note,
.help-warning {
    padding: 14px 16px;
    border-radius: 14px;
}

.help-note {
    background-color: alpha(@accent_bg_color, 0.1);
}

.help-note image {
    color: @accent_color;
}

.help-warning {
    background-color: alpha(@warning_color, 0.14);
}

.help-warning image {
    color: @warning_color;
}

.help-links {
    border-radius: 14px;
    border: 1px solid alpha(@borders, 0.5);
}

.help-link-row {
    border-radius: 0;
    padding: 12px 16px;
}

.help-link-row + .help-link-row {
    border-top: 1px solid alpha(@borders, 0.4);
}

.help-link-row:hover {
    background-color: alpha(@accent_color, 0.08);
}

.help-link-title {
    font-weight: 600;
}

.help-image {
    border-radius: 12px;
}
""";
    }

    public static int main (string[] args) {
        Intl.setlocale (LocaleCategory.ALL, "");
        string locale_dir = "/usr/share/locale";
        try {
            string exe = FileUtils.read_link ("/proc/self/exe");
            locale_dir = Path.build_filename (Path.get_dirname (Path.get_dirname (exe)), "share", "locale");
        } catch (Error e) {
        }
        Intl.bindtextdomain ("singularity-help", locale_dir);
        Intl.bind_textdomain_codeset ("singularity-help", "UTF-8");
        Intl.textdomain ("singularity-help");
        var app = new HelpApp ();
        new HelpSearchProvider (app).export (app);
        return app.run (args);
    }
}
