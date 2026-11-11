namespace Singularity.Apps.Help {

    internal class HelpIntents : Object {
        private static Library? library = null;

        private static Library lib() {
            if (library == null) library = Library.scan();
            return library;
        }

        private static string text(Json.Object args, string key) {
            return args.has_member(key) ? args.get_string_member(key).strip() : "";
        }

        private static void split(string id, out Book book, out string page) throws Error {
            string clean = id.has_prefix("help:") ? id.substring(5) : id;
            int slash = clean.index_of_char('/');
            string book_id = slash < 0 ? clean : clean.substring(0, slash);
            var b = lib().find(book_id);
            if (b == null) throw new IOError.NOT_FOUND("no help book %s; see help_books", book_id);
            book = b;
            page = slash < 0 || clean.substring(slash + 1) == "" ? b.start : clean.substring(slash + 1);
        }

        private static void book_entry(Json.Builder b, Book book) {
            b.begin_object();
            b.set_member_name("id").add_string_value(book.id);
            b.set_member_name("title").add_string_value(book.title);
            if (book.description != "") b.set_member_name("description").add_string_value(book.description);
            b.end_object();
        }

        internal static void install(HelpApp app) {
            var agent = app.agent;
            agent.add_intent("help_books", "The help guides and the app manuals installed on this computer.",
                "{\"type\":\"object\",\"properties\":{}}", Singularity.AppIntentRisk.READ, (args) => {
                    var b = new Json.Builder();
                    b.begin_object();
                    b.set_member_name("guides").begin_array();
                    foreach (var book in lib().guides) book_entry(b, book);
                    b.end_array();
                    b.set_member_name("apps").begin_array();
                    foreach (var book in lib().apps) book_entry(b, book);
                    b.end_array();
                    b.end_object();
                    return b.get_root();
                });
            agent.add_intent("help_search", "Search the installed help for how to do something. Each hit has a page id for help_read.",
                "{\"type\":\"object\",\"properties\":{\"query\":{\"type\":\"string\"},\"limit\":{\"type\":\"integer\"}},\"required\":[\"query\"]}",
                Singularity.AppIntentRisk.READ, (args) => {
                    string q = text(args, "query");
                    if (q == "") throw new IOError.INVALID_ARGUMENT("give what to look for");
                    int limit = args.has_member("limit") ? (int) args.get_int_member("limit").clamp(1, 30) : 8;
                    var b = new Json.Builder();
                    b.begin_array();
                    var seen = new Gee.HashSet<string>();
                    foreach (var hit in lib().search(q)) {
                        string id = hit.book.id + "/" + hit.page;
                        if (!seen.add(id)) continue;
                        if (seen.size > limit) break;
                        b.begin_object();
                        b.set_member_name("page").add_string_value(id);
                        b.set_member_name("title").add_string_value(hit.title != "" ? hit.title : hit.book.title);
                        b.set_member_name("book").add_string_value(hit.book.title);
                        if (hit.snippet != "") b.set_member_name("snippet").add_string_value(hit.snippet);
                        b.end_object();
                    }
                    b.end_array();
                    return b.get_root();
                });
            agent.add_intent("help_read", "The text of one help page, with the pages it links to.",
                "{\"type\":\"object\",\"properties\":{\"page\":{\"type\":\"string\",\"description\":\"book/page from help_search, or a book id for its first page\"}},\"required\":[\"page\"]}",
                Singularity.AppIntentRisk.READ, (args) => {
                    Book book;
                    string page_id;
                    split(text(args, "page"), out book, out page_id);
                    var page = book.page(page_id);
                    if (page == null) throw new IOError.NOT_FOUND("no page %s in %s", page_id, book.title);
                    string body = page.plain_text();
                    if (body.char_count() > 20000) body = body.substring(0, body.index_of_nth_char(20000)) + "...";
                    var b = new Json.Builder();
                    b.begin_object();
                    b.set_member_name("page").add_string_value(book.id + "/" + page_id);
                    b.set_member_name("title").add_string_value(page.title);
                    b.set_member_name("text").add_string_value(body);
                    var links = new Gee.HashSet<string>();
                    b.set_member_name("links").begin_array();
                    foreach (var block in page.blocks) {
                        foreach (var l in block.links) {
                            if (!links.add(l.target)) continue;
                            b.begin_object();
                            b.set_member_name("title").add_string_value(l.title);
                            string t = l.target;
                            if (t.has_prefix("help:")) t = t.substring(5);
                            else if (!t.contains(":") && !t.contains("/")) t = book.id + "/" + t;
                            b.set_member_name("target").add_string_value(t);
                            b.end_object();
                        }
                    }
                    b.end_array();
                    b.end_object();
                    return b.get_root();
                });
            agent.add_intent("help_show", "Open a help page in the Help window so the person can follow along.",
                "{\"type\":\"object\",\"properties\":{\"page\":{\"type\":\"string\"}},\"required\":[\"page\"]}",
                Singularity.AppIntentRisk.UNDOABLE, (args) => {
                    Book book;
                    string page_id;
                    split(text(args, "page"), out book, out page_id);
                    if (book.page(page_id) == null) throw new IOError.NOT_FOUND("no page %s in %s", page_id, book.title);
                    app.show_uri("help:%s/%s".printf(book.id, page_id));
                    var b = new Json.Builder();
                    b.begin_object();
                    b.set_member_name("shown").add_string_value(book.id + "/" + page_id);
                    b.set_member_name("undo").add_string_value("close the Help window");
                    b.end_object();
                    return b.get_root();
                });
        }
    }
}
