import SwiftProjectLintVisitors
import SwiftSyntax

/// Memoised per-file import sets backed by the analysis file cache.
///
/// Shared by the idempotency visitors whose heuristic inference gates
/// framework allowlists on a site's imports. Memoised off `fileCache` for
/// the lifetime of a single analysis run. Falls back to the empty set when
/// the path isn't in the cache — no source means no framework-gated
/// allowlists fire for that site, since we can't make import claims about a
/// file we haven't seen.
struct SiteImportCache {

    private let fileCache: [String: SourceFileSyntax]
    private var cache: [String: Set<String>] = [:]

    init(fileCache: [String: SourceFileSyntax]) {
        self.fileCache = fileCache
    }

    /// Returns the base module imports for the file that hosts a site.
    mutating func imports(forSiteFile path: String) -> Set<String> {
        if let cached = cache[path] { return cached }
        guard let source = fileCache[path] else { return [] }
        let set = ImportCollector.imports(in: source)
        cache[path] = set
        return set
    }
}
