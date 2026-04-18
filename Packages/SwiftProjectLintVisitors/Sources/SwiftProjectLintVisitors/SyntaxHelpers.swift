import SwiftProjectLintModels
import SwiftSyntax

// MARK: - SwiftSyntax Convenience Extensions

extension FunctionDeclSyntax {
    /// Direct accessor for the parameter list, avoiding deep signature navigation.
    public var parameterList: FunctionParameterListSyntax {
        signature.parameterClause.parameters
    }
}

extension InitializerDeclSyntax {
    /// Direct accessor for the parameter list, avoiding deep signature navigation.
    public var parameterList: FunctionParameterListSyntax {
        signature.parameterClause.parameters
    }
}

extension VariableDeclSyntax {
    /// Returns the initialiser closure for a single-binding decl whose
    /// initialiser is a closure literal. Returns `nil` when:
    /// - the decl has more than one binding (`let a = {}, b = {}`)
    /// - the sole binding has no initialiser
    /// - the initialiser is some other expression (`let x = 42`)
    ///
    /// Closure-handler annotation (Phase 2 third slice) uses this as the
    /// anchor for the closure's body when `/// @lint.context` is declared
    /// on the variable decl.
    public var closureInitializer: ClosureExprSyntax? {
        guard bindings.count == 1,
              let binding = bindings.first,
              let initialiser = binding.initializer?.value.as(ClosureExprSyntax.self)
        else { return nil }
        return initialiser
    }

    /// The simple identifier of the single binding, if any. Returns `nil`
    /// for multi-binding decls or non-identifier patterns (tuple patterns,
    /// wildcards, etc.).
    public var firstBindingName: String? {
        guard bindings.count == 1,
              let pattern = bindings.first?.pattern.as(IdentifierPatternSyntax.self)
        else { return nil }
        return pattern.identifier.text
    }
}

/// Returns whether a `ForEach` collection expression is safe to use with `id: \.self`.
///
/// `\.self` is the correct and idiomatic approach for:
/// - **Array literals** — e.g. `[100, 85, 70]`
/// - **`.allCases`** — enum cases are inherently stable identities
///
/// The rule should only flag `\.self` on complex model types where a stable `id`
/// property would be more appropriate.
public func isForEachCollectionSafeForSelfID(_ node: FunctionCallExprSyntax) -> Bool {
    guard let collectionArg = node.arguments.first(where: { $0.label?.text != "id" }) else {
        return false
    }
    let expr = collectionArg.expression

    // Pattern 1: Array literal — [100, 85, "a", "b"]
    if expr.is(ArrayExprSyntax.self) {
        return true
    }

    // Pattern 2: Type.allCases
    if let memberAccess = expr.as(MemberAccessExprSyntax.self),
       memberAccess.declName.baseName.text == "allCases" {
        return true
    }

    // Pattern 3: someArray.filter { ... } or similar chain ending in .allCases
    if let memberAccess = expr.as(FunctionCallExprSyntax.self),
       let calledMember = memberAccess.calledExpression.as(MemberAccessExprSyntax.self),
       calledMember.declName.baseName.text == "filter" {
        // e.g. refs.branches.filter { ... } — filtering a String array is still safe
        return true
    }

    return false
}

/// Returns whether the given struct declaration conforms to SwiftUI's `View` or `App` protocol.
public func isSwiftUIView(_ node: StructDeclSyntax) -> Bool {
    let swiftUITypes: Set<String> = [SwiftUIProtocol.view.rawValue, SwiftUIProtocol.app.rawValue]
    return conformsToAny(node, protocols: swiftUITypes)
}

/// Returns whether the given struct conforms to `View` (but not `App`).
public func isSwiftUIViewOnly(_ node: StructDeclSyntax) -> Bool {
    conformsToAny(node, protocols: [SwiftUIProtocol.view.rawValue])
}

private func conformsToAny(_ node: StructDeclSyntax, protocols: Set<String>) -> Bool {
    for inheritance in node.inheritanceClause?.inheritedTypes ?? [] {
        if let name = inheritance.type.as(IdentifierTypeSyntax.self)?.name.text,
           protocols.contains(name) {
            return true
        }
    }
    return false
}

