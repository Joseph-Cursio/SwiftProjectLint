import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// The positive testability signal: surfaces free / `static` functions that
/// look pure and total — they take parameters, return a value, aren't `async`,
/// and their body shows no obvious impurity (no I/O, logging, randomness, or
/// global access). These are the low-hanging fruit for property-based testing,
/// and the seed the lint → infer → verify pipeline (Idea #2) hands to
/// `swift-infer`.
///
/// Conservative by design — it under-suggests rather than flag an impure
/// function. `info` severity; opt-in.
final class PureFunctionCandidateVisitor: BasePatternVisitor {

    private var fileIsTestOrFixture = false

    /// Strong impurity markers — any in the body disqualifies the function.
    private static let impureMarkers: Set<String> = [
        "print", "NSLog", "FileManager", "URLSession", "UserDefaults",
        "NotificationCenter", "DispatchQueue",
        "arc4random", "arc4random_uniform", "drand48",
        "random", "randomElement", "shuffled"
    ]

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        super.setFilePath(filePath)
        fileIsTestOrFixture = isTestOrFixtureFile()
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard !fileIsTestOrFixture, let body = node.body else { return .visitChildren }
        // Free or `static` only — instance methods can read mutable `self`.
        guard isStatic(node) || isFileScope(node) else { return .visitChildren }
        // Must take inputs and return a value, and run synchronously.
        guard !node.signature.parameterClause.parameters.isEmpty else { return .visitChildren }
        guard hasNonVoidReturn(node.signature) else { return .visitChildren }
        guard node.signature.effectSpecifiers?.asyncSpecifier == nil else { return .visitChildren }
        guard !bodyLooksImpure(body) else { return .visitChildren }

        addIssue(
            severity: .info,
            message: "`\(node.name.text)(…)` looks pure and total — a good property-based-test "
                + "candidate (a function of its inputs)",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Run `swift-infer discover` on it, or add a PropertyLawKit test that "
                + "checks a law over generated inputs.",
            ruleName: .pureFunctionCandidate
        )
        return .visitChildren
    }

    private func isStatic(_ node: FunctionDeclSyntax) -> Bool {
        node.modifiers.contains { $0.name.tokenKind == .keyword(.static) }
    }

    private func isFileScope(_ node: FunctionDeclSyntax) -> Bool {
        guard let item = node.parent?.as(CodeBlockItemSyntax.self),
              let list = item.parent?.as(CodeBlockItemListSyntax.self) else {
            return false
        }
        return list.parent?.is(SourceFileSyntax.self) == true
    }

    private func hasNonVoidReturn(_ signature: FunctionSignatureSyntax) -> Bool {
        guard let returnType = signature.returnClause?.type.trimmedDescription else {
            return false
        }
        return returnType != "Void" && returnType != "()"
    }

    private func bodyLooksImpure(_ body: CodeBlockSyntax) -> Bool {
        body.tokens(viewMode: .sourceAccurate).contains { Self.impureMarkers.contains($0.text) }
    }
}
