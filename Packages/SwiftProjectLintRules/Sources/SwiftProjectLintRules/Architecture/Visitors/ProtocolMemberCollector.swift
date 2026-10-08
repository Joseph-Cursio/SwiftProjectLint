import SwiftSyntax

/// Walks one file for `ProtocolMemberScan`: members and top-level declarations only. Locals and
/// parameters belong to `ProtocolClientWalker`, which sees the scopes they live in.
final class ProtocolMemberCollector: SyntaxVisitor {

    /// The declaration whose members are being read.
    enum Context {
        case nominal(String)
        case protocolDecl(String)
        /// `extension P` (or an alias of protocols), whose `self` is typed with `protocols`.
        case protocolExtension(name: String, protocols: Set<String>)

        var ownerName: String {
            switch self {
            case .nominal(let name), .protocolDecl(let name), .protocolExtension(let name, _):
                return name
            }
        }
    }

    private(set) var scan: ProtocolMemberScan
    private let filePath: String
    private let converter: SourceLocationConverter
    private var contexts: [Context] = []
    private var generics = GenericScope()

    init(scan: ProtocolMemberScan, filePath: String, converter: SourceLocationConverter) {
        self.scan = scan
        self.filePath = filePath
        self.converter = converter
        super.init(viewMode: .sourceAccurate)
    }

