@testable import CLI
import Core
import Foundation
@testable import SwiftProjectLintEngine
import SwiftSyntax
import Testing

/// The CLI's half of the purity gate's rerun report.
///
/// `ProjectLinter.lint` hands a rerun to its notice (`rerunIsReported`); this pins that the CLI's
/// linter has one, and prints it as a `warning:`. Without it a release build redoes a mispredicted
/// run in silence: the findings stay right, the run takes twice as long, and nothing says which
/// declaration is missing.
@Suite
struct PurityRerunWarningTests {

    @Test func cliReportsAPurityRerunAsAWarning() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PurityRerun-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "let doubled = [1, 2].map { $0 * 2 }\n"
            .write(to: root.appendingPathComponent("Doubled.swift"), atomically: true, encoding: .utf8)

        let warnings = WarningBox()
        // `lint`, not `analyzeProject`: the run trips on purpose, and a debug build asserts on that.
        _ = await SwiftProjectLintCLI.makeLinter { warnings.append($0) }.lint(
            at: root.path, targetType: .auto, categories: nil, ruleIdentifiers: [.printStatement],
            detector: Self.undeclaredOracleReader(), configuration: .default
        )
        #expect(warnings.all.count == 1, "\(warnings.all)")
        #expect(warnings.all.first?.hasPrefix("warning: a visitor read package purity") == true, "\(warnings.all)")
        #expect(warnings.all.first?.contains("PurityInferrer()") == true, "\(warnings.all)")
    }

    /// A detector whose one visitor creates an oracle and declares no purity input, so every run of it
    /// withholds the table, trips, and is redone.
    private static func undeclaredOracleReader() -> SourcePatternDetector {
        let registry = PatternVisitorRegistry()
        registry.register(pattern: SyntaxPattern(
            name: .printStatement, visitor: UndeclaredOracleCreator.self, severity: .info, category: .codeQuality,
            messageTemplate: "read", suggestion: "", description: "test reader"
        ))
        return SourcePatternDetector(registry: registry)
    }
}

/// Creates an oracle with every instance, and declares nothing.
private final class UndeclaredOracleCreator: BasePatternVisitor {
    private let oracle = PurityInferrer()

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        if oracle.refutation(for: node) != nil { addIssue(node: Syntax(node)) }
        return .visitChildren
    }
}

/// Collects warnings from a `@Sendable` closure.
private final class WarningBox: @unchecked Sendable {
    // Safety: `@unchecked Sendable` — every access to `warnings` holds `lock`.
    private let lock = NSLock()
    private var warnings: [String] = []
    func append(_ warning: String) { lock.withLock { warnings.append(warning) } }
    var all: [String] { lock.withLock { warnings } }
}
