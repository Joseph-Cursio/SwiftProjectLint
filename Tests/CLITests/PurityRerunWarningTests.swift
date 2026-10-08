@testable import CLI
import Core
import Foundation
import SwiftParser
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

    /// The test above holds `makeLinter`; this holds that `run()` takes its linter from it, with
    /// standard error as the listener. `run()` cannot be exercised for it: the configured rules
    /// declare what they read, so a real run never trips, and a debug build's `analyzeProject`
    /// asserts on one that does. So this reads the CLI's source instead.
    @Test func cliBuildsItsLinterOnlyThroughMakeLinter() throws {
        let files = try Self.cliSources()
        #expect(files.count >= 5, "found \(files.map(\.path)) — has Sources/CLI moved?")
        var analyses = 0
        for file in files {
            let finder = LinterUseFinder(viewMode: .sourceAccurate)
            finder.walk(file.tree)
            // `ProjectLinter()`, `.init()` with the type spelled, or another helper returning one.
            #expect(finder.linterNamedOutsideMakeLinter.isEmpty, "\(file.path): \(finder.linterNamedOutsideMakeLinter)")
            #expect(finder.unboundAnalyses.isEmpty, "\(file.path): \(finder.unboundAnalyses)")
            analyses += finder.boundAnalyses
        }
        #expect(analyses == 1, "run() analyses the project once, on a linter from makeLinter")
    }

    /// Every Swift file in `Sources/CLI`, parsed.
    private static func cliSources() throws -> [(path: String, tree: SourceFileSyntax)] {
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // CLITests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repository root
            .appendingPathComponent("Sources/CLI")
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        return try names.filter { $0.hasSuffix(".swift") }.sorted().map { name in
            let text = try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
            return (name, Parser.parse(source: text))
        }
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

/// Where the CLI names `ProjectLinter`, and what it calls `analyzeProject` or `lint` on.
///
/// A call counts as bound when it is made in `run()` on a constant initialized there by a
/// `makeLinter` call whose argument passes `printToStandardError`.
private final class LinterUseFinder: SyntaxVisitor {

    private(set) var linterNamedOutsideMakeLinter: [String] = []
    private(set) var unboundAnalyses: [String] = []
    private(set) var boundAnalyses = 0
    private var function: String?
    /// The constants `run()` binds to a linter from `makeLinter` that warns on standard error.
    private var linters: Set<String> = []

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        function = node.name.text
        linters = []
        return .visitChildren
    }

    override func visitPost(_: FunctionDeclSyntax) {
        function = nil
    }

    override func visit(_ token: TokenSyntax) -> SyntaxVisitorContinueKind {
        if token.tokenKind == .identifier("ProjectLinter"), function != "makeLinter" {
            let use = token.parent?.trimmedDescription ?? ""
            linterNamedOutsideMakeLinter.append("\(function ?? "file scope"): \(use)")
        }
        return .visitChildren
    }

    override func visit(_ node: PatternBindingSyntax) -> SyntaxVisitorContinueKind {
        guard function == "run", let call = node.initializer?.value.as(FunctionCallExprSyntax.self) else {
            return .visitChildren
        }
        let callee = call.calledExpression.trimmedDescription
        let warnsOnStandardError = call.tokens(viewMode: .sourceAccurate).contains { $0.text == "printToStandardError" }
        if callee == "Self.makeLinter" || callee == "makeLinter", warnsOnStandardError {
            linters.insert(node.pattern.trimmedDescription)
        }
        return .visitChildren
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        guard ["analyzeProject", "lint"].contains(node.declName.baseName.text) else { return .visitChildren }
        if function == "run", let base = node.base?.trimmedDescription, linters.contains(base) {
            boundAnalyses += 1
        } else {
            unboundAnalyses.append("\(function ?? "file scope"): \(node.trimmedDescription)")
        }
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
