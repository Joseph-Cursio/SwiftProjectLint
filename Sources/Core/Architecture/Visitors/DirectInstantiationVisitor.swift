import Foundation
import SwiftSyntax

/// A SwiftSyntax visitor that detects direct instantiation of concrete service-like types
/// where dependency injection would improve testability and reduce coupling.
class DirectInstantiationVisitor: BasePatternVisitor {
    private var currentFilePath: String = ""
    private var insideFunctionOrClosure = 0

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

    // MARK: - Service-like call heuristic

    private func isServiceLikeCall(_ expr: ExprSyntax) -> String? {
        guard let call = expr.as(FunctionCallExprSyntax.self) else { return nil }
        let callee = call.calledExpression.description.trimmingCharacters(in: .whitespaces)
        guard callee.first?.isUppercase == true,
              ServiceSuffix.allCases.contains(where: { callee.hasSuffix($0.rawValue) }) else { return nil }
        return callee
    }

    // MARK: - Property wrapper detection

    private static let propertyWrapperNames: Set<String> = [
        "State", "StateObject", "ObservedObject", "EnvironmentObject",
        "Binding", "Published", "AppStorage", "SceneStorage"
    ]

    private func hasPropertyWrapper(_ node: VariableDeclSyntax) -> Bool {
        for attribute in node.attributes {
            if let attr = attribute.as(AttributeSyntax.self),
               let name = attr.attributeName.as(IdentifierTypeSyntax.self)?.name.text,
               Self.propertyWrapperNames.contains(name) {
                return true
            }
        }
        return false
    }

    // MARK: - Stored property / local variable detection

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        // Inside a function or closure: local variable — no wrapper check needed
        // Outside (stored property): skip if it has a property wrapper
        if insideFunctionOrClosure == 0 && hasPropertyWrapper(node) {
            return .visitChildren
        }

        for binding in node.bindings {
            guard let initializer = binding.initializer else { continue }
            if let typeName = isServiceLikeCall(initializer.value) {
                let paramName: String
                if let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                    paramName = pattern.identifier.text
                } else {
                    paramName = "dependency"
                }
                _ = paramName // suppress unused warning — message uses typeName
                addIssue(
                    severity: .warning,
                    message: "Direct instantiation of '\(typeName)' detected — prefer dependency injection",
                    filePath: currentFilePath,
                    lineNumber: getLineNumber(for: Syntax(node)),
                    suggestion: "Inject '\(typeName)' through the initializer or use @StateObject/@EnvironmentObject",
                    ruleName: .directInstantiation
                )
            }
        }
        return .visitChildren
    }

    // MARK: - Constructor/function parameter defaults

    override func visit(_ node: FunctionParameterSyntax) -> SyntaxVisitorContinueKind {
        guard let defaultValue = node.defaultValue else { return .visitChildren }
        if let typeName = isServiceLikeCall(defaultValue.value) {
            let paramName = node.firstName.text
            addIssue(
                severity: .warning,
                message: "Default parameter '\(paramName)' directly instantiates '\(typeName)' — prefer injection",
                filePath: currentFilePath,
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Remove the default value and inject '\(typeName)' at the call site",
                ruleName: .directInstantiation
            )
        }
        return .visitChildren
    }

    // MARK: - Function / closure context tracking

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        insideFunctionOrClosure += 1
        return .visitChildren
    }

    override func visitPost(_ node: FunctionDeclSyntax) {
        insideFunctionOrClosure -= 1
    }

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        insideFunctionOrClosure += 1
        return .visitChildren
    }

    override func visitPost(_ node: ClosureExprSyntax) {
        insideFunctionOrClosure -= 1
    }
}
