import Foundation

/// A registrar for the lowercased-contains pattern.
///
/// Provides the pattern for detecting `.lowercased().contains(...)` calls that should use
/// `localizedStandardContains()` instead.
struct LowercasedContains: PatternRegistrar {


    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .lowercasedContains,
            visitor: LowercasedContainsVisitor.self,
            severity: .warning,
            category: .codeQuality,
            messageTemplate: ".lowercased().contains() performs naive case-insensitive search",
            suggestion: "Use .localizedStandardContains() instead — it handles case, diacritics, "
                + "and locale-specific rules automatically.",
            description: "Detects .lowercased().contains() and .uppercased().contains() calls "
                + "that should use localizedStandardContains() for proper locale-aware search."
        )
    }
}
