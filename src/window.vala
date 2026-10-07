using Gtk;
using Singularity.Widgets;

namespace Singularity.Apps.Help {

    public class Location : Object {
        public string book;
        public string page;
        public string query;

        public Location (string book, string page, string query = "") {
            this.book = book;
            this.page = page;
            this.query = query;
        }
    }

    public delegate void ActionCallback ();

    public class HelpWindow : Singularity.Widgets.Window {
        private HelpApp app;
        private Library library;
        private AppSidebar sidebar;
        private Gee.HashMap<string, SidebarRow> rows = new Gee.HashMap<string, SidebarRow> ();
        private ScrolledWindow scroll;
        private Box column;
        private int search_serial = 0;
        private Button back_bubble;
        private Button forward_bubble;
        private Gee.ArrayList<Location> history = new Gee.ArrayList<Location> ();
        private int position = -1;
        private SearchBubble search;
        private uint search_source = 0;
        private Book? book = null;

        public HelpWindow (HelpApp app) {
            Object (application: app);
            this.app = app;
            set_default_size (1060, 760);
            set_title (_("Help"));

            sidebar = new AppSidebar (240);
            set_sidebar (sidebar);
            set_sidebar_visible (true);

            back_bubble = add_bubble_icon ("go-previous-symbolic", _("Back"), () => go (-1));
            forward_bubble = add_bubble_icon ("go-next-symbolic", _("Forward"), () => go (1));
            search = add_bubble_search (_("Search Help"), (text) => {
                if (search_source != 0) Source.remove (search_source);
                search_source = Timeout.add (250, () => {
                    search_source = 0;
                    if (text.strip () != "") navigate (new Location ("", "", text));
                    return Source.REMOVE;
                });
            });

            scroll = new ScrolledWindow ();
            scroll.hscrollbar_policy = PolicyType.NEVER;
            scroll.add_css_class ("help-view");
            column = new Box (Orientation.VERTICAL, 14);
            column.add_css_class ("help-page");
            scroll.child = new Clamp (column);
            set_content (scroll);

            add_win_action ("close", () => close ());
            add_win_action ("find", () => search.grab_focus_entry ());
            add_win_action ("back", () => go (-1));
            add_win_action ("forward", () => go (1));
            add_win_action ("home", () => go_home ());
            add_win_action ("manuals", () => navigate (new Location ("man:", "")));
            var sidebar_action = new SimpleAction.stateful ("sidebar", null, new Variant.boolean (true));
            sidebar_action.activate.connect (() => {
                set_sidebar_visible (!get_sidebar_visible ());
                sidebar_action.set_state (new Variant.boolean (get_sidebar_visible ()));
            });
            add_action (sidebar_action);

            library = Library.scan ();
            build_sidebar ();
            go_home ();
        }

        private void add_win_action (string name, owned ActionCallback callback) {
            var action = new SimpleAction (name, null);
            action.activate.connect (() => callback ());
            add_action (action);
        }

        private void go_home () {
            if (library.guides.size > 0) navigate (new Location (library.guides[0].id, ""));
            else if (library.apps.size > 0) navigate (new Location (library.apps[0].id, ""));
            else show_empty ();
        }

        private void build_sidebar () {
            if (library.guides.size > 0) {
                sidebar.box.append (new SidebarSectionLabel (_("Guides")));
                foreach (var b in library.guides) add_row (b);
            }
            if (library.apps.size > 0) {
                sidebar.box.append (new SidebarSectionLabel (_("Apps")));
                foreach (var b in library.apps) add_row (b);
            }
            if (Environment.find_program_in_path ("man") != null) {
                sidebar.box.append (new SidebarSectionLabel (_("Reference")));
                var row = new SidebarRow ("utilities-terminal-symbolic", _("Command Manuals"));
                row.clicked.connect (() => navigate (new Location ("man:", "")));
                rows["man:"] = row;
                sidebar.box.append (row);
            }
        }

        private void add_row (Book b) {
            var row = new SidebarRow (b.icon, b.title);
            row.tooltip_text = b.description != "" ? b.description : b.title;
            row.clicked.connect (() => navigate (new Location (b.id, "")));
            rows[b.id] = row;
            sidebar.box.append (row);
        }

        public void search_for (string text) {
            if (text.strip () != "") navigate (new Location ("", "", text));
        }

