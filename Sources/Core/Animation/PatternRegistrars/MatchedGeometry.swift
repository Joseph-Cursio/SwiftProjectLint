import Foundation

/// A registrar for the matched geometry effect misuse pattern.
///
/// Provides the pattern for detecting undeclared namespaces and duplicate IDs
/// in `matchedGeometryEffect` calls.
struct MatchedGeometry: PatternRegistrarProtocol {


    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .matchedGeometryEffectMisuse,
            visitor: MatchedGeometryVisitor.self,
            severity: .warning,
            category: .animation,
            messageTemplate: "matchedGeometryEffect misuse detected: undeclared namespace or duplicate ID.",
            suggestion: "Declare a @Namespace variable in the enclosing view and use unique IDs per namespace.",
            description: "Detects matchedGeometryEffect calls that reference undeclared namespaces or " +
                "reuse the same ID within a namespace, both of which cause undefined animation behavior."
        )
    }
}
