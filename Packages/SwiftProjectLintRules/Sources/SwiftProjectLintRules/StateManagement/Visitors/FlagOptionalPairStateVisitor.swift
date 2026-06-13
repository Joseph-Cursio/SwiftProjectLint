import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects a State struct that pairs a **Bool flag** with an **optional or
/// collection** property whose presence the flag shadows — an
/// "impossible state combination" where the flag and the data it tracks can be
/// set inconsistently.
///
/// Two tiers, tuned for precision:
///
/// 1. **Transition flags** (`isLoading` / `isFetching` / `isRefreshing` /
///    `isActive`) pair with *any* optional/collection. The verb names are
///    specific enough that "a loading flag plus some data" is the smell —
///    e.g. `isLoading` + `results: [User]`, where `isLoading` may stay true
///    after results arrive.
/// 2. **`has<X>` / `is<X>` flags** must *name-correlate* with a pairable
///    property — e.g. `hasError` + `errorMessage` (`error` echoes across both).
///    The correlation requirement keeps `isEnabled` + an unrelated optional
///    from firing.
///
/// `isLoading` describes a *change in progress*; the data describes the
/// *current value*. They are orthogonal, so the struct can represent illegal
/// combinations — loading-with-a-stale-result, loaded-but-flag-off,
/// error-flag-without-message — that no invariant between two independent
/// fields can rule out. The fix is one source of truth: a sum type
/// (`enum Status { case idle, loading, loaded(Value) }`) or a computed flag
/// (`var hasError: Bool { errorMessage != nil }`).
///
/// **Motivated by TCA example code** (`ScreenA`: `isLoading` + `fact: String?`;
/// `NavigateAndLoad`: `isNavigationActive` + `optionalCounter`) and common
/// session/error shapes (`isLoggedIn` + `currentUser`, `hasError` +
/// `errorMessage`). Such code is usually correct, so this is an opt-in `.info`
/// refactor suggestion, not an error.
///
/// *Known gap:* a flag with no shared name token, e.g. `isLoggedIn` +
/// `currentUser`, is not flagged — detecting it precisely needs type-level
/// semantics, and a blanket "`is*` Bool + any optional" rule would be too noisy.
final class FlagOptionalPairStateVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    // MARK: - Visit

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        if let flag = firstFlag(in: node) {
            addIssue(
                node: Syntax(node),
                variables: ["typeName": node.name.text, "flag": flag]
            )
        }
        return .visitChildren
    }

    // MARK: - Detection

    /// Returns the name of the first stored `Bool` flag that pairs with a
    /// pairable (optional / collection) property under either tier, or `nil`.
    private func firstFlag(in node: StructDeclSyntax) -> String? {
        let pairable = pairableProperties(in: node)
        guard pairable.isEmpty == false else { return nil }

        for member in node.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            for binding in varDecl.bindings {
                guard binding.accessorBlock == nil, // stored, not computed
                      let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                      isBoolBinding(binding) else {
                    continue
                }
                // Tier 1: a transition verb pairs with ANY optional/collection.
                if isTransitionFlagName(name) {
                    return name
                }
                // Tier 2: a has<X>/is<X> flag must name-correlate with a pairable property.
                if let stem = correlationStem(name),
                   pairable.contains(where: { $0.contains(stem) }) {
                    return name
                }
            }
        }
        return nil
    }

    /// Lowercased names of stored properties whose declared type is Optional
    /// (`T?`) or a collection (`[T]` / `Array` / `IdentifiedArray(Of)`).
    private func pairableProperties(in node: StructDeclSyntax) -> [String] {
        var names: [String] = []
        for member in node.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            for binding in varDecl.bindings {
                guard binding.accessorBlock == nil,
                      let type = binding.typeAnnotation?.type,
                      isPairableType(type),
                      let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else {
                    continue
                }
                names.append(name.lowercased())
            }
        }
        return names
    }

    /// Optional (`T?`) or collection (`[T]` / `Array<T>` / `IdentifiedArrayOf<T>`).
    private func isPairableType(_ type: TypeSyntax) -> Bool {
        if type.is(OptionalTypeSyntax.self) { return true }
        if type.is(ArrayTypeSyntax.self) { return true }
        if let ident = type.as(IdentifierTypeSyntax.self) {
            switch ident.name.text {
            case "Array", "IdentifiedArray", "IdentifiedArrayOf": return true
            default: return false
            }
        }
        return false
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

    /// For a `has<Stem>` / `is<Stem>` flag (camelCase boundary required), returns
    /// the lowercased `<Stem>` if it's at least 4 characters — otherwise `nil`.
    /// `hasError` → `"error"`; `isSelected` → `"selected"`; `issued` → `nil`
    /// (no camelCase boundary); `isOn` → `nil` (stem too short).
    private func correlationStem(_ name: String) -> String? {
        func stem(after prefix: String) -> String? {
            guard name.hasPrefix(prefix), name.count > prefix.count else { return nil }
            let afterIndex = name.index(name.startIndex, offsetBy: prefix.count)
            guard name[afterIndex].isUppercase else { return nil }
            let stem = String(name[afterIndex...]).lowercased()
            return stem.count >= 4 ? stem : nil
        }
        return stem(after: "has") ?? stem(after: "is")
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