        public void open_uri (string uri) {
            if (uri.has_prefix ("help:")) {
                string rest = uri.substring (5);
                int slash = rest.index_of ("/");
                string b = slash >= 0 ? rest.substring (0, slash) : rest;
                string p = slash >= 0 ? rest.substring (slash + 1) : "";
                navigate (new Location (b, p));
            } else if (uri.has_prefix ("man:")) {
                navigate (new Location ("man:", uri.substring (4)));
            }
        }

        private void navigate (Location loc) {
            while (history.size > position + 1) history.remove_at (history.size - 1);
            if (loc.query != "" && position >= 0 && history[position].query != "") history[position] = loc;
            else {
                history.add (loc);
                position = history.size - 1;
            }
            show (loc);
        }

        private void go (int delta) {
            int target = position + delta;
            if (target < 0 || target >= history.size) return;
            position = target;
            show (history[position]);
        }

        private void sync_nav () {
            back_bubble.sensitive = position > 0;
            forward_bubble.sensitive = position < history.size - 1;
            ((SimpleAction) lookup_action ("back")).set_enabled (position > 0);
            ((SimpleAction) lookup_action ("forward")).set_enabled (position < history.size - 1);
        }

        private void clear () {
            Widget? child;
            while ((child = column.get_first_child ()) != null) column.remove (child);
            scroll.vadjustment.value = 0;
            search_serial++;
        }

        private void show (Location loc) {
            sync_nav ();
            foreach (var e in rows.entries) e.value.set_active (loc.query == "" && e.key == loc.book);
            if (loc.query != "") {
                show_search (loc.query);
                return;
            }
            if (loc.book == "man:") {
                show_manual.begin (loc.page);
                return;
            }
            book = library.find (loc.book);
            if (book == null) {
                show_message (_("Page Not Found"), _("This help topic is not installed."), "dialog-warning", _("Go to Start"), () => go_home ());
                return;
            }
            var page = book.page (loc.page);
            if (page == null) {
                show_message (_("Page Not Found"), _("This help topic is not installed."), "dialog-warning", _("Go to Start"), () => go_home ());
                return;
            }
            render (page, loc.page != "" && loc.page != book.start ? book.title : null);
        }

        private void show_empty () {
            clear ();
            var page = new WelcomePage ();
            page.is_section = true;
            page.embedded = true;
            page.vexpand = true;
            page.app_icon_name = "dev.sinty.help";
            page.title = _("No Help Installed");
            page.subtitle = _("Guides from your system and apps appear here once they are installed.");
            if (rows.has_key ("man:")) page.add_action ("text-x-script", _("Command Manuals"), _("The manual of every command-line program"), () => navigate (new Location ("man:", "")));
            page.add_action ("system-search", _("Search Help"), _("Look for a topic or a command"), () => search.grab_focus_entry ());
            column.append (page);
        }

        private void show_message (string title, string text, string icon, string action, owned ActionCallback callback) {
            clear ();
            var status = new StatusPage ();
            status.icon_name = icon;
            status.title = title;
            status.description = text;
            status.vexpand = true;
            ActionCallback cb = (owned) callback;
            var button = new Button.with_label (action);
            button.add_css_class ("pill");
            button.add_css_class ("suggested-action");
            button.halign = Align.CENTER;
            button.clicked.connect (() => cb ());
            status.child = button;
            column.append (status);
        }

        private Label label (string markup, string? css = null) {
            var l = new Label (markup);
            l.use_markup = true;
            l.wrap = true;
            l.wrap_mode = Pango.WrapMode.WORD_CHAR;
            l.xalign = 0;
            l.max_width_chars = 72;
            l.selectable = true;
            l.can_focus = false;
            if (css != null) l.add_css_class (css);
            l.activate_link.connect ((uri) => {
                follow (uri);
                return true;
            });
            return l;
        }

        private async void open_settings (string page) {
            try {
                var bus = yield GLib.Bus.get (BusType.SESSION);
                yield bus.call ("dev.sinty.desktop", "/dev/sinty/Shell", "dev.sinty.Shell", "OpenSettings",
                    new Variant ("(s)", page), null, DBusCallFlags.NONE, 5000);
            } catch (Error e) {
                warning ("Help: could not open Settings > %s: %s", page, e.message);
            }
        }

