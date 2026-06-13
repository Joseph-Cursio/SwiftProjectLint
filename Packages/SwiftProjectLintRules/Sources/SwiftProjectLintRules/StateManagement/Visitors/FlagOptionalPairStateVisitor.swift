import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects a State struct that pairs a **transition Bool flag** (a stored
/// `Bool` whose name reads like `isLoading` / `isFetching` / `isRefreshing` /
/// `isActive`) with an **Optional** "result" property.
///
/// `isLoading` describes a *change in progress*; the optional describes the
/// *current value*. They are orthogonal, so the struct can represent illegal
/// combinations — loading-with-a-stale-result and loaded-but-flag-off — that no
/// invariant between two independent fields can rule out. The fix is to model
/// the pair as a single sum type, e.g.
/// `enum Status { case idle, loading, loaded(Value) }`, which makes the illegal
/// combinations unrepresentable.
///
/// **Motivated by TCA example code.** PointFree's case studies model exactly
/// this shape: `ScreenA` (`isLoading` + `fact: String?`) keeps the fact after
/// loading completes, and `NavigateAndLoad` (`isNavigationActive` +
/// `optionalCounter: Counter.State?`). Both declare the flag with an *inferred*
/// type (`var isLoading = false`), so detection treats a boolean-literal
/// initializer as a `Bool`. The code is not buggy, so this is an opt-in
/// `.info` refactor suggestion rather than an error.
final class FlagOptionalPairStateVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    // MARK: - Visit

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let flag = firstTransitionFlag(in: node),
              hasOptionalProperty(in: node) else {
            return .visitChildren
        }
        addIssue(
            node: Syntax(node),
            variables: ["typeName": node.name.text, "flag": flag]
        )
        return .visitChildren
    }

    // MARK: - Detection

    /// Returns the name of the first stored `Bool` property whose name reads
    /// like a transition flag, or `nil` if there is none.
    private func firstTransitionFlag(in node: StructDeclSyntax) -> String? {
        for member in node.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            for binding in varDecl.bindings {
                guard binding.accessorBlock == nil, // stored, not computed
                      let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                      isTransitionFlagName(name),
                      isBoolBinding(binding) else {
                    continue
                }
                return name
            }
        }
        return nil
    }

    /// Returns `true` when any stored property is declared with an Optional type.
    private func hasOptionalProperty(in node: StructDeclSyntax) -> Bool {
        node.memberBlock.members.contains { member in
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { return false }
            return varDecl.bindings.contains { binding in
                binding.typeAnnotation?.type.is(OptionalTypeSyntax.self) ?? false
            }
        }
    }

    /// Name heuristic for an in-flight / transition flag. `interactive` and
    /// `inactive` are excluded so they don't trip the `active` match.
    private func isTransitionFlagName(_ name: String) -> Bool {
        let lower = name.lowercased()
        if lower.contains("loading") || lower.contains("fetching") || lower.contains("refreshing") {
            return true
        }
        return lower.contains("active")
            && lower.contains("interactive") == false
            && lower.contains("inactive") == false
    }

    /// Returns `true` when the binding's type is `Bool` — either by explicit
    /// annotation or, for an inferred type, by a boolean-literal initializer
    /// (`var isLoading = false`).
    private func isBoolBinding(_ binding: PatternBindingSyntax) -> Bool {
        if let typeAnnotation = binding.typeAnnotation {
            return typeAnnotation.type.as(IdentifierTypeSyntax.self)?.name.text == "Bool"
        }
        return binding.initializer?.value.is(BooleanLiteralExprSyntax.self) ?? false
    }
}
