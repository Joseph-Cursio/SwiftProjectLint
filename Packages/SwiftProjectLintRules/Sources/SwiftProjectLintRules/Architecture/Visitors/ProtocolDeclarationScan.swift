import SwiftSyntax

/// What the first pass of `ProtocolClientIndex` learns: every name a type reference could resolve
/// to, before any type reference is resolved.
struct ProtocolDeclarations {
    var protocols: [String: [ProtocolInfo]] = [:]
    /// `typealias Store = Saving & History` → its right-hand side.
    var aliases: [String: TypeSyntax] = [:]
    /// Struct, class, enum, actor and protocol names — what `Name(…)` may construct.
    var typeNames: Set<String> = []
    /// Inheritance-clause names per type, from its declaration and every extension of it.
    var supertypes: [String: [String]] = [:]
    /// The generic parameter clauses of each nominal type, resolved once every protocol is known.
    var genericClauses: [String: [GenericClause]] = [:]

    struct GenericClause {
        let parameters: GenericParameterClauseSyntax?
        let whereClause: GenericWhereClauseSyntax?
    }

    /// Each protocol plus every project protocol it refines, transitively.
    func ancestors(of name: String) -> Set<String> {
        var result: Set<String> = []
        var pending = [name]
        while let next = pending.popLast() {
            for resolved in protocolNames(spelled: next) where result.insert(resolved).inserted {
                let inherited = protocols[resolved]?.flatMap(\.inheritedNames) ?? []
                pending.append(contentsOf: inherited)
            }
        }
        return result
    }

    /// A protocol's own name, or the protocols a typealias composes.
    private func protocolNames(spelled name: String) -> [String] {
        if protocols[name] != nil {
            return [name]
        }
        guard let alias = aliases[name] else { return [] }
        return ProtocolDeclarationScan.componentNames(of: alias)
    }
}

/// Pass one of `ProtocolClientIndex`: declarations only.
enum ProtocolDeclarationScan {

    static func scan(_ sources: [(path: String, tree: SourceFileSyntax)]) -> ProtocolDeclarations {
        var declarations = ProtocolDeclarations()
        for source in sources {
            let collector = Collector(
                filePath: source.path,
                converter: SourceLocationConverter(fileName: source.path, tree: source.tree),
                declarations: declarations
            )
            collector.walk(source.tree)
            declarations = collector.declarations
        }
        return declarations
    }