        private void follow (string uri) {
            if (uri.has_prefix ("http://") || uri.has_prefix ("https://") || uri.has_prefix ("mailto:")) {
                new UriLauncher (uri).launch.begin (this, null);
                return;
            }
            if (uri.has_prefix ("settings:")) {
                open_settings.begin (uri.substring (9));
                return;
            }
            if (uri.has_prefix ("help:") || uri.has_prefix ("man:")) {
                open_uri (uri);
                return;
            }
            string target = uri.has_prefix ("page:") ? uri.substring (5) : uri;
            if (target.has_prefix ("#")) return;
            if (book != null) navigate (new Location (book.id, target));
        }

        private void render (Page page, string? crumb) {
            clear ();
            if (crumb != null) {
                var c = new Button.with_label (crumb);
                c.add_css_class ("flat");
                c.add_css_class ("help-crumb");
                c.halign = Align.START;
                c.clicked.connect (() => navigate (new Location (book.id, "")));
                column.append (c);
            }
            column.append (label (Markup.escape_text (page.title), "help-title"));
            if (page.description != "") column.append (label (Markup.escape_text (page.description), "help-lead"));
            foreach (var b in page.blocks) {
                var w = block (b, page);
                if (w != null) column.append (w);
            }
        }

        private Widget? block (Block b, Page page) {
            switch (b.kind) {
                case BlockKind.HEADING:
                    return label (b.markup, b.level <= 2 ? "help-h2" : "help-h3");
                case BlockKind.PARAGRAPH:
                    return label (b.markup, "help-text");
                case BlockKind.BULLETS:
                case BlockKind.STEPS:
                    var box = new Box (Orientation.VERTICAL, 8);
                    for (int i = 0; i < b.items.length; i++) {
                        var row = new Box (Orientation.HORIZONTAL, 12);
                        Widget mark;
                        if (b.kind == BlockKind.STEPS) {
                            mark = new Label ((i + 1).to_string ());
                            mark.add_css_class ("help-step");
                        } else {
                            var dot = new Box (Orientation.HORIZONTAL, 0);
                            dot.set_size_request (6, 6);
                            dot.add_css_class ("help-bullet");
                            mark = dot;
                        }
                        mark.valign = Align.START;
                        mark.halign = Align.CENTER;
                        mark.hexpand = true;
                        var slot = new Box (Orientation.HORIZONTAL, 0);
                        slot.set_size_request (24, -1);
                        slot.hexpand = false;
                        slot.append (mark);
                        row.append (slot);
                        var text = label (b.items[i], "help-text");
                        text.hexpand = true;
                        row.append (text);
                        box.append (row);
                    }
                    return box;
                case BlockKind.CODE:
                    var code = label (b.markup, "help-code");
                    code.wrap = false;
                    var sw = new ScrolledWindow ();
                    sw.vscrollbar_policy = PolicyType.NEVER;
                    sw.propagate_natural_height = true;
                    sw.child = code;
                    sw.add_css_class ("help-code-box");
                    return sw;
                case BlockKind.NOTE:
                case BlockKind.WARNING:
                    var note = new Box (Orientation.HORIZONTAL, 12);
                    note.add_css_class (b.kind == BlockKind.WARNING ? "help-warning" : "help-note");
                    var icon = new Image.from_icon_name (b.kind == BlockKind.WARNING ? "dialog-warning-symbolic" : "dialog-information-symbolic");
                    icon.valign = Align.START;
                    note.append (icon);
                    var t = label (b.markup, "help-text");
                    t.hexpand = true;
                    note.append (t);
                    return note;
                case BlockKind.LINKS:
                    var list = new Box (Orientation.VERTICAL, 0);
                    list.add_css_class ("help-links");
                    list.overflow = Overflow.HIDDEN;
                    foreach (var link in b.links) {
                        var btn = new Button ();
                        btn.add_css_class ("flat");
                        btn.add_css_class ("help-link-row");
                        var inner = new Box (Orientation.HORIZONTAL, 12);
                        var texts = new Box (Orientation.VERTICAL, 2);
                        texts.hexpand = true;
                        var tl = new Label (link.title);
                        tl.xalign = 0;
                        tl.wrap = true;
                        tl.add_css_class ("help-link-title");
                        texts.append (tl);
                        if (link.description != "") {
                            var dl = new Label (link.description);
                            dl.xalign = 0;
                            dl.wrap = true;
                            dl.add_css_class ("dim-label");
                            dl.add_css_class ("caption");
                            texts.append (dl);
                        }
                        inner.append (texts);
                        var arrow = new Image.from_icon_name ("go-next-symbolic");
                        arrow.add_css_class ("dim-label");
                        inner.append (arrow);
                        btn.child = inner;
                        string target = link.target;
                        btn.clicked.connect (() => follow (target));
                        list.append (btn);
                    }
                    return list;
                case BlockKind.IMAGE:
                    string path = Path.is_absolute (b.markup) ? b.markup : Path.build_filename (page.base_dir, b.markup);
                    if (!FileUtils.test (path, FileTest.EXISTS)) return null;
                    var pic = new Picture.for_filename (path);
                    pic.can_shrink = true;
                    pic.content_fit = ContentFit.CONTAIN;
                    pic.halign = Align.START;
                    pic.add_css_class ("help-image");
                    if (b.items.length > 0 && b.items[0] != "") pic.alternative_text = b.items[0];
                    return pic;
                case BlockKind.RULE:
                    return new Separator (Orientation.HORIZONTAL);
                case BlockKind.TERM:
                    var term = new Box (Orientation.VERTICAL, 4);
                    term.add_css_class ("help-term");
                    term.append (label (b.markup, "help-term-name"));
                    foreach (string item in b.items) {
                        var d = label (item, "help-text");
                        d.margin_start = 24;
                        term.append (d);
                    }
                    return term;
            }
            return null;
        }

