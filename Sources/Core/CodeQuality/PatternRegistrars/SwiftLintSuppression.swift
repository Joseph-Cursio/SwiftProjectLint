import Foundation

/// A registrar for the SwiftLint suppression comment pattern.
///
/// Detects `swiftlint:disable` and `swiftlint:disable:next` comments
/// that suppress SwiftLint rules, which may hide real issues.
struct SwiftLintSuppression: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .swiftlintSuppression,
            visitor: SwiftLintSuppressionVisitor.self,
            severity: .warning,
            category: .codeQuality,
            messageTemplate: "SwiftLint suppression: {directive} {rule}",
            suggestion: "Fix the underlying issue instead of suppressing the SwiftLint rule.",
            description: "Detects swiftlint:disable and swiftlint:disable:next comments "
                + "that suppress SwiftLint rules, which may hide real issues."
        )
    }
}
