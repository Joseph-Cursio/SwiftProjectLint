import Foundation

/// A registrar for the Force Unwrap pattern.
///
/// Provides the pattern for detecting force unwrap (`!`) expressions that crash on nil.
struct ForceUnwrap: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .forceUnwrap,
            visitor: ForceUnwrapVisitor.self,
            severity: .info,
            category: .codeQuality,
            messageTemplate: "Force unwrap (!) will crash on nil — consider using if-let, guard-let, or nil-coalescing",
            suggestion: "Use if-let, guard-let, or the nil-coalescing operator (??) for safe unwrapping.",
            description: "Detects force unwrap expressions that will crash at runtime if the "
                + "optional value is nil."
        )
    }
}