    /// The nominal names a type spells at its top level: `P` for `any P`, `[P, Q]` for `P & Q`.
    static func componentNames(of type: TypeSyntax) -> [String] {
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            return [identifier.name.text]
        }
        if let member = type.as(MemberTypeSyntax.self) {
            return [member.name.text]
        }
        if let composition = type.as(CompositionTypeSyntax.self) {
            return composition.elements.flatMap { componentNames(of: $0.type) }
        }
        if let someOrAny = type.as(SomeOrAnyTypeSyntax.self) {
            return componentNames(of: someOrAny.constraint)
        }
        if let attributed = type.as(AttributedTypeSyntax.self) {
            return componentNames(of: attributed.baseType)
        }
        return []
    }

    /// The requirements a protocol body declares, in source order.
    static func requirements(
        of node: ProtocolDeclSyntax,
        converter: SourceLocationConverter
    ) -> [ProtocolRequirement] {
        node.memberBlock.members.flatMap { member in
            let line = converter.location(for: member.decl.positionAfterSkippingLeadingTrivia).line
            return requirements(declaredBy: member.decl, line: line)
        }
    }

    private static func requirements(declaredBy decl: DeclSyntax, line: Int) -> [ProtocolRequirement] {
        if let function = decl.as(FunctionDeclSyntax.self) {
            let parameters = function.signature.parameterClause.parameters
            let requirement = ProtocolRequirement(
                kind: .method,
                name: function.name.text,
                labels: parameters.map(\.firstName.text),
                isStatic: isStatic(function.modifiers),
                hasVariadicParameter: parameters.contains { $0.ellipsis != nil },
                line: line
            )
            return [requirement]
        }
        if let variable = decl.as(VariableDeclSyntax.self) {
            return variable.bindings.compactMap { binding in
                binding.pattern.as(IdentifierPatternSyntax.self).map { pattern in
                    ProtocolRequirement(
                        kind: .property, name: pattern.identifier.text, labels: [],
                        isStatic: isStatic(variable.modifiers), hasVariadicParameter: false, line: line
                    )
                }
            }
        }
        return otherRequirements(declaredBy: decl, line: line)
    }

    private static func otherRequirements(declaredBy decl: DeclSyntax, line: Int) -> [ProtocolRequirement] {
        if let subscriptDecl = decl.as(SubscriptDeclSyntax.self) {
            // A subscript parameter has an argument label only when it spells two names.
            let labels = subscriptDecl.parameterClause.parameters.map { parameter in
                parameter.secondName == nil ? "_" : parameter.firstName.text
            }
            let requirement = ProtocolRequirement(
                kind: .subscriptMember, name: "subscript", labels: labels,
                isStatic: isStatic(subscriptDecl.modifiers), hasVariadicParameter: false, line: line
            )
            return [requirement]
        }
        if decl.is(InitializerDeclSyntax.self) {
            let requirement = ProtocolRequirement(
                kind: .initializer, name: "init", labels: [], isStatic: false, hasVariadicParameter: false, line: line
            )
            return [requirement]
        }
        if let associated = decl.as(AssociatedTypeDeclSyntax.self) {
            let requirement = ProtocolRequirement(
                kind: .associatedType, name: associated.name.text, labels: [],
                isStatic: true, hasVariadicParameter: false, line: line
            )
            return [requirement]
        }
        return []
    }

    static func isStatic(_ modifiers: DeclModifierListSyntax) -> Bool {
        modifiers.contains { ["static", "class"].contains($0.name.text) }
    }

    static func inheritedNames(_ clause: InheritanceClauseSyntax?) -> [String] {
        clause?.inheritedTypes.flatMap { componentNames(of: $0.type) } ?? []
    }

    // MARK: - Collector

    private final class Collector: SyntaxVisitor {
        var declarations: ProtocolDeclarations
        let filePath: String
        let converter: SourceLocationConverter

        init(filePath: String, converter: SourceLocationConverter, declarations: ProtocolDeclarations) {
            self.filePath = filePath
            self.converter = converter
            self.declarations = declarations
            super.init(viewMode: .sourceAccurate)
        }

        override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
            let name = node.name.text
            let info = ProtocolInfo(
                name: name,
                filePath: filePath,
                line: converter.location(for: node.positionAfterSkippingLeadingTrivia).line,
                requirements: ProtocolDeclarationScan.requirements(of: node, converter: converter),
                inheritedNames: ProtocolDeclarationScan.inheritedNames(node.inheritanceClause),
                modifiers: Set(node.modifiers.map(\.name.text)),
                attributeNames: node.attributes.compactMap {
                    $0.as(AttributeSyntax.self)?.attributeName.trimmedDescription
                }
            )
            declarations.protocols[name, default: []].append(info)
            declarations.typeNames.insert(name)
            return .visitChildren
        }

        override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
            declarations.aliases[node.name.text] = node.initializer.value
            return .skipChildren
        }

        override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
            recordNominal(node.name.text, node.inheritanceClause, node.genericParameterClause, node.genericWhereClause)
            return .visitChildren
        }

        override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
            recordNominal(node.name.text, node.inheritanceClause, node.genericParameterClause, node.genericWhereClause)
            return .visitChildren
        }

        override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
            recordNominal(node.name.text, node.inheritanceClause, node.genericParameterClause, node.genericWhereClause)
            return .visitChildren
        }

        override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
            recordNominal(node.name.text, node.inheritanceClause, node.genericParameterClause, node.genericWhereClause)
            return .visitChildren
        }

        override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
            if let name = ProtocolDeclarationScan.componentNames(of: node.extendedType).last {
                declarations.supertypes[name, default: []]
                    .append(contentsOf: ProtocolDeclarationScan.inheritedNames(node.inheritanceClause))
            }
            return .visitChildren
        }

        private func recordNominal(
            _ name: String,
            _ inheritance: InheritanceClauseSyntax?,
            _ parameters: GenericParameterClauseSyntax?,
            _ whereClause: GenericWhereClauseSyntax?
        ) {
            declarations.typeNames.insert(name)
            declarations.supertypes[name, default: []]
                .append(contentsOf: ProtocolDeclarationScan.inheritedNames(inheritance))
            declarations.genericClauses[name, default: []]
                .append(ProtocolDeclarations.GenericClause(parameters: parameters, whereClause: whereClause))
        }
    }
}
