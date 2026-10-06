namespace Singularity.Apps.Help {

    public class MallardInfo : Object {
        public string id;
        public string path;
        public string title = "";
        public string description = "";
        public string type = "topic";
        public Gee.ArrayList<string> guides = new Gee.ArrayList<string> ();
        public string sort = "";
    }

    public class Mallard : Object {
        private static Xml.Node* child (Xml.Node* node, string name) {
            for (Xml.Node* c = node->children; c != null; c = c->next) {
                if (c->type == Xml.ElementType.ELEMENT_NODE && c->name == name) return c;
            }
            return null;
        }

        private static string text_of (Xml.Node* node) {
            if (node == null) return "";
            var sb = new StringBuilder ();
            collect_text (node, sb);
            return squash (sb.str);
        }

        private static void collect_text (Xml.Node* node, StringBuilder sb) {
            for (Xml.Node* c = node->children; c != null; c = c->next) {
                if (c->type == Xml.ElementType.TEXT_NODE || c->type == Xml.ElementType.CDATA_SECTION_NODE) sb.append (c->content);
                else if (c->type == Xml.ElementType.ELEMENT_NODE && c->name != "media") collect_text (c, sb);
            }
        }

        private static string squash (string s) {
            var sb = new StringBuilder ();
            bool space = false;
            unichar ch;
            int idx = 0;
            while (s.get_next_char (ref idx, out ch)) {
                if (ch.isspace ()) {
                    space = true;
                    continue;
                }
                if (space && sb.len > 0) sb.append_c (' ');
                space = false;
                sb.append_unichar (ch);
            }
            return sb.str;
        }

        public static MallardInfo? read_info (string path) {
            Xml.Doc* doc = Xml.Parser.read_file (path, null, Xml.ParserOption.NONET | Xml.ParserOption.NOERROR | Xml.ParserOption.NOWARNING);
            if (doc == null) return null;
            var root = doc->get_root_element ();
            if (root == null || root->name != "page") {
                delete doc;
                return null;
            }
            var info = new MallardInfo ();
            info.path = path;
            info.id = root->get_prop ("id") ?? Path.get_basename (path).replace (".page", "");
            info.type = root->get_prop ("type") ?? "topic";
            var i = child (root, "info");
            if (i != null) {
                for (Xml.Node* c = i->children; c != null; c = c->next) {
                    if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                    if (c->name == "link" && c->get_prop ("type") == "guide") {
                        string? xref = c->get_prop ("xref");
                        if (xref != null) info.guides.add (xref);
                    } else if (c->name == "desc") {
                        info.description = text_of (c);
                    } else if (c->name == "title" && c->get_prop ("type") == "sort") {
                        info.sort = text_of (c);
                    }
                }
            }
            info.title = text_of (child (root, "title"));
            delete doc;
            return info;
        }

        private static string inline (Xml.Node* node) {
            var sb = new StringBuilder ();
            for (Xml.Node* c = node->children; c != null; c = c->next) render (c, sb);
            return squash_markup (sb.str);
        }

        private static void render (Xml.Node* c, StringBuilder sb) {
            if (c->type == Xml.ElementType.TEXT_NODE || c->type == Xml.ElementType.CDATA_SECTION_NODE) {
                sb.append (Markup.escape_text (c->content));
                return;
            }
            if (c->type != Xml.ElementType.ELEMENT_NODE) return;
            string inner = inline (c);
            switch (c->name) {
                case "em":
                    sb.append ("<i>" + inner + "</i>");
                    break;
                case "guiseq":
                case "keyseq":
                    string sep = c->name == "guiseq" ? " %s ".printf (((unichar) 0x25B8).to_string ()) : (c->get_prop ("type") == "sequence" ? " " : "+");
                    string[] parts = {};
                    for (Xml.Node* k = c->children; k != null; k = k->next) {
                        if (k->type == Xml.ElementType.ELEMENT_NODE) {
                            var part = new StringBuilder ();
                            render (k, part);
                            parts += squash_markup (part.str);
                        } else if (k->type == Xml.ElementType.TEXT_NODE && k->content.strip () != "" && k->content.strip () != "+") {
                            parts += Markup.escape_text (k->content.strip ());
                        }
                    }
                    sb.append (string.joinv (sep, parts));
                    break;
                case "key":
                    sb.append ("<span font_family=\"monospace\" weight=\"bold\">" + inner + "</span>");
                    break;
                case "gui":
                case "app":
                case "cmd":
                    sb.append ("<b>" + inner + "</b>");
                    break;
                case "code":
                case "file":
                case "input":
                case "output":
                case "var":
                case "sys":
                    sb.append ("<tt>" + inner + "</tt>");
                    break;
                case "link":
                    string? href = c->get_prop ("href");
                    string? xref = c->get_prop ("xref");
                    string target = href ?? ("page:" + (xref ?? ""));
                    string label = inner.strip () != "" ? inner : Markup.escape_text (xref ?? href ?? "");
                    sb.append ("<a href=\"%s\">%s</a>".printf (Markup.escape_text (target), label));
                    break;
                case "media":
                    break;
                default:
                    sb.append (inner);
                    break;
            }
        }

        private static string squash_markup (string s) {
            return squash (s);
        }

        private static void blocks (Xml.Node* node, Page page, Gee.List<MallardInfo> book, string page_id, string? section) {
            for (Xml.Node* c = node->children; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                switch (c->name) {
                    case "p":
                        string p = inline (c);
                        if (p.strip () != "") page.blocks.add (new Block (BlockKind.PARAGRAPH, p));
                        break;
                    case "title":
                        if (node->name == "section") {
                            var h = new Block (BlockKind.HEADING, inline (c));
                            h.level = 2;
                            page.blocks.add (h);
                        }
                        break;
                    case "section":
                        string? sid = c->get_prop ("id");
                        blocks (c, page, book, page_id, sid);
                        break;
                    case "list":
                    case "steps":
                    case "terms":
                        var b = new Block (c->name == "steps" ? BlockKind.STEPS : BlockKind.BULLETS);
                        string[] items = {};
                        for (Xml.Node* it = c->children; it != null; it = it->next) {
                            if (it->type != Xml.ElementType.ELEMENT_NODE || it->name != "item") continue;
                            var sb = new StringBuilder ();
                            for (Xml.Node* part = it->children; part != null; part = part->next) {
                                if (part->type != Xml.ElementType.ELEMENT_NODE) continue;
                                string t = inline (part);
                                if (t.strip () == "") continue;
                                if (sb.len > 0) sb.append (part->name == "title" ? "\n" : " ");
                                sb.append (part->name == "title" ? "<b>" + t + "</b>" : t);
                            }
                            if (sb.len > 0) items += sb.str;
                        }
                        b.items = items;
                        if (items.length > 0) page.blocks.add (b);
                        break;
                    case "note":
                        string? style = c->get_prop ("style");
                        var nb = new StringBuilder ();
                        for (Xml.Node* part = c->children; part != null; part = part->next) {
                            if (part->type != Xml.ElementType.ELEMENT_NODE) continue;
                            string t = inline (part);
                            if (t.strip () == "") continue;
                            if (nb.len > 0) nb.append ("\n\n");
                            nb.append (t);
                        }
                        page.blocks.add (new Block (style != null && (style.contains ("warning") || style.contains ("important")) ? BlockKind.WARNING : BlockKind.NOTE, nb.str));
                        break;
                    case "code":
                    case "screen":
                        page.blocks.add (new Block (BlockKind.CODE, Markup.escape_text (text_raw (c))));
                        break;
                    case "media":
                        string? src = c->get_prop ("src");
                        if (src != null && c->get_prop ("type") == "image") {
                            var img = new Block (BlockKind.IMAGE, src);
                            img.items = { "" };
                            page.blocks.add (img);
                        }
                        break;
                    case "links":
                        string? type = c->get_prop ("type");
                        if (type == "topic") add_topics (page, book, page_id, section);
                        else if (type == "seealso") add_seealso (c, page, book);
                        break;
                    case "table":
                    case "div":
                    case "synopsis":
                        blocks (c, page, book, page_id, section);
                        break;
                    default:
                        break;
                }
            }
        }

        private static string text_raw (Xml.Node* node) {
            var sb = new StringBuilder ();
            collect_text (node, sb);
            return sb.str.strip ();
        }

        private static void add_topics (Page page, Gee.List<MallardInfo> book, string page_id, string? section) {
            var b = new Block (BlockKind.LINKS);
            string want = section != null ? page_id + "#" + section : page_id;
            var found = new Gee.ArrayList<MallardInfo> ();
            foreach (var info in book) {
                foreach (string g in info.guides) {
                    if (g == want) {
                        found.add (info);
                        break;
                    }
                }
            }
            found.sort ((x, y) => (x.sort != "" ? x.sort : x.title).collate (y.sort != "" ? y.sort : y.title));
            foreach (var info in found) b.links.add (new Link (info.title, info.description, "page:" + info.id));
            if (b.links.size > 0) page.blocks.add (b);
        }

        private static void add_seealso (Xml.Node* node, Page page, Gee.List<MallardInfo> book) {
            var b = new Block (BlockKind.LINKS);
            foreach (var info in book) {
                foreach (string g in info.guides) {
                    if (g == page.id) b.links.add (new Link (info.title, info.description, "page:" + info.id));
                }
            }
            if (b.links.size == 0) return;
            var h = new Block (BlockKind.HEADING, _("See Also"));
            h.level = 2;
            page.blocks.add (h);
            page.blocks.add (b);
        }

        public static Page? load (MallardInfo info, Gee.List<MallardInfo> book) {
            Xml.Doc* doc = Xml.Parser.read_file (info.path, null, Xml.ParserOption.NONET | Xml.ParserOption.NOERROR | Xml.ParserOption.NOWARNING);
            if (doc == null) return null;
            var root = doc->get_root_element ();
            var page = new Page ();
            page.id = info.id;
            page.title = info.title;
            page.description = info.description;
            page.base_dir = Path.get_dirname (info.path);
            blocks (root, page, book, info.id, null);
            if (info.type == "guide") {
                bool has_links = false;
                foreach (var b in page.blocks) if (b.kind == BlockKind.LINKS) has_links = true;
                if (!has_links) add_topics (page, book, info.id, null);
            }
            delete doc;
            return page;
        }
    }

    public class Manual : Object {
        public static async Page? load (string name, string section) {
            try {
                string[] env = Environ.get ();
                env = Environ.set_variable (env, "MANWIDTH", "2000");
                env = Environ.set_variable (env, "MAN_KEEP_FORMATTING", "1");
                env = Environ.set_variable (env, "GROFF_NO_SGR", "1");
                var launcher = new SubprocessLauncher (SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE);
                launcher.set_environ (env);
                string[] argv = { "man", "-P", "cat" };
                if (section != "") argv += section;
                argv += name;
                var proc = launcher.spawnv (argv);
                string output;
                yield proc.communicate_utf8_async (null, null, out output, null);
                if (!proc.get_successful () || output == null || output.strip () == "") return null;
                return parse (output, name, section);
            } catch (Error e) {
                return null;
            }
        }

        public static Page parse (string output, string name, string section) {
            var page = new Page ();
            page.id = "man:" + name;
            page.title = section != "" ? "%s(%s)".printf (name, section) : name;
            var group = new Gee.ArrayList<ManLine> ();
            bool started = false;
            string current = "";
            foreach (string raw in output.split ("\n")) {
                var line = new ManLine (raw);
                if (line.blank) {
                    flush (page, group, current);
                    continue;
                }
                if (line.indent == 0) {
                    flush (page, group, current);
                    if (line.plain.contains ("(") || line.plain != line.plain.up ()) continue;
                    started = true;
                    current = line.plain.strip ();
                    string t = current.substring (0, 1) + current.substring (1).down ();
                    var h = new Block (BlockKind.HEADING, Markup.escape_text (t));
                    h.level = 2;
                    page.blocks.add (h);
                    continue;
                }
                if (!started) continue;
                if (line.indent < 7) {
                    flush (page, group, current);
                    var h = new Block (BlockKind.HEADING, line.markup (line.indent));
                    h.level = 3;
                    page.blocks.add (h);
                    continue;
                }
                group.add (line);
            }
            flush (page, group, current);
            if (page.blocks.size > 1 && page.blocks[0].kind == BlockKind.HEADING && page.blocks[1].kind == BlockKind.PARAGRAPH && page.blocks[0].markup == "Name") {
                page.description = Page.strip_markup (page.blocks[1].markup);
                int dash = page.description.index_of (" - ");
                if (dash > 0) page.description = page.description.substring (dash + 3);
                page.description = page.description.substring (0, 1).up () + page.description.substring (1);
                page.blocks.remove_at (1);
                page.blocks.remove_at (0);
            }
            return page;
        }

        private static string collapse (string s) {
            string r = s;
            while (r.contains ("  ")) r = r.replace ("  ", " ");
            return r;
        }

        private static void flush (Page page, Gee.ArrayList<ManLine> group, string section) {
            if (group.size == 0) return;
            Block? last = page.blocks.size > 0 ? page.blocks[page.blocks.size - 1] : null;
            int base_indent = group[0].indent;
            bool synopsis = section == "SYNOPSIS";

            var first = group[0];
            string tag = first.text (7, 12).strip ();
            if (!synopsis && base_indent == 7 && group.size == 1 && first.at (12) == ' ' && first.at (13) == ' ' && first.at (14) != ' ' && first.at (14) != 0 && tag != "" && !tag.contains (" ")) {
                var term = new Block (BlockKind.TERM, first.markup (7, 12).strip ());
                term.items = { collapse (first.markup (14)) };
                page.blocks.add (term);
                group.clear ();
                return;
            }

            int deeper = -1;
            for (int i = 1; i < group.size; i++) {
                if (group[i].indent > base_indent) {
                    deeper = i;
                    break;
                }
            }
            if (!synopsis && base_indent == 7 && deeper > 0) {
                string[] names = {};
                for (int i = 0; i < deeper; i++) names += group[i].markup (7).strip ();
                var term = new Block (BlockKind.TERM, string.joinv ("\n", names));
                string[] desc = {};
                for (int i = deeper; i < group.size; i++) desc += collapse (group[i].markup (group[i].indent));
                term.items = { string.joinv ("\n", desc) };
                page.blocks.add (term);
                group.clear ();
                return;
            }

            string[] texts = {};
            foreach (var l in group) texts += l.markup (base_indent);
            string text = collapse (string.joinv ("\n", texts));

            if (!synopsis && base_indent > 7 && last != null && last.kind == BlockKind.TERM && group.size == 1) {
                string[] items = last.items;
                items += text;
                last.items = items;
            } else if (synopsis || base_indent > 7) {
                string plain_text = "";
                foreach (var l in group) plain_text += (plain_text != "" ? "\n" : "") + l.text (base_indent);
                if (last != null && last.kind == BlockKind.CODE) last.markup += "\n" + Markup.escape_text (plain_text);
                else page.blocks.add (new Block (BlockKind.CODE, Markup.escape_text (plain_text)));
            } else {
                page.blocks.add (new Block (BlockKind.PARAGRAPH, text));
            }
            group.clear ();
        }

        private static int rank (string line, string q) {
            int open = line.index_of (" (");
            string name = (open > 0 ? line.substring (0, open) : line).casefold ();
            int close = line.index_of (")", open);
            string section = open > 0 && close > open ? line.substring (open + 2, close - open - 2) : "";
            int r = 3;
            if (name == q) r = 0;
            else if (name.has_prefix (q)) r = 1;
            else if (name.contains (q)) r = 2;
            bool user = section.has_prefix ("1") || section.has_prefix ("8") || section.has_prefix ("5");
            return r * 2 + (user ? 0 : 1);
        }

        public static async Gee.List<string> search (string query) {
            var list = new Gee.ArrayList<string> ();
            if (query.strip ().length < 2) return list;
            try {
                var proc = new Subprocess.newv ({ "apropos", "--", query.strip () }, SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE);
                string output;
                yield proc.communicate_utf8_async (null, null, out output, null);
                string q = query.strip ().casefold ();
                var ranked = new Gee.ArrayList<string> ();
                foreach (string line in (output ?? "").split ("\n")) {
                    if (line.strip () != "") ranked.add (line.strip ());
                }
                ranked.sort ((a, b) => {
                    int ra = rank (a, q), rb = rank (b, q);
                    return ra != rb ? ra - rb : a.collate (b);
                });
                foreach (string line in ranked) {
                    list.add (line);
                    if (list.size >= 30) break;
                }
            } catch (Error e) {
            }
            return list;
        }
    }

    public class ManLine : Object {
        private enum Style {
            PLAIN,
            BOLD,
            ITALIC
        }

        public string plain;
        public int indent = 0;
        public bool blank;
        private unichar[] chars = {};
        private Style[] styles = {};

        public ManLine (string raw) {
            int i = 0;
            unichar c;
            while (raw.get_next_char (ref i, out c)) {
                if (c == '\b') {
                    if (chars.length == 0) continue;
                    unichar prev = chars[chars.length - 1];
                    unichar next;
                    if (!raw.get_next_char (ref i, out next)) break;
                    Style st = prev == '_' && next != '_' ? Style.ITALIC : Style.BOLD;
                    chars[chars.length - 1] = next;
                    styles[styles.length - 1] = st;
                    continue;
                }
                if (c == '\r') continue;
                chars += c;
                styles += Style.PLAIN;
            }
            var sb = new StringBuilder ();
            foreach (unichar u in chars) sb.append_unichar (u);
            plain = sb.str.chomp ();
            blank = plain.strip () == "";
            while (indent < chars.length && chars[indent] == ' ') indent++;
        }

        public unichar at (int i) {
            return i < chars.length ? chars[i] : 0;
        }

        public string text (int from, int to = -1) {
            int end = to < 0 ? chars.length : int.min (to, chars.length);
            var sb = new StringBuilder ();
            for (int i = from; i < end; i++) sb.append_unichar (chars[i]);
            return sb.str.chomp ();
        }

        public string markup (int from, int to = -1) {
            int end = to < 0 ? chars.length : int.min (to, chars.length);
            var sb = new StringBuilder ();
            Style open = Style.PLAIN;
            for (int i = from; i < end; i++) {
                Style st = styles[i];
                if (chars[i] == ' ') {
                    int j = i;
                    while (j < end && chars[j] == ' ') j++;
                    st = j < end && styles[j] == open ? open : Style.PLAIN;
                }
                if (st != open) {
                    if (open == Style.BOLD) sb.append ("</b>");
                    else if (open == Style.ITALIC) sb.append ("</i>");
                    if (st == Style.BOLD) sb.append ("<b>");
                    else if (st == Style.ITALIC) sb.append ("<i>");
                    open = st;
                }
                sb.append (Markup.escape_text (chars[i].to_string ()));
            }
            if (open == Style.BOLD) sb.append ("</b>");
            else if (open == Style.ITALIC) sb.append ("</i>");
            return sb.str.chomp ();
        }
    }
}
