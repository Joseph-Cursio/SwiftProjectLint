import SwiftSyntax

/// Returns whether the given struct declaration conforms to SwiftUI's `View` or `App` protocol.
func isSwiftUIView(_ node: StructDeclSyntax) -> Bool {
    let swiftUITypes: Set<String> = [SwiftUIProtocol.view.rawValue, SwiftUIProtocol.app.rawValue]
    return conformsToAny(node, protocols: swiftUITypes)
}

/// Returns whether the given struct conforms to `View` (but not `App`).
func isSwiftUIViewOnly(_ node: StructDeclSyntax) -> Bool {
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
func inferForEachElementType(_ node: FunctionCallExprSyntax) -> String? {
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
            if let elementType = findArrayParameter(named: varName, in: funcDecl.signature.parameterClause.parameters) {
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
