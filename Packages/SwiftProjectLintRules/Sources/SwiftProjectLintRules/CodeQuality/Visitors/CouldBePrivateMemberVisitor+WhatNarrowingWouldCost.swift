import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

extension CouldBePrivateMemberVisitor {
    // MARK: - What narrowing would cost

    /// The finding for `decl`, saying what `private` would cost when the member is a
    /// property-test candidate.
    ///
    /// Narrowing a declaration used only in its own file is sound advice about scope. Applied to a
    /// *pure function*, it is also advice that puts that function beyond the reach of any test:
    /// `@testable import` exposes `internal`, and does not expose `private`. So the linter would be
    /// telling the reader, on the same line, both to property-test a function and to hide it — the
    /// `pureFunctionCandidate` rule flags exactly the declarations this one wants narrowed.
    ///
    /// The finding is not suppressed. Least privilege is a real principle and the reader gets to
    /// weigh it; what they cannot do is weigh a cost nobody told them about.
    func narrowingMessage(for decl: MemberDeclaration) -> String {
        let base = "'\(decl.typeName).\(decl.memberName)' is only used in its declaring file "
            + "and could be private"
        guard propertyTestShape(of: decl) != nil else { return base }

        return base + " — but it is a property-based-test candidate, and `private` puts it beyond "
            + "`@testable import`, which reaches `internal` and no further. Narrowing it means no "
            + "test can call it."
    }

    func narrowingSuggestion(for decl: MemberDeclaration) -> String {
        let base = "Add `private` to '\(decl.memberKind) \(decl.memberName)' to narrow its scope."
        guard propertyTestShape(of: decl) != nil else { return base }

        return "Leave it `internal` if you intend to property-test it, or extract the logic into a "
            + "type of its own — which narrows the surface *and* keeps it testable. Adding "
            + "`private` buys scope at the cost of the test."
    }

    /// The property-test shape of `decl`, when it is a function that qualifies as one.
    private func propertyTestShape(of decl: MemberDeclaration) -> PropertyTestShape? {
        guard let function = decl.node.as(FunctionDeclSyntax.self) else { return nil }
        return PropertyTestCandidacy.shape(of: function, knownEquatableTypes: knownEquatableTypes)
    }
}
