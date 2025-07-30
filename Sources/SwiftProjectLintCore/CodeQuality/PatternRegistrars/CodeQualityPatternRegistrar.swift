import Foundation

/// Registers patterns related to code quality and best practices.
/// This registrar handles patterns for magic numbers, long functions, hardcoded strings, and documentation.
@MainActor
class CodeQualityPatternRegistrar: PatternRegistrarWithVisitorRegistryProtocol {

    let registry: SourcePatternRegistry
    let visitorRegistry: PatternVisitorRegistryProtocol

    init(registry: SourcePatternRegistry, visitorRegistry: PatternVisitorRegistryProtocol) {
        self.registry = registry
        self.visitorRegistry = visitorRegistry
    }

    func registerPatterns() {
        let patterns = [
            SyntaxPattern(
                name: .magicNumber,
                visitor: CodeQualityVisitor.self,
                severity: .info,
                category: .codeQuality,
                messageTemplate: "Magic number detected: {number}",
                suggestion: "Define a named constant instead of using magic numbers",
                description: "Detects hardcoded numbers that should be named constants"
            ),
            SyntaxPattern(
                name: .longFunction,
                visitor: CodeQualityVisitor.self,
                severity: .warning,
                category: .codeQuality,
                messageTemplate: "Function '{functionName}' is too long ({lineCount} lines)",
                suggestion: "Break down the function into smaller, more focused functions",
                description: "Detects functions that exceed recommended length limits"
            ),
            SyntaxPattern(
                name: .hardcodedStrings,
                visitor: CodeQualityVisitor.self,
                severity: .info,
                category: .codeQuality,
                messageTemplate: "Hardcoded string detected: '{string}'",
                suggestion: "Define a named constant or use localization for user-facing strings",
                description: "Detects hardcoded strings that should be constants or localized"
            ),
            SyntaxPattern(
                name: .missingDocumentation,
                visitor: CodeQualityVisitor.self,
                severity: .info,
                category: .codeQuality,
                messageTemplate: "Missing documentation for '{elementName}'",
                suggestion: "Add documentation comments to improve code clarity",
                description: "Detects public APIs and complex functions missing documentation"
            )
        ]
        registry.register(patterns: patterns)
    }
}
