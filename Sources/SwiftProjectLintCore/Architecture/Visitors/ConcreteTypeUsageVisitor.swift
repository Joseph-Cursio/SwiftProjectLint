import Foundation
import SwiftSyntax

/// A SwiftSyntax visitor that detects type annotations using concrete service-like types
/// where a protocol abstraction would improve testability and reduce coupling.
class ConcreteTypeUsageVisitor: BasePatternVisitor {
    private var currentFilePath: String = ""

    /// Whether the current struct/class looks like a DI container.
    private var isInsideDIContainer: Bool = false

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

    /// Foundation / system types that are concrete by design and cannot
    /// reasonably be protocol-abstracted.
    private static let systemConcreteTypes: Set<String> = [
        "FileManager", "NotificationCenter", "UserDefaults",
        "URLSession", "ProcessInfo", "Bundle",
        "UNUserNotificationCenter", "NSWorkspace"
    ]

    /// Type-name suffixes that indicate a DI container or composition root,
    /// where holding concrete types is the whole point.
    private static let diContainerSuffixes = [
        "Container", "Dependencies", "Composition", "Assembly"
    ]

    /// Type-name suffixes indicating a mock/stub/fake, which are concrete by design.
    private static let mockSuffixes = [
        "Mock", "Stub", "Fake", "Spy", "Dummy"
    ]

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        self.currentFilePath = filePath
    }

    // MARK: - Scope tracking

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        isInsideDIContainer = Self.diContainerSuffixes.contains(where: {
            node.name.text.hasSuffix($0)
        })
        return .visitChildren
    }

    override func visitPost(_ node: StructDeclSyntax) {
        isInsideDIContainer = false
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        isInsideDIContainer = Self.diContainerSuffixes.contains(where: {
            node.name.text.hasSuffix($0)
        })
        return .visitChildren
    }

    override func visitPost(_ node: ClassDeclSyntax) {
        isInsideDIContainer = false
    }

    // MARK: - Service-like type heuristic

    private func extractServiceTypeName(from type: TypeSyntax) -> String? {
        // Direct: NetworkService
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            return qualifying(identifier.name.text)
        }
        // Optional: NetworkService?
        if let opt = type.as(OptionalTypeSyntax.self),
           let identifier = opt.wrappedType.as(IdentifierTypeSyntax.self) {
            return qualifying(identifier.name.text)
        }
        // Implicitly unwrapped: NetworkService!
        if let iuo = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self),
           let identifier = iuo.wrappedType.as(IdentifierTypeSyntax.self) {
            return qualifying(identifier.name.text)
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

        // System types that are concrete by design
        if Self.systemConcreteTypes.contains(name) { return nil }

        // Mock/stub/fake types
        if Self.mockSuffixes.contains(where: { name.hasPrefix($0) || name.contains($0) }) {
            return nil
        }

        return name
    }

    // MARK: - Property wrapper detection

    private static let propertyWrapperNames: Set<String> = [
        "State", "StateObject", "ObservedObject", "EnvironmentObject",
        "Binding", "Published", "AppStorage", "SceneStorage",
        "Bindable", "Environment"
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

    // MARK: - Common exemptions

    private func shouldSkipFile() -> Bool {
        // Test files and test helpers use concrete types by necessity
        currentFilePath.contains("Test")
    }

    private func isInsideSwiftUIView(_ node: some SyntaxProtocol) -> Bool {
        // Walk up to find the enclosing struct and check for View conformance
        var current: Syntax = Syntax(node)
        while let parent = current.parent {
            if let structDecl = parent.as(StructDeclSyntax.self) {
                return isSwiftUIView(structDecl)
            }
            current = parent
        }
        return false
    }

    // MARK: - Function/initializer parameters

    override func visit(_ node: FunctionParameterSyntax) -> SyntaxVisitorContinueKind {
        if shouldSkipFile() || isInsideDIContainer { return .visitChildren }
        // Skip opaque types (some Protocol)
        if node.type.is(SomeOrAnyTypeSyntax.self) {
            return .visitChildren
        }
        guard let typeName = extractServiceTypeName(from: node.type) else {
            return .visitChildren
        }
        // Skip all concrete types in SwiftUI views — @Observable requires
        // concrete types for SwiftUI's observation tracking to work
        if isInsideSwiftUIView(node) {
            return .visitChildren
        }
        let paramName = node.firstName.text
        addIssue(
            severity: .info,
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
        if shouldSkipFile() || isInsideDIContainer { return .visitChildren }
        // Skip if property has a reactive/injection wrapper
        if hasPropertyWrapper(node) {
            return .visitChildren
        }

        for binding in node.bindings {
            guard let typeAnnotation = binding.typeAnnotation else { continue }
            // Skip if there's also a service-like initializer (caught by DirectInstantiationVisitor)
            if binding.initializer != nil { continue }

            guard let typeName = extractServiceTypeName(from: typeAnnotation.type) else { continue }
            // Skip all concrete types in SwiftUI views — @Observable requires
            // concrete types for SwiftUI's observation tracking to work
            if isInsideSwiftUIView(node) {
                continue
            }
            let propName: String
            if let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                propName = pattern.identifier.text
            } else {
                propName = "property"
            }
            addIssue(
                severity: .info,
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
