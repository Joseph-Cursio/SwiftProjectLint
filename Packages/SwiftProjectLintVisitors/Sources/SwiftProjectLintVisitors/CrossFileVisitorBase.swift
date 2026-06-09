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
}
