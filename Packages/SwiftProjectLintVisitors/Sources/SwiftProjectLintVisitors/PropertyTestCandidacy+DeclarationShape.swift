import SwiftEffectInference
import SwiftSyntax

extension PropertyTestCandidacy {
    // MARK: - Declaration shape

    static func isStatic(_ function: FunctionDeclSyntax) -> Bool {
        function.modifiers.contains { $0.name.tokenKind == .keyword(.static) }
    }

    static func isMutating(_ function: FunctionDeclSyntax) -> Bool {
        function.modifiers.contains { $0.name.tokenKind == .keyword(.mutating) }
    }

    static func isFileScope(_ function: FunctionDeclSyntax) -> Bool {
        guard let item = function.parent?.as(CodeBlockItemSyntax.self),
              let list = item.parent?.as(CodeBlockItemListSyntax.self) else {
            return false
        }
        return list.parent?.is(SourceFileSyntax.self) == true
    }

    /// The type a method is declared in, with the stored properties visible in this file.
    struct TypeContainer {
        let isActor: Bool
        /// `true` when the enclosing type is a `struct` or `enum`. Decided directly for a primary
        /// declaration and, for an `extension`, by looking the extended type up in the project's
        /// value-type index — the extension syntax alone never says `struct`.
        let isValueType: Bool
        let storedProperties: [String: StoredProperty]
    }

    /// Walks out to the type (or extension) `function` is declared in, then gathers the stored
    /// properties of *every* declaration of that type in this file.
    ///
    /// The second half matters: the logic usually lives in an extension and the state in the
    /// primary declaration, and an extension's own member block holds no stored properties at all.
    /// What this cannot see is a primary declaration in another file — and a reference the analyzer
    /// cannot resolve disqualifies the candidate, which is the safe direction.
    static func enclosingTypeContainer(
        of function: some SyntaxProtocol,
        knownValueTypes: Set<String>
    ) -> TypeContainer? {
        var cursor: Syntax? = Syntax(function).parent
        while let current = cursor {
            if let structDecl = current.as(StructDeclSyntax.self) {
                return container(named: structDecl.name.text, isActor: false, isValueType: true, from: function)
            }
            if let classDecl = current.as(ClassDeclSyntax.self) {
                return container(named: classDecl.name.text, isActor: false, isValueType: false, from: function)
            }
            if let enumDecl = current.as(EnumDeclSyntax.self) {
                return container(named: enumDecl.name.text, isActor: false, isValueType: true, from: function)
            }
            if let actorDecl = current.as(ActorDeclSyntax.self) {
                return container(named: actorDecl.name.text, isActor: true, isValueType: false, from: function)
            }
            if let extensionDecl = current.as(ExtensionDeclSyntax.self) {
                // The extended type's kind is not in the extension's syntax; the cross-file index
                // is what says whether `extension OrderedSet` extends a value type.
                //
                // A stdlib carrier answers the same question without the index. `knownValueTypes`
                // holds *project* declarations, so `extension String` used to report "not a value
                // type" — and the bare-`self` branch then refused every member that reads the
                // string it extends. That is not conservatism about something unknown; `String`
                // is a struct, and the analyzer was answering a question it had the answer to
                // (SwiftProjectLint#214).
                let extendedBase = baseTypeName(extensionDecl.extendedType)
                    ?? extensionDecl.extendedType.trimmedDescription
                return container(
                    named: extensionDecl.extendedType.trimmedDescription,
                    isActor: false,
                    isValueType: knownValueTypes.contains(extendedBase)
                        || StdlibTypeNames.valueTypes.contains(extendedBase),
                    from: function
                )
            }
            cursor = current.parent
        }
        return nil
    }

    static func container(
        named name: String,
        isActor: Bool,
        isValueType: Bool,
        from node: some SyntaxProtocol
    ) -> TypeContainer {
        guard let file = node.root.as(SourceFileSyntax.self) else {
            return TypeContainer(isActor: isActor, isValueType: isValueType, storedProperties: [:])
        }

        let collector = TypeStoredPropertyCollector(typeName: name, viewMode: .sourceAccurate)
        collector.walk(file)
        let sawActor = isActor || collector.sawActorDeclaration
        return TypeContainer(
            isActor: sawActor,
            // An actor is never a value type — if the local scan reveals `name` is actually an
            // actor, the value-type read must not fire.
            isValueType: isValueType && !sawActor,
            storedProperties: collector.properties
        )
    }
}
