namespace Singularity.Apps.Help {

    public class HelpSearchProvider : Singularity.SearchProviderService {
        private weak HelpApp app;
        private Library? library = null;
        private Gee.HashMap<string, Library.Hit> hits = new Gee.HashMap<string, Library.Hit> ();

        public HelpSearchProvider (HelpApp app) {
            this.app = app;
        }

        public override async string[] get_initial_results (string[] terms, Cancellable? cancellable) throws Error {
            if (library == null) library = Library.scan ();
            string[] ids = {};
            foreach (var hit in library.search_terms (terms)) {
                string id = "help:%s/%s".printf (hit.book.id, hit.page);
                if (id in ids) continue;
                hits[id] = hit;
                ids += id;
                if (ids.length >= 8) break;
            }
            return ids;
        }

        public override async Singularity.SearchResultMeta[] get_result_metas (string[] ids, Cancellable? cancellable) throws Error {
            Singularity.SearchResultMeta[] metas = {};
            foreach (string id in ids) {
                var hit = hits[id];
                if (hit == null) continue;
                var meta = new Singularity.SearchResultMeta (id, hit.title != "" ? hit.title : hit.book.title);
                meta.description = hit.snippet != "" ? "%s: %s".printf (hit.book.title, hit.snippet) : hit.book.title;
                meta.icon = new ThemedIcon ("dev.sinty.help");
                meta.score = hit.score;
                metas += meta;
            }
            return metas;
        }

        public override async Singularity.SearchActivationReply? activate_result (string id, string[] terms, uint32 timestamp) throws Error {
            app.show_uri (id);
            return null;
        }

        public override void launch_search (string[] terms, uint32 timestamp) {
            app.show_search (string.joinv (" ", terms));
        }
    }
}
