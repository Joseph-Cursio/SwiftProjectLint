import SwiftSyntax

/// What the compiler conforms a type to without being asked.
///
/// This exists so that the two places needing the answer give the same one. The candidate gate
/// (`EquatableConformanceCollector`) already knew that a payload-free enum is `Equatable`
/// whether or not it says so; `MissingEquatableOnStateTypeVisitor` did not, and told readers to
/// add a conformance the language had already given them. A rule and a gate disagreeing about
/// the same language guarantee is the kind of drift a shared helper is for.
public enum SynthesizedConformance {

    /// Whether `node` is `Equatable` and `Hashable` without declaring either.
    ///
    /// True for an enum whose every case is payload-free. The compiler synthesises both, and a
    /// raw-value enum cannot carry associated values, so this covers `enum R: String` and bare
    /// `enum C { case a, b }` alike.
    ///
    /// An enum *with* associated values is `Equatable` only when it declares it — and only if
    /// every payload is itself `Equatable`, which the compiler checks — so those stay gated on
    /// the declared conformance.
    ///
    /// This is a language guarantee rather than a heuristic, so it cannot admit a type that is
    /// not really `Equatable`.
    public static func isImplicitlyEquatable(_ node: EnumDeclSyntax) -> Bool {
        for member in node.memberBlock.members {
            guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else { continue }
            for element in caseDecl.elements where element.parameterClause != nil {
                return false
            }
        }
        return true
    }
}
