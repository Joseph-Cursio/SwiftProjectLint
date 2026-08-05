import SwiftSyntax

/// Shared scaffolding for cross-file pattern visitors.
///
/// Cross-file visitors accumulate state across every file walked, then emit in
/// `finalizeAnalysis()` once all files have been seen. They all need the same
/// setup: the file cache, the two `required` initialisers (the `fileCache` form
/// the cross-file engine constructs, and the `pattern` form used for direct and
/// unit-test use), and tracking of the path currently being walked.
///
/// This base provides exactly that. Subclasses add their own collection state,
/// `visit(_:)` overrides, and `finalizeAnalysis()`, and declare
/// `CrossFilePatternVisitorProtocol` conformance — the inherited `fileCache` and
/// `init(fileCache:)` satisfy its requirements.
open class CrossFileVisitorBase: BasePatternVisitor {

    /// The cached source files for cross-file analysis.
    public let fileCache: [String: SourceFileSyntax]

    /// Path of the file currently being walked. Updated via `setFilePath`.
    public private(set) var currentFilePath: String = ""

    public required init(fileCache: [String: SourceFileSyntax]) {
        self.fileCache = fileCache
        super.init(pattern: BasePatternVisitor.placeholderPattern, viewMode: .sourceAccurate)
    }

    public required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        self.fileCache = [:]
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override open func setFilePath(_ filePath: String) {
        super.setFilePath(filePath)
        currentFilePath = filePath
    }

    /// Converters keyed by the identity of the tree they were built for, so a node
    /// can be resolved against its own file rather than the current one.
    private var convertersByRoot: [SyntaxIdentifier: SourceLocationConverter] = [:]

    /// The path each cached file was parsed from, keyed by its tree's identity — the inverse of
    /// `fileCache`, which is keyed the wrong way round to answer "which file is this node from?".
    /// Only names the converters built below; a converter carrying one file's name and another
    /// file's tree would be a trap for anyone who later reads its `file` rather than its `line`.
    private lazy var pathsByRoot: [SyntaxIdentifier: String] =
        Dictionary(fileCache.map { (Syntax($0.value).id, $0.key) }) { first, _ in first }

    /// The 1-based line `node` begins on, read from *its own* file.
    ///
    /// The inherited implementation reads `sourceLocationConverter`, which the analysis engine
    /// resets before walking each file. That is correct during the walk and wrong afterwards:
    /// cross-file visitors collect declarations while walking and emit them from
    /// `finalizeAnalysis()`, by which point the installed converter belongs to whichever file
    /// happened to be walked last. A node from any other file was then measured against a
    /// stranger's line table — and since the engine iterates `fileCache`, an unordered
    /// dictionary, "last" changed with the hash seed, so the same binary reported the same
    /// finding at different lines on different runs.
    ///
    /// A node knows its own tree, so ask that instead. `node.root` is the `SourceFileSyntax`
    /// the node was parsed from, and a converter built from it is the only one that can be
    /// right. Converters are cached by root identity, so at most one is built per file that
    /// actually carries a finding — the walk-phase path stays on the engine's own converter,
    /// which already matches.
    override open func getLineNumber(for node: Syntax) -> Int {
        let root = node.root
        if let cached = convertersByRoot[root.id] {
            return cached.location(for: node.positionAfterSkippingLeadingTrivia).line
        }
        guard root.is(SourceFileSyntax.self) else { return super.getLineNumber(for: node) }

        let converter = SourceLocationConverter(
            fileName: pathsByRoot[root.id] ?? currentFilePath,
            tree: root
        )
        convertersByRoot[root.id] = converter
        return converter.location(for: node.positionAfterSkippingLeadingTrivia).line
    }
}
