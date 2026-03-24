import Foundation

/// A registrar for the Print Statement pattern.
///
/// Provides the pattern for detecting `print()` and `debugPrint()` calls.
struct PrintStatement: PatternRegistrarProtocol {


    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .printStatement,
            visitor: PrintStatementVisitor.self,
            severity: .info,
            category: .codeQuality,
            messageTemplate: "print() statement found — consider using os.Logger or removing before release",
            suggestion: "Use os.Logger for structured logging or remove print statements before release.",
            description: "Detects print() and debugPrint() calls that should be replaced with "
                + "structured logging or removed before shipping to production."
        )
    }
}
