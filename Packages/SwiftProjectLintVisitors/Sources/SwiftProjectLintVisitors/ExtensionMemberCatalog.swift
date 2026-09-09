import SwiftSyntax

/// Per type, the member names declared in `extension` blocks anywhere in the project.
///
/// ## Why this exists
///
/// A per-file visitor that reasons about *what a type's members read* is only as good as its view
/// of the type. Swift lets a type's members be spread across files, and this corpus does it
/// routinely: `RuleAuditView` declares its state in `RuleAuditView.swift` and its subviews in
/// `RuleAuditView+Subviews.swift`; `ContentView`, `OnboardingView`, `RuleDetailView` and
/// `ViolationInspectorView` are all split the same way.
///
/// `ComputedPropertyViewVisitor` computes each view property's transitive dependency on the type's
/// stored inputs and reports the ones that read a **strict subset**. When a property forwards to a
/// sibling the file cannot see, that sibling contributes no dependencies at all — so the property
/// reads as depending on *nothing*, which is the strongest possible pass of the gate. **The gate
/// was at its most confident exactly where it knew least.**
///
/// Measured on SwiftLintRuleStudio: 7 of the rule's 20 findings there sat in types split across
/// files. `RuleAuditView.auditResultsView` is the clearest — it composes two extension properties
/// that between them read six stored properties and call four instance methods, so with the whole
/// type in view the capture gate declines it outright.
///
/// ## What it is not
///
/// It carries names, not bodies. That is enough for the only question asked of it — *does this
/// property reach a member this file cannot see?* — and a "yes" makes the dependency set unknown,
/// which is not a subset claim the rule can make. Completing the dependency graph across files
/// would need the bodies too, and no rule has yet needed that.
///
/// An empty catalog means no pre-scan ran (a visitor driven straight by a unit test) or the
/// project declares no extensions. Both are correctly treated as "nothing is hidden": the gate is
/// a *decline*, so an absent catalog leaves behaviour exactly as it was.
public struct ExtensionMemberCatalog: Sendable, Equatable {

    private let membersByType: [String: Set<String>]

    /// The catalog a caller with no pre-scan gets: no type has hidden members.
    public static let empty = Self(membersByType: [:])

    public init(membersByType: [String: Set<String>]) {
        self.membersByType = membersByType
    }

    /// Member names declared in any `extension` of `typeName`, project-wide.
    public func members(on typeName: String) -> Set<String> {
        membersByType[typeName] ?? []
    }

    public var isEmpty: Bool { membersByType.isEmpty }

    /// Merges the per-file results of ``ExtensionMemberCollector``.
    public static func merging(_ collected: [[String: Set<String>]]) -> Self {
        var merged: [String: Set<String>] = [:]
        for file in collected {
            for (typeName, names) in file {
                merged[typeName, default: []].formUnion(names)
            }
        }
        return Self(membersByType: merged)
    }

    /// Builds the catalog over every parsed source in the project.
    public static func build(from sources: [SourceFileSyntax]) -> Self {
        merging(sources.map { source in
            let collector = ExtensionMemberCollector(viewMode: .sourceAccurate)
            collector.walk(source)
            return collector.membersByType
        })
    }
}

/// Gathers the member names an `extension` block declares, keyed by the extended type.
///
/// The key is the extended type's leading identifier, so `extension Array<Int>` and
/// `extension Array` both key on `Array`. Nested spellings (`extension Outer.Inner`) key on the
/// last component, which is what a per-file visitor visiting `Inner` has to match against.
public final class ExtensionMemberCollector: SyntaxVisitor {
    private(set) var membersByType: [String: Set<String>] = [:]

    override public func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let name = Self.extendedTypeName(node.extendedType) else { return .visitChildren }
        membersByType[name, default: []].formUnion(Self.memberNames(in: node.memberBlock))
        return .visitChildren
    }

    /// The name an extension extends, or `nil` for a spelling this cannot read.
    public static func extendedTypeName(_ type: TypeSyntax) -> String? {
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            return identifier.name.text
        }
        if let member = type.as(MemberTypeSyntax.self) {
            return member.name.text
        }
        return nil
    }

    /// The `var` and `func` names an extension's body declares. Nested types are not descended
    /// into: their members belong to the nested type, not to the extended one.
    public static func memberNames(in memberBlock: MemberBlockSyntax) -> Set<String> {
        var names: Set<String> = []
        for member in memberBlock.members {
            if let function = member.decl.as(FunctionDeclSyntax.self) {
                names.insert(function.name.text)
            }
            if let variable = member.decl.as(VariableDeclSyntax.self) {
                for binding in variable.bindings {
                    if let identifier = binding.pattern.as(IdentifierPatternSyntax.self) {
                        names.insert(identifier.identifier.text)
                    }
                }
            }
        }
        return names
    }
}
