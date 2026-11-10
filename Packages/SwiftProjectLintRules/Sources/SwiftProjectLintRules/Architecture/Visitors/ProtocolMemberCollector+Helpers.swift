import SwiftSyntax

extension ProtocolMemberCollector {
    // MARK: - Helpers

    func recordExtensionMember(_ node: Syntax, owner: Context?, display: String, trigger: String?) {
        guard case .protocolExtension(_, let protocols)? = owner else { return }
        scan.extensionMembers[node.id] = scan.addClient(ProtocolClient(
            kind: .extensionMember, name: "extension \(display)", protocols: protocols,
            filePath: filePath, line: line(of: node), liveWhenReferenced: trigger
        ))
    }

    func signature(of parameters: FunctionParameterListSyntax) -> CallableSignature {
        CallableSignature(parameters: parameters.map { parameter in
            // A variadic parameter is an array; `ProtocolTypePosition` calls it opaque.
            let protocols = parameter.ellipsis == nil
                ? scan.resolver.protocols(in: parameter.type, generics: generics)
                : []
            return CallableSignature.Parameter(label: parameter.firstName.text, protocols: protocols)
        })
    }

    /// A struct with no initializer in its body gets one taking each stored property.
    func recordMemberwiseInitializer(of node: StructDeclSyntax) {
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
    private static func isMemberwiseParameter(
        _ binding: PatternBindingSyntax,
        in variable: VariableDeclSyntax
    ) -> Bool {
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
    enum Placement {
        case member(Context)
        case topLevel
        case local

        var owner: Context? {
            guard case .member(let context) = self else { return nil }
            return context
        }
    }

    func placement(of node: Syntax) -> Placement {
        if node.parent?.is(MemberBlockItemSyntax.self) == true, let context = contexts.last {
            return .member(context)
        }
        if node.parent?.is(CodeBlockItemSyntax.self) == true,
           node.parent?.parent?.parent?.is(SourceFileSyntax.self) == true {
            return .topLevel
        }
        return .local
    }

    func push(_ context: Context, frame: [String: Set<String>]) {
        contexts.append(context)
        generics.push(frame)
    }

    func pop() {
        contexts.removeLast()
        generics.pop()
    }

    func line(of node: Syntax) -> Int {
        converter.location(for: node.positionAfterSkippingLeadingTrivia).line
    }
}
