namespace Singularity.Apps.Help {

    public enum BookKind {
        GUIDE,
        MALLARD
    }

    public class Book : Object {
        public string id;
        public BookKind kind;
        public string dir;
        public string title = "";
        public string description = "";
        public string icon = "help-browser-symbolic";
        public int order = 100;
        public string start = "index";
        private Gee.ArrayList<MallardInfo>? mallard = null;
        private Gee.HashMap<string, Page> cache = new Gee.HashMap<string, Page> ();

        public Gee.List<MallardInfo> mallard_pages () {
            if (mallard == null) {
                mallard = new Gee.ArrayList<MallardInfo> ();
                try {
                    var d = Dir.open (dir);
                    string? name;
                    while ((name = d.read_name ()) != null) {
                        if (!name.has_suffix (".page")) continue;
                        var info = Mallard.read_info (Path.build_filename (dir, name));
                        if (info != null) mallard.add (info);
                    }
                } catch (FileError e) {
                }
            }
            return mallard;
        }

        public string[] page_ids () {
            string[] ids = {};
            if (kind == BookKind.MALLARD) {
                foreach (var i in mallard_pages ()) ids += i.id;
                return ids;
            }
            var seen = new Gee.HashSet<string> ();
            foreach (string gd in guide_dirs ()) {
                try {
                    var d = Dir.open (gd);
                    string? name;
                    while ((name = d.read_name ()) != null) {
                        if (!name.has_suffix (".md")) continue;
                        string pid = name.substring (0, name.length - 3);
                        if (seen.add (pid)) ids += pid;
                    }
                } catch (FileError e) {
                }
            }
            return ids;
        }

        private string[] guide_dirs () {
            string fallback = Path.build_filename (Path.get_dirname (Path.get_dirname (dir)), "C", id);
            if (fallback == dir || !FileUtils.test (fallback, FileTest.IS_DIR)) return { dir };
            return { dir, fallback };
        }

        public Page? page (string id) {
            string key = id == "" ? start : id;
            if (key.has_suffix (".md")) key = key.substring (0, key.length - 3);
            if (key.has_suffix (".page")) key = key.substring (0, key.length - 5);
            int hash = key.index_of ("#");
            if (hash >= 0) key = key.substring (0, hash);
            if (cache.has_key (key)) return cache[key];
            Page? p = null;
            if (kind == BookKind.MALLARD) {
                foreach (var info in mallard_pages ()) {
                    if (info.id == key) {
                        p = Mallard.load (info, mallard_pages ());
                        break;
                    }
                }
            } else {
                foreach (string d in guide_dirs ()) {
                    string text;
                    try {
                        FileUtils.get_contents (Path.build_filename (d, key + ".md"), out text);
                        p = Markdown.parse (text, key, d);
                        break;
                    } catch (FileError e) {
                    }
                }
            }
            if (p != null) cache[key] = p;
            return p;
        }
    }

    public class Library : Object {
        public Gee.ArrayList<Book> guides = new Gee.ArrayList<Book> ();
        public Gee.ArrayList<Book> apps = new Gee.ArrayList<Book> ();

        public static string[] data_dirs () {
            string[] dirs = { Environment.get_user_data_dir () };
            foreach (string d in Environment.get_system_data_dirs ()) dirs += d;
            return dirs;
        }

        public static string[] languages () {
            string[] langs = {};
            foreach (unowned string l in Intl.get_language_names ()) {
                if (l.contains (".") || l.contains ("@")) continue;
                langs += l;
            }
            bool has_c = false;
            foreach (string l in langs) if (l == "C") has_c = true;
            if (!has_c) langs += "C";
            return langs;
        }

