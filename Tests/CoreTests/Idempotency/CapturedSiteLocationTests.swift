import SwiftParser
@testable import SwiftProjectLintIdempotencyRules
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// The source-location plumbing shared by the five idempotency visitors, extracted from five
/// identical `filePath`/`locationConverter` pairs (flagged by Duplicate Struct Shape) into one
/// `CapturedSiteLocation`. The visitors' own suites already assert the emitted line numbers and
/// file paths end-to-end; these cover the helper in isolation.
@Suite
struct CapturedSiteLocationTests {

    /// Minimal `CrossFileVisitorBase` subclass so `captureSiteLocation(rootedAt:)` — an
    /// extension method on that base — can be exercised directly.
    private final class ProbeVisitor: CrossFileVisitorBase {
        var captured: CapturedSiteLocation?

        override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
            captured = captureSiteLocation(rootedAt: node)
            return .visitChildren
        }
    }

    @Test("line(of:) reports the 1-based line a node begins on, skipping leading trivia")
    func lineOfReportsNodeLine() {
        let source = """
        // line 1
        func first() {}

        func second() {}
        """
        let tree = Parser.parse(source: source)
        let location = CapturedSiteLocation(
            filePath: "Probe.swift",
            converter: SourceLocationConverter(fileName: "Probe.swift", tree: tree)
        )

        let funcs = tree.statements.compactMap { $0.item.as(FunctionDeclSyntax.self) }
        #expect(funcs.count == 2)
        #expect(location.line(of: funcs[0]) == 2)
        #expect(location.line(of: funcs[1]) == 4)
    }

    @Test("captureSiteLocation carries the walked file's path and a working converter")
    func capturePreservesFileAndConverter() throws {
        let source = "func target() {}"
        let tree = Parser.parse(source: source)
        let visitor = ProbeVisitor(fileCache: ["Feature/Target.swift": tree])
        visitor.setFilePath("Feature/Target.swift")
        visitor.setSourceLocationConverter(SourceLocationConverter(fileName: "Feature/Target.swift", tree: tree))
        visitor.walk(tree)

        let captured = try #require(visitor.captured)
        #expect(captured.filePath == "Feature/Target.swift")
        // The captured converter resolves against the same file that was walked.
        let target = try #require(tree.statements.first?.item.as(FunctionDeclSyntax.self))
        #expect(captured.line(of: target) == 1)
    }

    @Test("captureSiteLocation falls back to the node's tree when no converter was set")
    func captureFallsBackWithoutConverter() throws {
        let source = "\nfunc late() {}"
        let tree = Parser.parse(source: source)
        // No setSourceLocationConverter — exercises the defensive fallback path.
        let visitor = ProbeVisitor(fileCache: [:])
        visitor.setFilePath("NoConverter.swift")
        visitor.walk(tree)

        let captured = try #require(visitor.captured)
        #expect(captured.filePath == "NoConverter.swift")
        let target = try #require(tree.statements.first?.item.as(FunctionDeclSyntax.self))
        #expect(captured.line(of: target) == 2)
    }
}
