import Foundation
import SwiftSyntax

/// A SwiftSyntax visitor that detects type annotations using concrete service-like types
/// where a protocol abstraction would improve testability and reduce coupling.
class ConcreteTypeUsageVisitor: BasePatternVisitor {
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

    // MARK: - Service-like type heuristic

    private func extractServiceTypeName(from type: TypeSyntax) -> String? {
        // Direct: NetworkService
        if let id = type.as(IdentifierTypeSyntax.self) {
            return qualifying(id.name.text)
        }
        // Optional: NetworkService?
        if let opt = type.as(OptionalTypeSyntax.self),
           let id = opt.wrappedType.as(IdentifierTypeSyntax.self) {
            return qualifying(id.name.text)
        }
        // Implicitly unwrapped: NetworkService!
        if let iuo = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self),
           let id = iuo.wrappedType.as(IdentifierTypeSyntax.self) {
            return qualifying(id.name.text)
        }
        return nil
    }

    /// Returns the name if it's service-like and not a protocol indicator, else nil.
    private func qualifying(_ name: String) -> String? {
        guard name.first?.isUppercase == true,
              ServiceSuffix.allCases.contains(where: { name.hasSuffix($0.rawValue) }),
              !name.hasSuffix("Protocol"),
              !name.hasSuffix("Type"),
              !name.hasSuffix("Interface")
        else { return nil }
        return name
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

    // MARK: - Function/initializer parameters

    override func visit(_ node: FunctionParameterSyntax) -> SyntaxVisitorContinueKind {
        // Skip opaque types (some Protocol)
        if node.type.is(SomeOrAnyTypeSyntax.self) {
            return .visitChildren
        }
        guard let typeName = extractServiceTypeName(from: node.type) else {
            return .visitChildren
        }
        let paramName = node.firstName.text
        addIssue(
            severity: .warning,
            message: "Parameter '\(paramName)' uses concrete type '\(typeName)' — prefer a protocol abstraction",
            filePath: currentFilePath,
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Define a protocol for '\(typeName)' and use the protocol as the parameter type",
            ruleName: .concreteTypeUsage
        )
        return .visitChildren
    }

    // MARK: - Stored properties with type annotations

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        // Skip if property has a reactive/injection wrapper
        if hasPropertyWrapper(node) {
            return .visitChildren
        }

        for binding in node.bindings {
            guard let typeAnnotation = binding.typeAnnotation else { continue }
            // Skip if there's also a service-like initializer (caught by DirectInstantiationVisitor)
            if binding.initializer != nil { continue }

            guard let typeName = extractServiceTypeName(from: typeAnnotation.type) else { continue }
            let propName: String
            if let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                propName = pattern.identifier.text
            } else {
                propName = "property"
            }
            addIssue(
                severity: .warning,
                message: "Property '\(propName)' declares concrete type '\(typeName)' — prefer a protocol abstraction",
                filePath: currentFilePath,
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Define a protocol for '\(typeName)' and use the protocol as the property type",
                ruleName: .concreteTypeUsage
            )
        }
        return .visitChildren
    }
}