        public static Library scan (string[]? dirs = null, string[]? langs = null) {
            var lib = new Library ();
            var seen = new Gee.HashSet<string> ();
            var seen_apps = new Gee.HashSet<string> ();
            string[] search = dirs ?? data_dirs ();
            string[] order = langs ?? languages ();
            foreach (string lang in order) {
                foreach (string base_dir in search) {
                    string gdir = Path.build_filename (base_dir, "singularity", "help", lang);
                    foreach (string id in children (gdir)) {
                        if (seen.contains (id)) continue;
                        string dir = Path.build_filename (gdir, id);
                        if (!FileUtils.test (Path.build_filename (dir, "index.md"), FileTest.EXISTS)) continue;
                        seen.add (id);
                        lib.guides.add (read_guide (id, dir));
                    }
                    string mdir = Path.build_filename (base_dir, "help", lang);
                    foreach (string id in children (mdir)) {
                        if (seen_apps.contains (id)) continue;
                        string dir = Path.build_filename (mdir, id);
                        string index = Path.build_filename (dir, "index.page");
                        if (!FileUtils.test (index, FileTest.EXISTS)) continue;
                        seen_apps.add (id);
                        var book = new Book ();
                        book.id = id;
                        book.kind = BookKind.MALLARD;
                        book.dir = dir;
                        var info = Mallard.read_info (index);
                        book.title = info != null && info.title != "" ? info.title : id;
                        book.icon = app_icon (id);
                        lib.apps.add (book);
                    }
                }
            }
            lib.guides.sort ((a, b) => a.order != b.order ? a.order - b.order : a.title.collate (b.title));
            lib.apps.sort ((a, b) => a.title.collate (b.title));
            return lib;
        }

        private static string[] children (string dir) {
            string[] out_list = {};
            try {
                var d = Dir.open (dir);
                string? name;
                while ((name = d.read_name ()) != null) {
                    if (FileUtils.test (Path.build_filename (dir, name), FileTest.IS_DIR)) out_list += name;
                }
            } catch (FileError e) {
            }
            return out_list;
        }

        private static Book read_guide (string id, string dir) {
            var book = new Book ();
            book.id = id;
            book.kind = BookKind.GUIDE;
            book.dir = dir;
            book.title = id;
            var kf = new KeyFile ();
            try {
                kf.load_from_file (Path.build_filename (dir, "book.ini"), KeyFileFlags.NONE);
                book.title = kf.get_locale_string ("Book", "Title", null);
                if (kf.has_key ("Book", "Description")) book.description = kf.get_locale_string ("Book", "Description", null);
                if (kf.has_key ("Book", "Icon")) book.icon = kf.get_string ("Book", "Icon");
                if (kf.has_key ("Book", "Order")) book.order = kf.get_integer ("Book", "Order");
            } catch (Error e) {
                var page = book.page ("index");
                if (page != null && page.title != "") book.title = page.title;
            }
            return book;
        }

        private static string app_icon (string id) {
            string[] candidates = { id, "org.gnome." + id.substring (0, 1).up () + id.substring (1) };
            foreach (string c in candidates) {
                var info = new DesktopAppInfo (c + ".desktop");
                if (info != null && info.get_icon () != null) return info.get_icon ().to_string ();
            }
            return "help-browser-symbolic";
        }

        public Book? find (string id) {
            foreach (var b in guides) if (b.id == id) return b;
            foreach (var b in apps) if (b.id == id) return b;
            return null;
        }

        public class Hit : Object {
            public Book book;
            public string page;
            public string title;
            public string snippet;
            public int score;
        }

        public Gee.List<Hit> search (string query) {
            var hits = new Gee.ArrayList<Hit> ();
            string q = query.strip ().casefold ();
            if (q.length < 2) return hits;
            var all = new Gee.ArrayList<Book> ();
            all.add_all (guides);
            all.add_all (apps);
            foreach (var book in all) {
                if (book.kind == BookKind.MALLARD) {
                    foreach (var info in book.mallard_pages ()) {
                        int s = score (info.title, info.description, "", q);
                        if (s > 0) hits.add (make_hit (book, info.id, info.title, info.description, s));
                    }
                    continue;
                }
                foreach (string id in book.page_ids ()) {
                    var p = book.page (id);
                    if (p == null) continue;
                    string text = p.plain_text ();
                    int s = score (p.title, p.description, text, q);
                    if (s > 0) hits.add (make_hit (book, id, p.title, snippet (p.description != "" ? p.description : text, q), s));
                }
            }
            hits.sort ((a, b) => b.score - a.score);
            return hits;
        }