    // MARK: - Types

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        push(.nominal(name), frame: scan.genericFrame(ofType: name))
        recordMemberwiseInitializer(of: node)
        return .visitChildren
    }

    override func visitPost(_ _: StructDeclSyntax) {
        pop()
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        push(.nominal(node.name.text), frame: scan.genericFrame(ofType: node.name.text))
        return .visitChildren
    }

    override func visitPost(_ _: ClassDeclSyntax) {
        pop()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        push(.nominal(node.name.text), frame: scan.genericFrame(ofType: node.name.text))
        return .visitChildren
    }

    override func visitPost(_ _: EnumDeclSyntax) {
        pop()
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        push(.nominal(node.name.text), frame: scan.genericFrame(ofType: node.name.text))
        return .visitChildren
    }

    override func visitPost(_ _: ActorDeclSyntax) {
        pop()
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        push(.protocolDecl(name), frame: ["Self": scan.declarations.ancestors(of: name)])
        return .visitChildren
    }

    override func visitPost(_ _: ProtocolDeclSyntax) {
        pop()
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let resolved = Self.extensionContext(of: node, scan: &scan)
        push(resolved.context, frame: resolved.frame)
        return .visitChildren
    }

    override func visitPost(_ _: ExtensionDeclSyntax) {
        pop()
    }

    /// `extension P` makes `self` a protocol value; any other extension reads its type's members.
    static func extensionContext(
        of node: ExtensionDeclSyntax,
        scan: inout ProtocolMemberScan
    ) -> (context: Context, frame: [String: Set<String>]) {
        let name = ProtocolDeclarationScan.componentNames(of: node.extendedType).last ?? ""
        let constraints = node.genericWhereClause?.requirements ?? []
        if var protocols = scan.resolver.protocols(named: name, generics: GenericScope()) {
            for requirement in constraints {
                guard let conformance = requirement.requirement.as(ConformanceRequirementSyntax.self),
                      conformance.leftType.trimmedDescription == "Self" else {
                    continue
                }
                protocols.formUnion(scan.resolver.protocols(in: conformance.rightType, generics: GenericScope()))
            }
            return (.protocolExtension(name: name, protocols: protocols), ["Self": protocols])
        }
        var outer = GenericScope()
        let typeFrame = scan.genericFrame(ofType: name)
        outer.push(typeFrame)
        let whereFrame = scan.resolver.genericFrame(
            parameters: nil, whereClause: node.genericWhereClause, outer: outer
        )
        return (.nominal(name), typeFrame.merging(whereFrame) { $1 })
    }

    // MARK: - Members

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        let position = placement(of: Syntax(node))
        if case .local = position {
            return .visitChildren
        }
        let bindings = Array(node.bindings)
        for (offset, binding) in bindings.enumerated() {
            guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
            recordProperty(
                pattern.identifier.text, binding: binding, siblings: bindings[offset...],
                decl: node, owner: position.owner
            )
        }
        return .visitChildren
    }

    private func recordProperty(
        _ name: String,
        binding: PatternBindingSyntax,
        siblings: ArraySlice<PatternBindingSyntax>,
        decl: VariableDeclSyntax,
        owner: Context?
    ) {
        let line = line(of: Syntax(binding))
        // `let a, b: any P` gives `a` the type written after `b`.
        let annotation = binding.initializer == nil
            ? siblings.lazy.compactMap(\.typeAnnotation).first?.type
            : binding.typeAnnotation?.type
        if let annotation {
            let protocols = scan.resolver.protocols(in: annotation, generics: generics)
            let qualified = owner.map { "\($0.ownerName).\(name)" } ?? name
            var bindingValue = ProtocolBinding.other
            if protocols.isEmpty == false {
                let client = scan.addClient(ProtocolClient(
                    kind: .property, name: qualified, protocols: protocols,
                    filePath: filePath, line: line, liveWhenReferenced: nil
                ))
                bindingValue = .clients([client])
            }
            scan.recordMember(name, in: owner?.ownerName, binding: bindingValue)
        } else {
            scan.pendingInferred.append(PendingInferredMember(
                name: name, typeName: owner?.ownerName, initializer: binding.initializer?.value,
                keyPathMemberName: Self.keyPathMemberName(in: decl.attributes),
                filePath: filePath, line: line
            ))
        }
        if case .protocolExtension(let extended, let protocols)? = owner {
            scan.extensionMembers[binding.id] = scan.addClient(ProtocolClient(
                kind: .extensionMember, name: "extension \(extended).\(name)", protocols: protocols,
                filePath: filePath, line: line, liveWhenReferenced: name
            ))
        }
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        generics.push(scan.resolver.genericFrame(
            parameters: node.genericParameterClause, whereClause: node.genericWhereClause, outer: generics
        ))
        let name = node.name.text
        let parameters = node.signature.parameterClause.parameters
        scan.callables[name, default: []].append(signature(of: parameters))
        let owner = placement(of: Syntax(node)).owner
        let labels = parameters.map { "\($0.firstName.text):" }.joined()
        let display = "\(owner.map { "\($0.ownerName)." } ?? "")\(name)(\(labels))"
        if let returnType = node.signature.returnClause?.type {
            let protocols = scan.resolver.protocols(in: returnType, generics: generics)
            if protocols.isEmpty == false {
                let producer = scan.addClient(ProtocolClient(
                    kind: .producer, name: display, protocols: protocols,
                    filePath: filePath, line: line(of: Syntax(node)), liveWhenReferenced: nil
                ))
                scan.producers[name, default: []].insert(producer)
            }
        }
        recordExtensionMember(Syntax(node), owner: owner, display: display, trigger: name)
        return .visitChildren
    }

    override func visitPost(_ _: FunctionDeclSyntax) {
        generics.pop()
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        generics.push(scan.resolver.genericFrame(
            parameters: node.genericParameterClause, whereClause: node.genericWhereClause, outer: generics
        ))
        let owner = placement(of: Syntax(node)).owner
        if let owner {
            scan.initializers[owner.ownerName, default: []]
                .append(signature(of: node.signature.parameterClause.parameters))
        }
        // An initializer is reached as `Type(…)`, which names no member, so it is always live.
        recordExtensionMember(Syntax(node), owner: owner, display: "init", trigger: nil)
        return .visitChildren
    }

    override func visitPost(_ _: InitializerDeclSyntax) {
        generics.pop()
    }

    override func visit(_ node: SubscriptDeclSyntax) -> SyntaxVisitorContinueKind {
        generics.push(scan.resolver.genericFrame(
            parameters: node.genericParameterClause, whereClause: node.genericWhereClause, outer: generics
        ))
        recordExtensionMember(
            Syntax(node), owner: placement(of: Syntax(node)).owner, display: "subscript", trigger: nil
        )
        return .visitChildren
    }

    override func visitPost(_ _: SubscriptDeclSyntax) {
        generics.pop()
    }

    // MARK: - Helpers

    private func recordExtensionMember(_ node: Syntax, owner: Context?, display: String, trigger: String?) {
        guard case .protocolExtension(_, let protocols)? = owner else { return }
        scan.extensionMembers[node.id] = scan.addClient(ProtocolClient(
            kind: .extensionMember, name: "extension \(display)", protocols: protocols,
            filePath: filePath, line: line(of: node), liveWhenReferenced: trigger
        ))
    }

    private func signature(of parameters: FunctionParameterListSyntax) -> CallableSignature {
        CallableSignature(parameters: parameters.map { parameter in
            // A variadic parameter is an array; `ProtocolTypePosition` calls it opaque.
            let protocols = parameter.ellipsis == nil
                ? scan.resolver.protocols(in: parameter.type, generics: generics)
                : []
            return CallableSignature.Parameter(label: parameter.firstName.text, protocols: protocols)
        })
    }

    /// A struct with no initializer in its body gets one taking each stored property.
    private func recordMemberwiseInitializer(of node: StructDeclSyntax) {
        let members = node.memberBlock.members.map(\.decl)
        guard members.contains(where: { $0.is(InitializerDeclSyntax.self) }) == false else { return }
        var parameters: [CallableSignature.Parameter] = []
        for variable in members.compactMap({ $0.as(VariableDeclSyntax.self) })
        where ProtocolDeclarationScan.isStatic(variable.modifiers) == false {
            for binding in variable.bindings where Self.isMemberwiseParameter(binding, in: variable) {
                guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else { continue }
                let protocols = binding.typeAnnotation.map {
                    scan.resolver.protocols(in: $0.type, generics: generics)
                } ?? []
                parameters.append(.init(label: pattern.identifier.text, protocols: protocols))
            }
        }
        scan.initializers[node.name.text, default: []].append(CallableSignature(parameters: parameters))
    }

    /// Stored (no accessors, or only observers), and not a `let` that is already initialised.
    private static func isMemberwiseParameter(_ binding: PatternBindingSyntax, in variable: VariableDeclSyntax) -> Bool {
        if variable.bindingSpecifier.tokenKind == .keyword(.let), binding.initializer != nil {
            return false
        }
        guard let accessors = binding.accessorBlock?.accessors else { return true }
        guard case .accessors(let list) = accessors else { return false }
        return list.allSatisfy { ["willSet", "didSet"].contains($0.accessorSpecifier.text) }
    }

    /// The last component of a key path passed to a property's attribute:
    /// `orderStore` for `@Environment(\.orderStore)` or `@Dependency(\.orderStore)`.
    static func keyPathMemberName(in attributes: AttributeListSyntax) -> String? {
        for case .attribute(let attribute) in attributes {
            guard case .argumentList(let arguments)? = attribute.arguments,
                  let keyPath = arguments.first?.expression.as(KeyPathExprSyntax.self) else {
                continue
            }
            for component in keyPath.components.reversed() {
                if case .property(let property) = component.component {
                    return property.declName.baseName.text
                }
            }
        }
        return nil
    }

    /// Where a declaration sits. Locals are read by `ProtocolClientWalker`, not here.
    private enum Placement {
        case member(Context)
        case topLevel
        case local

        var owner: Context? {
            guard case .member(let context) = self else { return nil }
            return context
        }
    }

    private func placement(of node: Syntax) -> Placement {
        if node.parent?.is(MemberBlockItemSyntax.self) == true, let context = contexts.last {
            return .member(context)
        }
        if node.parent?.is(CodeBlockItemSyntax.self) == true,
           node.parent?.parent?.parent?.is(SourceFileSyntax.self) == true {
            return .topLevel
        }
        return .local
    }

    private func push(_ context: Context, frame: [String: Set<String>]) {
        contexts.append(context)
        generics.push(frame)
    }

    private func pop() {
        contexts.removeLast()
        generics.pop()
    }

    private func line(of node: Syntax) -> Int {
        converter.location(for: node.positionAfterSkippingLeadingTrivia).line
    }
}
