import SwiftSyntax

/// A fast SyntaxVisitor that collects the names of `View` types reading
/// `@Environment(SomeType.self)` — the `@Observable` form, which has **no default value**.
///
/// Used as a project-wide pre-scan so that a per-file visitor can tell whether a view is
/// capable of the trap at all. Evaluating such a view's `body` outside SwiftUI does not
/// fail, it traps inside `EnvironmentValues.subscript.getter`, killing the test process.
/// The keypath form `@Environment(\.someKey)` is not collected: it resolves to a default
/// and evaluates out-of-tree without complaint.
///
/// The distinction matters because it is the whole precondition of
/// `ViewHostingBeforeInspectionVisitor`. That rule reports a test that hosts before it
/// inspects, and the ordering is only dangerous for a view in this set — every other view
/// inspects out-of-tree perfectly well, which is ViewInspector's ordinary mode of
/// operation. Without this catalog the rule fires on the ordering alone and reports an
/// error against tests that pass and will keep passing.
public final class ObservableEnvironmentViewCollector: SyntaxVisitor, TypeCollectorProtocol {
    public var collectedTypes: Set<String> { viewNames }

    /// Names of `View` conformers that read at least one `@Environment(SomeType.self)`.
    private(set) var viewNames: Set<String> = []

    public init() {
        super.init(viewMode: .sourceAccurate)
    }

    override public func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        if Self.conformsToView(node), Self.readsObservableEnvironment(node) {
            viewNames.insert(node.name.text)
        }
        return .visitChildren
    }

    private static func conformsToView(_ node: StructDeclSyntax) -> Bool {
        guard let inheritance = node.inheritanceClause else { return false }
        return inheritance.inheritedTypes.contains { inherited in
            inherited.type.as(IdentifierTypeSyntax.self)?.name.text == "View"
        }
    }

    /// True when any stored property carries `@Environment(SomeType.self)`.
    ///
    /// The argument has to be a member access ending in `.self` on a capitalised base —
    /// `@Environment(\.dependencies)` is a keypath expression and does not match, which is
    /// the case this collector exists to exclude.
    private static func readsObservableEnvironment(_ node: StructDeclSyntax) -> Bool {
        for member in node.memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self) else { continue }
            for attribute in variable.attributes {
                guard let attr = attribute.as(AttributeSyntax.self),
                      attr.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "Environment",
                      let args = attr.arguments?.as(LabeledExprListSyntax.self),
                      let first = args.first?.expression.as(MemberAccessExprSyntax.self),
                      first.declName.baseName.text == "self",
                      let base = first.base?.as(DeclReferenceExprSyntax.self),
                      base.baseName.text.first?.isUppercase == true else {
                    continue
                }
                return true
            }
        }
        return false
    }
}
