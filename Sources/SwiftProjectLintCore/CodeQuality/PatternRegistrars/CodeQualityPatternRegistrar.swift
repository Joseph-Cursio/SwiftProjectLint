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
                name: .magicLayoutNumber,
                visitor: CodeQualityVisitor.self,
                severity: .info,
                category: .codeQuality,
                messageTemplate: "Magic layout number detected: {number}",
                suggestion: "Extract layout value to a named design token",
                description: "Detects hardcoded numbers in SwiftUI layout modifiers. Disabled by default."
            ),
            SyntaxPattern(
                name: .hardcodedStrings,
                visitor: CodeQualityVisitor.self,
                severity: .info,
                category: .codeQuality,
                messageTemplate: "Consider localizing hardcoded text in user-facing view",
                suggestion: "Use NSLocalizedString or String(localized:) for user-facing text",
                description: "Detects hardcoded strings in SwiftUI views that should be localized. " +
                    "Skips URLs, SF Symbol names, and systemImage/systemName arguments."
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
            ),
            SyntaxPattern(
                name: .expectNegation,
                visitor: ExpectNegationVisitor.self,
                severity: .warning,
                category: .codeQuality,
                messageTemplate: "#expect(!{expression}) negates inside the macro",
                suggestion: "Use #expect({expression} == false) for better failure diagnostics",
                description: "Detects #expect(!expr) which defeats Swift Testing's sub-expression capture"
            )
        ]
        registry.register(patterns: patterns)
        registry.register(pattern: LowercasedContainsPatternRegistrar().pattern)
        registry.register(pattern: MultipleTypesPerFilePatternRegistrar().pattern)
        registry.register(pattern: ActorReentrancyPatternRegistrar().pattern)
        registry.register(pattern: ForceTryPatternRegistrar().pattern)
        registry.register(pattern: ForceUnwrapPatternRegistrar().pattern)
        registry.register(pattern: PrintStatementPatternRegistrar().pattern)
        registry.register(pattern: EmptyCatchPatternRegistrar().pattern)
        registry.register(pattern: TodoCommentPatternRegistrar().pattern)
        registry.register(pattern: TaskDetachedPatternRegistrar().pattern)
        registry.register(pattern: AsyncLetUnusedPatternRegistrar().pattern)
        registry.register(pattern: ButtonClosureWrappingPatternRegistrar().pattern)
        registry.register(pattern: NonisolatedUnsafePatternRegistrar().pattern)
        registry.register(pattern: TaskYieldOffloadPatternRegistrar().pattern)
        registry.register(pattern: SwallowedTaskErrorPatternRegistrar().pattern)
        registry.register(pattern: CouldBePrivatePatternRegistrar().pattern)
        registry.register(pattern: PublicInAppTargetPatternRegistrar().pattern)
        registry.register(pattern: CouldBePrivateMemberPatternRegistrar().pattern)
        registry.register(pattern: ProtocolCouldBePrivatePatternRegistrar().pattern)
    }
}