        public static string[] keywords (string[] terms) {
            string[] stop = { "a", "an", "the", "is", "are", "my", "i", "to", "of", "in", "on", "for", "and", "or", "not", "no", "does", "do", "doesn't", "dont", "don't", "can", "cannot", "can't", "how", "what", "why", "with", "it", "won't", "wont", "isn't" };
            string[] words = {};
            foreach (string t in terms) {
                foreach (string raw in t.casefold ().split_set (" \t,.;:!?\"()")) {
                    string w = raw.replace ("-", "").strip ();
                    if (w.char_count () < 2 || w in stop) continue;
                    foreach (string suffix in new string[] { "ing", "ed", "es", "s" }) {
                        if (w.has_suffix (suffix) && w.char_count () - suffix.length >= 4) {
                            w = w.substring (0, w.length - suffix.length);
                            break;
                        }
                    }
                    if (!(w in words)) words += w;
                }
            }
            return words;
        }

        public Gee.List<Hit> search_terms (string[] terms) {
            var hits = new Gee.ArrayList<Hit> ();
            string[] words = keywords (terms);
            if (words.length == 0) return hits;
            var all = new Gee.ArrayList<Book> ();
            all.add_all (guides);
            all.add_all (apps);
            foreach (var book in all) {
                if (book.kind == BookKind.MALLARD) {
                    foreach (var info in book.mallard_pages ()) {
                        int s = score_words (info.title, info.description, "", words);
                        if (s > 0) hits.add (make_hit (book, info.id, info.title, info.description, s));
                    }
                    continue;
                }
                foreach (string id in book.page_ids ()) {
                    var p = book.page (id);
                    if (p == null) continue;
                    string text = p.plain_text ();
                    int s = score_words (p.title, p.description, text, words);
                    if (s > 0) hits.add (make_hit (book, id, p.title, snippet (p.description != "" ? p.description : text, words[0]), s));
                }
            }
            hits.sort ((a, b) => b.score - a.score);
            if (hits.size > 0) {
                int best = hits[0].score / 1000;
                var kept = new Gee.ArrayList<Hit> ();
                foreach (var h in hits) if (h.score / 1000 == best) kept.add (h);
                return kept;
            }
            return hits;
        }

        private static int score_words (string title, string desc, string text, string[] words) {
            string t = title.casefold ().replace ("-", "");
            string d = desc.casefold ().replace ("-", "");
            string x = text.casefold ().replace ("-", "");
            int total = 0;
            int matched = 0;
            bool strong = false;
            foreach (string w in words) {
                int s = 0;
                if (word_match (t, w)) {
                    s += 40;
                    strong = true;
                }
                if (word_match (d, w)) {
                    s += 15;
                    strong = true;
                }
                if (word_match (x, w)) s += 5;
                if (s > 0) matched++;
                total += s;
            }
            if (matched == 0) return 0;
            if (!strong && matched < words.length) return 0;
            if (matched * 2 < words.length) return 0;
            return matched * 1000 + int.min (999, total);
        }

        private static Hit make_hit (Book book, string page, string title, string snippet, int score) {
            var h = new Hit ();
            h.book = book;
            h.page = page;
            h.title = title;
            h.snippet = snippet;
            h.score = score;
            return h;
        }

        private static int score (string title, string desc, string text, string q) {
            int s = 0;
            string t = title.casefold ();
            if (t == q) s += 100;
            else if (t.has_prefix (q)) s += 60;
            else if (word_match (t, q)) s += 40;
            if (word_match (desc.casefold (), q)) s += 15;
            if (word_match (text.casefold (), q)) s += 5;
            return s;
        }

        private static bool word_match (string hay, string q) {
            int at = 0;
            while ((at = hay.index_of (q, at)) >= 0) {
                if (at == 0) return true;
                int prev = at;
                unichar c;
                hay.get_prev_char (ref prev, out c);
                if (!c.isalnum ()) return true;
                at += q.length;
            }
            return false;
        }

        private static string snippet (string text, string q) {
            string plain = text.strip ();
            int at = plain.casefold ().index_of (q);
            if (at < 0 || plain.length < 140) return plain.length > 140 ? plain.substring (0, plain.index_of_nth_char (140)) + "..." : plain;
            int start = int.max (0, at - 50);
            while (start > 0 && !plain.valid_char (start)) start--;
            string part = plain.substring (start);
            if (part.char_count () > 140) part = part.substring (0, part.index_of_nth_char (140)) + "...";
            return (start > 0 ? "..." : "") + part;
        }
    }
}