/// Attempts to infer the element type name of the collection passed to a `ForEach` call.
///
/// Handles common patterns:
/// - `ForEach(TypeName.allCases)` → `"TypeName"`
/// - `ForEach(variable)` where `variable` has a `[TypeName]` type annotation in scope → `"TypeName"`
/// - `ForEach(expr.property)` where `property` has a `[TypeName]` type annotation → `"TypeName"`
///
/// Returns `nil` when the element type cannot be determined from syntax alone.
public func inferForEachElementType(_ node: FunctionCallExprSyntax) -> String? {
    // The collection is the first (non-id, non-content) argument.
    guard let collectionArg = node.arguments.first(where: { $0.label?.text != "id" }) else {
        return nil
    }
    let expr = collectionArg.expression

    // Pattern 1: TypeName.allCases / TypeName.someStaticProperty
    if let memberAccess = expr.as(MemberAccessExprSyntax.self),
       let base = memberAccess.base?.as(DeclReferenceExprSyntax.self) {
        let typeName = base.baseName.text
        // Heuristic: type names start with an uppercase letter
        if let first = typeName.first, first.isUppercase {
            return typeName
        }
    }

    // Pattern 2: plain variable reference — search enclosing scope for type annotation
    if let varRef = expr.as(DeclReferenceExprSyntax.self) {
        let varName = varRef.baseName.text
        if let elementType = findArrayElementType(named: varName, around: Syntax(node)) {
            return elementType
        }
    }

    // Pattern 3: member access on a variable (e.g. viewModel.items)
    if let memberAccess = expr.as(MemberAccessExprSyntax.self) {
        let propertyName = memberAccess.declName.baseName.text
        if let elementType = findArrayElementType(named: propertyName, around: Syntax(node)) {
            return elementType
        }
    }

    return nil
}

/// Walks up from `startNode` to find a variable or parameter declaration whose name matches
/// `varName` and whose type annotation is an array type `[ElementType]`. Returns the element type name.
private func findArrayElementType(named varName: String, around startNode: Syntax) -> String? {
    var current: Syntax? = startNode
    while let node = current {
        // Check function parameters (e.g. func foo(_ items: [Item]) { ForEach(items) ... })
        if let funcDecl = node.as(FunctionDeclSyntax.self) {
            if let elementType = findArrayParameter(named: varName, in: funcDecl.parameterList) {
                return elementType
            }
        }
        // Check struct/class members
        if let structDecl = node.as(StructDeclSyntax.self) {
            if let elementType = findArrayProperty(named: varName, in: structDecl.memberBlock.members) {
                return elementType
            }
        }
        if let classDecl = node.as(ClassDeclSyntax.self) {
            if let elementType = findArrayProperty(named: varName, in: classDecl.memberBlock.members) {
                return elementType
            }
        }
        current = node.parent
    }
    return nil
}

/// Searches function parameters for one matching `varName` with an `[ElementType]` annotation.
private func findArrayParameter(named varName: String, in parameters: FunctionParameterListSyntax) -> String? {
    for param in parameters {
        // Match by second name (local name) or first name if no second name
        let localName = param.secondName?.text ?? param.firstName.text
        guard localName == varName else { continue }

        if let name = extractArrayElementTypeName(from: param.type) {
            return name
        }
    }
    return nil
}

/// Searches member declarations for a property with the given name and an `[ElementType]` annotation.
private func findArrayProperty(named varName: String, in members: MemberBlockItemListSyntax) -> String? {
    for member in members {
        guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
        for binding in varDecl.bindings {
            guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                  pattern.identifier.text == varName,
                  let typeAnnotation = binding.typeAnnotation else { continue }

            if let name = extractArrayElementTypeName(from: typeAnnotation.type) {
                return name
            }
        }
    }
    return nil
}

/// Extracts the element type name from an array type like `[Foo]` or `[Outer.Inner]`.
/// Returns the **leaf** type name (e.g. `"Inner"` for `[Outer.Inner]`) since that is
/// the type that must conform to `Identifiable`.
private func extractArrayElementTypeName(from typeSyntax: TypeSyntax) -> String? {
    guard let arrayType = typeSyntax.as(ArrayTypeSyntax.self) else { return nil }
    // Simple identifier: [Foo]
    if let ident = arrayType.element.as(IdentifierTypeSyntax.self) {
        return ident.name.text
    }
    // Member type: [Outer.Inner]
    if let memberType = arrayType.element.as(MemberTypeSyntax.self) {
        return memberType.name.text
    }
    return nil
}
