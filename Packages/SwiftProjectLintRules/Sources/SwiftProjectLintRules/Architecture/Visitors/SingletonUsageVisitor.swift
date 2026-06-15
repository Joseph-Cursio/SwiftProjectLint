import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects access to `.shared` singletons on service-like types,
/// where dependency injection would improve testability and reduce hard coupling.
class SingletonUsageVisitor: BasePatternVisitor {
    private var currentFilePath: String = ""

    /// Cached once per file: whether this is a test or fixture file, in which
    /// case `.shared` access is exempt (see `visit` below).
    private var fileIsTestOrFixture = false

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        // Forward to the base so `isTestOrFixtureFile()` sees the real path —
        // the previous override shadowed `filePath`, leaving the base at its
        // "unknown" default.
        super.setFilePath(filePath)
        self.currentFilePath = filePath
        self.fileIsTestOrFixture = isTestOrFixtureFile()
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        // Test and fixture files legitimately exercise the real `.shared`
        // singleton — calling `ProjectParser.shared` in a unit test is the test
        // using production code, not a coupling smell to refactor. Exempt them,
        // consistent with the other architecture rules' test-file handling
        // (see `ProtocolExemption.isTestConformer`).
        guard !fileIsTestOrFixture else {
            return .skipChildren
        }
        guard node.declName.baseName.text == "shared",
              let base = node.base,
              let ref = base.as(DeclReferenceExprSyntax.self),
              let typeName = qualifyingServiceName(ref.baseName.text) else {
            return .visitChildren
        }
        addIssue(
            severity: .warning,
            message: "Accessing singleton '\(typeName).shared' creates hard coupling — prefer dependency injection",
            filePath: currentFilePath,
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Inject '\(typeName)' as a dependency through the initializer or environment",
            ruleName: .singletonUsage
        )
        return .visitChildren
    }

    private func qualifyingServiceName(_ name: String) -> String? {
        guard name.first?.isUppercase == true,
              ServiceTypeSuffix.matches(name)
        else { return nil }
        return name
    }
}