        private void show_search (string query) {
            clear ();
            var hits = library.search (query);
            if (hits.size == 0) hits = library.search_terms ({ query });
            if (hits.size == 0) {
                var status = new StatusPage ();
                status.icon_name = "system-search";
                status.title = _("No Help Pages Found");
                status.description = _("Try other words, or look in the command manuals.");
                var clear_search = new Button.with_label (_("Clear Search"));
                clear_search.halign = Align.CENTER;
                clear_search.add_css_class ("pill");
                clear_search.add_css_class ("suggested-action");
                clear_search.clicked.connect (() => {
                    search.clear ();
                    if (position > 0) go (-1);
                });
                status.child = clear_search;
                column.append (status);
            } else {
                column.append (label (Markup.escape_text (_("Results for \"%s\"").printf (query.strip ())), "help-title"));
                var b = new Block (BlockKind.LINKS);
                int n = 0;
                foreach (var h in hits) {
                    if (n++ >= 40) break;
                    string desc = h.book.title + (h.snippet != "" ? " · " + h.snippet : "");
                    b.links.add (new Link (h.title, desc, "help:" + h.book.id + "/" + h.page));
                }
                column.append (block (b, new Page ()));
            }
            if (Environment.find_program_in_path ("apropos") != null) find_manuals.begin (query);
        }

        private async void find_manuals (string query) {
            int serial = ++search_serial;
            var found = yield Manual.search (query);
            if (serial != search_serial || found.size == 0) return;
            column.append (label (_("Command Manuals"), "help-h2"));
            var b = new Block (BlockKind.LINKS);
            foreach (string line in found) {
                int dash = line.index_of (" - ");
                string head = dash > 0 ? line.substring (0, dash).strip () : line;
                string desc = dash > 0 ? line.substring (dash + 3).strip () : "";
                b.links.add (new Link (head, desc, "man:" + head.replace (" ", "")));
            }
            column.append (block (b, new Page ()));
        }

        private async void show_manual (string what) {
            clear ();
            if (what == "") {
                column.append (label (_("Command Manuals"), "help-title"));
                column.append (label (_("Every command-line program on the system has a manual. Search for a command or a task in the search field, for example \"copy files\" or \"ls\"."), "help-lead"));
                return;
            }
            string name = what;
            string section = "";
            int open = what.index_of ("(");
            if (open > 0 && what.has_suffix (")")) {
                name = what.substring (0, open);
                section = what.substring (open + 1, what.length - open - 2);
            }
            var page = yield Manual.load (name, section);
            if (page == null) {
                show_message (_("No Manual"), _("There is no manual for \"%s\".").printf (name), "dialog-warning", _("All Command Manuals"), () => navigate (new Location ("man:", "")));
                return;
            }
            render (page, null);
        }
    }
}
