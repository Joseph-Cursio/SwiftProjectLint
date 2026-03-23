import Foundation
import SwiftSyntax

/// A SwiftSyntax visitor that detects access to `.shared` singletons on service-like types,
/// where dependency injection would improve testability and reduce hard coupling.
class SingletonUsageVisitor: BasePatternVisitor {
    private var currentFilePath: String = ""

    private enum ServiceSuffix: String, CaseIterable {
        case manager = "Manager"
        case service = "Service"
        case store = "Store"
        case provider = "Provider"
        case client = "Client"
        case repository = "Repository"
        case handler = "Handler"
        case controller = "Controller"
        case factory = "Factory"
        case adapter = "Adapter"
        case viewModel = "ViewModel"
        case coordinator = "Coordinator"
    }

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        self.currentFilePath = filePath
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
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
              ServiceSuffix.allCases.contains(where: { name.hasSuffix($0.rawValue) })
        else { return nil }
        return name
    }
}
