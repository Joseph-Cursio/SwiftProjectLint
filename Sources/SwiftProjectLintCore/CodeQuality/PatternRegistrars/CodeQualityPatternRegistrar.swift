import Foundation

/// Registers patterns related to code quality and best practices.
/// This registrar handles patterns for magic numbers, long functions, hardcoded strings, and documentation.

class CodeQualityPatternRegistrar: PatternRegistrarWithVisitorProto {

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
            ),
            SyntaxPattern(
                name: .protocolNamingSuffix,
                visitor: NamingConventionVisitor.self,
                severity: .info,
                category: .codeQuality,
                messageTemplate: "Protocol '{protocolName}' is not suffixed with 'Protocol'",
                suggestion: "Rename to '{protocolName}Protocol' to improve clarity for both humans and LLMs",
                description: "Detects protocols whose names don't end with 'Protocol' suffix"
            ),
            SyntaxPattern(
                name: .actorNamingSuffix,
                visitor: NamingConventionVisitor.self,
                severity: .info,
                category: .codeQuality,
                messageTemplate: "Actor '{actorName}' is not suffixed with 'Actor'",
                suggestion: "Rename to '{actorName}Actor' to make isolation semantics visible at usage sites",
                description: "Detects actors whose names don't end with 'Actor' suffix"
            ),
            SyntaxPattern(
                name: .propertyWrapperNamingSuffix,
                visitor: NamingConventionVisitor.self,
                severity: .info,
                category: .codeQuality,
                messageTemplate: "Property wrapper '{wrapperName}' is not suffixed with 'Wrapper'",
                suggestion: "Rename to '{wrapperName}Wrapper' to clarify its role as a property wrapper",
                description: "Detects property wrappers whose names don't end with 'Wrapper' suffix"
            )
        ]
        registry.register(patterns: patterns)
    }
}
