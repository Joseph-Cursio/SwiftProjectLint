import SwiftProjectLintVisitors
import SwiftSyntax

/// A source location captured during the walk so it can be reported after it.
///
/// The idempotency visitors are cross-file: they collect *analysis sites* while walking each
/// file, but emit issues from `finalizeAnalysis()` once every file has been walked — by which
/// point the visitor's own converter and `currentFilePath` point at whichever file came last.
/// Each site therefore has to capture its own file's path and converter at collection time and
/// carry them to the emit phase.
///
/// All five visitors did this the same way: a `filePath`/`locationConverter` pair on every site
/// struct, a `currentLocationConverter` field mirroring the base's own converter, a fallback
/// `SourceLocationConverter(...)` at every construction site, and a
/// `converter.location(for: node.positionAfterSkippingLeadingTrivia).line` incantation at every
/// emit. Duplicate Struct Shape flagged the site structs and Hoistable Conformer Member the
/// identical `analyze()`; this is the shared plumbing under both. See `captureSiteLocation`.
struct CapturedSiteLocation {
    let filePath: String
    let converter: SourceLocationConverter

    /// The 1-based line `node` begins on, skipping leading trivia — the lookup every emit site
    /// used to spell out by hand.
    func line(of node: some SyntaxProtocol) -> Int {
        converter.location(for: node.positionAfterSkippingLeadingTrivia).line
    }
}

extension CrossFileVisitorBase {

    /// Captures the current file's location for a site being collected during the walk.
    ///
    /// Reads the converter the analysis engine set for this file before walking it, falling back
    /// to one built from `node.root` if none was set (the same defensive default the visitors
    /// carried inline). `rootedAt` only supplies that fallback tree.
    func captureSiteLocation(rootedAt node: some SyntaxProtocol) -> CapturedSiteLocation {
        let resolved = sourceLocationConverter
            ?? SourceLocationConverter(fileName: currentFilePath, tree: node.root)
        return CapturedSiteLocation(filePath: currentFilePath, converter: resolved)
    }
}
