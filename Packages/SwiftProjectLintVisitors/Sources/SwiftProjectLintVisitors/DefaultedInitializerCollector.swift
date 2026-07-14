import SwiftSyntax

/// A project-wide pre-scan collecting the types whose initialiser has **defaulted parameters**.
///
/// ## Why this is the load-bearing half of `lossyStructRebuild`
///
/// Rebuilding a value field-by-field is not, in itself, a bug. It becomes one only when a forgotten
/// argument can *silently* take a default:
///
///     Suggestion(templateName: s.templateName, …, carrier: s.carrier)
///     //                                            carrierTypeName: ← forgotten
///
/// If every parameter of `Suggestion.init` were **required**, that omission would be a compile error,
/// the mistake would be impossible, and a rule firing on it would be pure noise. Because some
/// parameters have defaults, the omission type-checks and produces a value that renders correctly in
/// every visible respect while quietly missing part of itself.
///
/// **So the defaults are the bug**, and a rule that cannot see them cannot tell a hazard from a habit.
/// That is also why this cannot be a regex rule: the initialiser is usually declared in another file.
///
/// ## What counts
///
/// - An explicit `init` with at least one `= default` parameter.
/// - A struct with **no** explicit `init` and at least one stored property carrying an initialiser
///   (`var count: Int = 0`), because Swift's memberwise init defaults that parameter — the same trap,
///   with nothing written down anywhere.
///
/// Conservative in the safe direction: a type this scan cannot see is simply absent, and the rule
/// stays silent on it.
public final class DefaultedInitializerCollector: SyntaxVisitor, TypeCollectorProtocol {

    public var collectedTypes: Set<String> { defaulted }

    private var defaulted: Set<String> = []

    public init() {
        super.init(viewMode: .sourceAccurate)
    }

    override public func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        record(name: node.name.text, members: node.memberBlock.members)
        return .visitChildren
    }

    override public func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        // A class has no memberwise init, so only an explicit defaulted `init` counts.
        if Self.hasDefaultedInitializer(in: node.memberBlock.members) {
            defaulted.insert(node.name.text)
        }
        return .visitChildren
    }

    override public func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        // `extension Foo { init(…, x: Int = 0) }` — the type gains the hazard from elsewhere.
        if Self.hasDefaultedInitializer(in: node.memberBlock.members) {
            defaulted.insert(node.extendedType.trimmedDescription)
        }
        return .visitChildren
    }

    private func record(name: String, members: MemberBlockItemListSyntax) {
        if Self.hasDefaultedInitializer(in: members) {
            defaulted.insert(name)
            return
        }
        // No explicit init: Swift synthesises a memberwise one, and any stored property with an
        // initialiser becomes a DEFAULTED parameter of it. The trap exists and nobody wrote it down.
        if Self.declaresNoInitializer(in: members), Self.hasDefaultedStoredProperty(in: members) {
            defaulted.insert(name)
        }
    }

    private static func hasDefaultedInitializer(in members: MemberBlockItemListSyntax) -> Bool {
        members.contains { member in
            guard let initializer = member.decl.as(InitializerDeclSyntax.self) else { return false }
            return initializer.signature.parameterClause.parameters
                .contains { $0.defaultValue != nil }
        }
    }

    private static func declaresNoInitializer(in members: MemberBlockItemListSyntax) -> Bool {
        !members.contains { $0.decl.is(InitializerDeclSyntax.self) }
    }

    /// `var count: Int = 0` — stored, with an initialiser. A computed property has an accessor block
    /// and is not a memberwise parameter at all.
    private static func hasDefaultedStoredProperty(in members: MemberBlockItemListSyntax) -> Bool {
        members.contains { member in
            guard let variable = member.decl.as(VariableDeclSyntax.self) else { return false }
            return variable.bindings.contains { binding in
                binding.accessorBlock == nil && binding.initializer != nil
            }
        }
    }
}
