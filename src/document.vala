namespace Singularity.Apps.Help {

    public enum BlockKind {
        HEADING,
        PARAGRAPH,
        BULLETS,
        STEPS,
        CODE,
        NOTE,
        WARNING,
        LINKS,
        IMAGE,
        RULE,
        TERM
    }

    public class Link : Object {
        public string title;
        public string description;
        public string target;

        public Link (string title, string description, string target) {
            this.title = title;
            this.description = description;
            this.target = target;
        }
    }

    public class Block : Object {
        public BlockKind kind;
        public int level = 1;
        public string markup = "";
        public string[] items = {};
        public Gee.ArrayList<Link> links = new Gee.ArrayList<Link> ();

        public Block (BlockKind kind, string markup = "") {
            this.kind = kind;
            this.markup = markup;
        }
    }

    public class Page : Object {
        public string id = "";
        public string title = "";
        public string description = "";
        public string base_dir = "";
        public Gee.ArrayList<Block> blocks = new Gee.ArrayList<Block> ();

        public string plain_text () {
            var sb = new StringBuilder (title);
            foreach (var b in blocks) {
                sb.append (" ");
                sb.append (strip_markup (b.markup));
                foreach (string i in b.items) {
                    sb.append (" ");
                    sb.append (strip_markup (i));
                }
            }
            return sb.str;
        }

        public static string strip_markup (string text) {
            try {
                string plain;
                Pango.parse_markup (text, -1, 0, null, out plain, null);
                return plain;
            } catch (Error e) {
                return text;
            }
        }
    }

    public class Markdown : Object {
        private static string escape (string s) {
            return Markup.escape_text (s);
        }

        public static string? settings_page_for (string text) {
            if (!text.has_prefix ("Settings > ")) return null;
            string[] path = text.substring (11).split (" > ");
            string label = path[0].strip ();
            string row = path.length > 1 ? "#" + path[1].strip () : "";
            string[] labels = { "Network", "Sharing", "Apps", "Autostart", "Privacy", "Users", "Online Accounts", "Displays",
                "Region & Language", "Date & Time", "Desktop", "Sound", "Notifications", "Wellbeing", "Bluetooth",
                "Connected Devices", "Printers", "Keyboard", "Graphics Tablet", "Accessibility", "Plugins", "Power",
                "Performance", "Updates", "System", "Developer" };
            string[] pages = { "network", "sharing", "apps", "autostart", "privacy", "users", "accounts", "displays",
                "region", "datetime", "desktop", "sound", "notifications", "wellbeing", "bluetooth",
                "connected-devices", "printers", "keyboard", "tablet", "accessibility", "plugins", "power",
                "performance", "updates", "system", "developer" };
            for (int i = 0; i < labels.length; i++) {
                if (labels[i] == label) return pages[i] + row;
            }
            return null;
        }

        public static string inline (string text) {
            var sb = new StringBuilder ();
            int i = 0;
            int n = text.length;
            while (i < n) {
                char c = text[i];
                if (c == '`') {
                    int end = text.index_of_char ('`', i + 1);
                    if (end > i) {
                        sb.append ("<tt>" + escape (text.substring (i + 1, end - i - 1)) + "</tt>");
                        i = end + 1;
                        continue;
                    }
                }
                if (c == '*' && i + 1 < n && text[i + 1] == '*') {
                    int end = text.index_of ("**", i + 2);
                    if (end > i) {
                        string strong = text.substring (i + 2, end - i - 2);
                        string? page = settings_page_for (strong);
                        if (page != null) sb.append ("<a href=\"settings:%s\"><b>%s</b></a>".printf (escape (page), inline (strong)));
                        else sb.append ("<b>" + inline (strong) + "</b>");
                        i = end + 2;
                        continue;
                    }
                }
                if ((c == '*' || c == '_') && i + 1 < n && text[i + 1] != ' ') {
                    int end = text.index_of_char (c, i + 1);
                    if (end > i + 1) {
                        sb.append ("<i>" + inline (text.substring (i + 1, end - i - 1)) + "</i>");
                        i = end + 1;
                        continue;
                    }
                }
                if (c == '[') {
                    int close = text.index_of ("](", i);
                    int end = close > 0 ? text.index_of_char (')', close + 2) : -1;
                    if (close > i && end > close) {
                        string label = text.substring (i + 1, close - i - 1);
                        string href = text.substring (close + 2, end - close - 2);
                        sb.append ("<a href=\"%s\">%s</a>".printf (escape (href), inline (label)));
                        i = end + 1;
                        continue;
                    }
                }
                if (c == '<' && text.index_of (">", i) > i) {
                    int end = text.index_of (">", i);
                    string inner = text.substring (i + 1, end - i - 1);
                    if (inner.has_prefix ("kbd")) {
                        int close = text.index_of ("</kbd>", end);
                        if (close > end) {
                            sb.append ("<span font_family=\"monospace\" weight=\"bold\">%s</span>".printf (escape (text.substring (end + 1, close - end - 1))));
                            i = close + 6;
                            continue;
                        }
                    }
                }
                unichar u = text.get_char (i);
                sb.append (escape (u.to_string ()));
                i += u.to_string ().length;
            }
            return sb.str;
        }

        public static Page parse (string text, string id, string base_dir) {
            var page = new Page ();
            page.id = id;
            page.base_dir = base_dir;
            var lines = text.split ("\n");
            int i = 0;
            if (lines.length > 0 && lines[0].strip () == "---") {
                i = 1;
                while (i < lines.length && lines[i].strip () != "---") {
                    string l = lines[i];
                    int colon = l.index_of (":");
                    if (colon > 0) {
                        string key = l.substring (0, colon).strip ();
                        string val = l.substring (colon + 1).strip ();
                        if (key == "title") page.title = val;
                        else if (key == "description") page.description = val;
                    }
                    i++;
                }
                i++;
            }
            var para = new StringBuilder ();
            string[] list = {};
            BlockKind list_kind = BlockKind.BULLETS;
            Block? links = null;
            while (i <= lines.length) {
                string line = i < lines.length ? lines[i] : "";
                string t = line.strip ();
                bool is_list = t.has_prefix ("- ") || t.has_prefix ("* ") || is_numbered (t);
                bool is_link_item = is_list && (t.has_prefix ("- [") || t.has_prefix ("* [")) && t.has_suffix (")") && link_only (t.substring (2));
                if (i == lines.length || t == "" || t.has_prefix ("#") || t.has_prefix ("```") || t.has_prefix (">") || is_list || t == "---" || t.has_prefix ("![")) {
                    if (para.len > 0) {
                        page.blocks.add (new Block (BlockKind.PARAGRAPH, inline (para.str.strip ())));
                        para.truncate ();
                    }
                }
                if (i == lines.length) break;
                if (!is_list && list.length > 0) {
                    var b = new Block (list_kind);
                    b.items = list;
                    page.blocks.add (b);
                    list = {};
                }
                if (!is_link_item && links != null) {
                    page.blocks.add (links);
                    links = null;
                }
                if (t.has_prefix ("#")) {
                    int level = 0;
                    while (level < t.length && t[level] == '#') level++;
                    string title = t.substring (level).strip ();
                    if (level == 1 && page.title == "") page.title = title;
                    else {
                        var h = new Block (BlockKind.HEADING, inline (title));
                        h.level = level;
                        page.blocks.add (h);
                    }
                } else if (t.has_prefix ("```")) {
                    var code = new StringBuilder ();
                    i++;
                    while (i < lines.length && !lines[i].strip ().has_prefix ("```")) {
                        if (code.len > 0) code.append ("\n");
                        code.append (lines[i]);
                        i++;
                    }
                    page.blocks.add (new Block (BlockKind.CODE, escape (code.str)));
                } else if (t.has_prefix (">")) {
                    var note = new StringBuilder ();
                    BlockKind kind = BlockKind.NOTE;
                    while (i < lines.length && lines[i].strip ().has_prefix (">")) {
                        string l = lines[i].strip ().substring (1).strip ();
                        if (l.has_prefix ("[!WARNING]") || l.has_prefix ("[!CAUTION]")) {
                            kind = BlockKind.WARNING;
                            l = "";
                        } else if (l.has_prefix ("[!")) {
                            l = "";
                        }
                        if (l != "") {
                            if (note.len > 0) note.append (" ");
                            note.append (l);
                        }
                        i++;
                    }
                    i--;
                    page.blocks.add (new Block (kind, inline (note.str)));
                } else if (t == "---") {
                    page.blocks.add (new Block (BlockKind.RULE));
                } else if (t.has_prefix ("![")) {
                    int close = t.index_of ("](");
                    int end = t.last_index_of (")");
                    if (close > 0 && end > close) {
                        var img = new Block (BlockKind.IMAGE, t.substring (close + 2, end - close - 2));
                        img.items = { t.substring (2, close - 2) };
                        page.blocks.add (img);
                    }
                } else if (is_link_item) {
                    if (links == null) links = new Block (BlockKind.LINKS);
                    string item = t.substring (2);
                    int close = item.index_of ("](");
                    string label = item.substring (1, close - 1);
                    string href = item.substring (close + 2, item.length - close - 3);
                    int dash = label.index_of (" -- ");
                    string desc = "";
                    if (dash > 0) {
                        desc = label.substring (dash + 4);
                        label = label.substring (0, dash);
                    }
                    links.links.add (new Link (label, desc, href));
                } else if (is_list) {
                    BlockKind kind = is_numbered (t) ? BlockKind.STEPS : BlockKind.BULLETS;
                    if (list.length > 0 && kind != list_kind) {
                        var b = new Block (list_kind);
                        b.items = list;
                        page.blocks.add (b);
                        list = {};
                    }
                    list_kind = kind;
                    string content = kind == BlockKind.STEPS ? t.substring (t.index_of (".") + 1).strip () : t.substring (2);
                    list += inline (content);
                } else if (t != "") {
                    if (para.len > 0) para.append (" ");
                    para.append (t);
                }
                i++;
            }
            if (list.length > 0) {
                var b = new Block (list_kind);
                b.items = list;
                page.blocks.add (b);
            }
            if (links != null) page.blocks.add (links);
            return page;
        }

        private static bool is_numbered (string t) {
            int d = 0;
            while (d < t.length && t[d].isdigit ()) d++;
            return d > 0 && d + 1 < t.length && t[d] == '.' && t[d + 1] == ' ';
        }

        private static bool link_only (string item) {
            return item.has_prefix ("[") && item.index_of ("](") > 0 && item.has_suffix (")") && item.index_of ("](") == item.last_index_of ("](");
        }
    }
}
