using Singularity.Apps.Help;

string fx (string p) {
    return Path.build_filename (Environment.get_variable ("HELP_FIXTURES"), p);
}

void test_markdown () {
    var p = Markdown.parse ("---\ntitle: T\ndescription: D\n---\n\nSome *em* and **strong** [link](other) text.\n\n- [A -- first](a)\n- [B](b)\n\n1. one\n2. two\n\n- plain item\n\n> note line\n\n```\ncode <x>\n```\n", "p", "/tmp");
    assert (p.title == "T" && p.description == "D");
    assert (p.blocks[0].kind == BlockKind.PARAGRAPH);
    assert (p.blocks[0].markup.contains ("<i>em</i>") && p.blocks[0].markup.contains ("<b>strong</b>") && p.blocks[0].markup.contains ("<a href=\"other\">"));
    assert (p.blocks[1].kind == BlockKind.LINKS && p.blocks[1].links.size == 2 && p.blocks[1].links[0].description == "first");
    assert (p.blocks[2].kind == BlockKind.STEPS && p.blocks[2].items.length == 2);
    assert (p.blocks[3].kind == BlockKind.BULLETS);
    assert (p.blocks[4].kind == BlockKind.NOTE);
    assert (p.blocks[5].kind == BlockKind.CODE && p.blocks[5].markup == "code &lt;x&gt;");
}

void test_library () {
    var lib = Library.scan ({ fx ("user"), fx ("sys") }, { "C" });
    assert (lib.guides.size == 2);
    assert (lib.guides[0].id == "extra" && lib.guides[1].title == "Distro Guide");
    assert (lib.apps.size == 1 && lib.apps[0].title == "Demo App");
    var it = Library.scan ({ fx ("user"), fx ("sys") }, { "it", "C" });
    assert (it.find ("distro").title == "Guida della distro");
    var fallback = it.find ("distro").page ("updates");
    assert (fallback != null && fallback.title == "Updating");
    assert ("updates" in it.find ("distro").page_ids ());
    var upd = lib.find ("distro").page ("updates.md");
    assert (upd != null && upd.title == "Updating");
    bool warning = false, code = false, steps = false;
    foreach (var b in upd.blocks) {
        if (b.kind == BlockKind.WARNING) warning = true;
        if (b.kind == BlockKind.CODE) code = true;
        if (b.kind == BlockKind.STEPS) steps = true;
    }
    assert (warning && code && steps);
}

void test_mallard () {
    var lib = Library.scan ({ fx ("sys") }, { "C" });
    var demo = lib.find ("demo");
    var index = demo.page ("");
    Block? links = null;
    foreach (var b in index.blocks) if (b.kind == BlockKind.LINKS) links = b;
    assert (links != null && links.links.size == 2);
    assert (links.links[0].title == "Save Your Work");
    var open = demo.page ("open");
    assert (open.description == "Open a file from disk.");
    assert (open.blocks[0].markup.contains ("weight=\"bold\">Ctrl</span>+<span") && open.blocks[0].markup.contains ("href=\"page:save\""));
    assert (open.blocks[1].kind == BlockKind.STEPS && open.blocks[1].items.length == 2);
    assert (open.blocks[2].kind == BlockKind.WARNING);
}

void test_search () {
    var lib = Library.scan ({ fx ("user"), fx ("sys") }, { "C" });
    var hits = lib.search ("updat");
    assert (hits.size >= 1 && hits[0].page == "updates");
    hits = lib.search ("save your");
    assert (hits.size >= 1 && hits[0].title == "Save Your Work");
    assert (Library.keywords ({ "Wi-Fi", "not", "connecting" }).length == 2);
    assert (Library.keywords ({ "Wi-Fi", "not", "connecting" })[1] == "connect");
    hits = lib.search_terms ({ "how", "to", "save", "work" });
    assert (hits.size >= 1 && hits[0].title == "Save Your Work");
    assert (lib.search_terms ({ "the", "not" }).size == 0);
}

void test_manual () {
    string bs = "\b";
    string raw = "LS(1)        User Commands        LS(1)\n\nNAME\n       ls - list directory contents\n\nDESCRIPTION\n       List  the  FILEs.\n\n       "
        + "-a" .replace ("-", "-" + bs + "-").replace ("a", "a" + bs + "a") + ", --all\n              do not ignore entries starting with .\n\n       -c     sort by ctime\n\n"
        + "   Sizes\n       Use _" + bs + "S_" + bs + "I_" + bs + "Z_" + bs + "E here.\n";
    var page = Manual.parse (raw, "ls", "1");
    assert (page.title == "ls(1)");
    assert (page.description == "List directory contents");
    assert (page.blocks[0].kind == BlockKind.HEADING && page.blocks[0].markup == "Description");
    assert (page.blocks[1].kind == BlockKind.PARAGRAPH && page.blocks[1].markup == "List the FILEs.");
    assert (page.blocks[2].kind == BlockKind.TERM && page.blocks[2].markup == "<b>-a</b>, --all");
    assert (page.blocks[3].kind == BlockKind.TERM && page.blocks[3].markup == "-c" && page.blocks[3].items[0] == "sort by ctime");
    assert (page.blocks[4].kind == BlockKind.HEADING && page.blocks[4].level == 3);
    assert (page.blocks[5].markup == "Use <i>SIZE</i> here.");
}

void test_shipped_guide () {
    var lib = Library.scan ({ Path.build_filename (Environment.get_variable ("HELP_GUIDE"), "..") }, { "C" });
    var dirs = new string[] { Environment.get_variable ("HELP_GUIDE") };
    var guide = Library.scan ({ fx ("none") }, { "C" });
    assert (guide.guides.size == 0);
    string root = Environment.get_variable ("HELP_GUIDE");
    var d = Path.build_filename (root, "C", "singularity");
    var book = new Book ();
    book.id = "singularity";
    book.kind = BookKind.GUIDE;
    book.dir = d;
    foreach (string id in book.page_ids ()) {
        var p = book.page (id);
        assert (p != null && p.title != "");
        foreach (var b in p.blocks) {
            foreach (var l in b.links) assert (book.page (l.target) != null);
            try {
                Pango.parse_markup (b.markup, -1, 0, null, null, null);
                foreach (string i in b.items) Pango.parse_markup (i, -1, 0, null, null, null);
            } catch (Error e) {
                error ("%s: bad markup %s", id, e.message);
            }
        }
    }
    var shipped = new Library ();
    shipped.guides.add (book);
    var wifi = shipped.search_terms ({ "wifi", "not", "connecting" });
    assert (wifi.size >= 1 && wifi[0].page == "network");
    var wallpaper = shipped.search_terms ({ "change", "wallpaper" });
    assert (wallpaper.size >= 1 && wallpaper[0].page == "settings");
    assert (lib != null && dirs.length == 1);
}

int main (string[] args) {
    Test.init (ref args);
    Test.add_func ("/help/markdown", test_markdown);
    Test.add_func ("/help/library", test_library);
    Test.add_func ("/help/mallard", test_mallard);
    Test.add_func ("/help/search", test_search);
    Test.add_func ("/help/manual", test_manual);
    Test.add_func ("/help/shipped-guide", test_shipped_guide);
    return Test.run ();
}
