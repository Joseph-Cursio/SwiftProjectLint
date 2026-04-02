import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// Registers patterns related to code quality and best practices.
/// This registrar handles patterns for magic numbers, long functions, hardcoded strings, and documentation.

class CodeQuality: BasePatternRegistrar {
    override func registerPatterns() {
        registry.register(patterns: inlinePatterns)
        registerDelegatedPatterns()
    }

    private var inlinePatterns: [SyntaxPattern] {
        [
            SyntaxPattern(
                name: .magicNumber,
                visitor: MagicNumberVisitor.self,
                severity: .info,
                category: .codeQuality,
                messageTemplate: "Magic number detected: {number}",
                suggestion: "Define a named constant instead of using magic numbers",
                description: "Detects hardcoded numbers that should be named constants"
            ),
            SyntaxPattern(
                name: .magicLayoutNumber,
                visitor: MagicNumberVisitor.self,
                severity: .info,
                category: .codeQuality,
                messageTemplate: "Magic layout number detected: {number}",
                suggestion: "Extract layout value to a named design token",
                description: "Detects hardcoded numbers in SwiftUI layout modifiers. Disabled by default."
            ),
            SyntaxPattern(
                name: .hardcodedStrings,
                visitor: HardcodedStringVisitor.self,
                severity: .info,
                category: .codeQuality,
                messageTemplate: "Consider localizing hardcoded text in user-facing view",
                suggestion: "Use NSLocalizedString or String(localized:) for user-facing text",
                description: "Detects hardcoded strings in SwiftUI views that should be localized. "
                    + "Skips URLs, SF Symbol names, and systemImage/systemName arguments."
            ),
            SyntaxPattern(
                name: .missingDocumentation,
                visitor: DocumentationVisitor.self,
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
                suggestion: "Rename to '{protocolName}Protocol' to improve clarity",
                description: "Detects protocols whose names don't end with 'Protocol' suffix"
            ),
            SyntaxPattern(
                name: .actorNamingSuffix,
                visitor: NamingConventionVisitor.self,
                severity: .info,
                category: .codeQuality,
                messageTemplate: "Actor '{actorName}' is not suffixed with 'Actor'",
                suggestion: "Rename to '{actorName}Actor' to make isolation visible",
                description: "Detects actors whose names don't end with 'Actor' suffix"
            ),
            SyntaxPattern(
                name: .actorAgentName,
                visitor: NamingConventionVisitor.self,
                severity: .info,
                category: .codeQuality,
                messageTemplate: "Actor '{actorName}' has a passive name",
                suggestion: "Use an agent-noun name (-er/-or) or add the 'Actor' suffix",
                description: "Detects actors with passive-sounding names that give no signal "
                    + "of concurrency isolation. Fires only when the name lacks both "
                    + "an agent-noun suffix (-er/-or) and the 'Actor' suffix."
            ),
            SyntaxPattern(
                name: .nonActorAgentSuffix,
                visitor: NamingConventionVisitor.self,
                severity: .info,
                category: .codeQuality,
                messageTemplate: "'{name}' has an agent-noun name but is not an actor",
                suggestion: "Declare as 'actor {name}' or rename to '{name}Agent'",
                description: "Opt-in: detects classes/structs with agent-noun names "
                    + "(-er/-or/-ar) that are neither Swift actors "
                    + "nor suffixed with 'Agent'."
            ),
            SyntaxPattern(
                name: .propertyWrapperNamingSuffix,
                visitor: NamingConventionVisitor.self,
                severity: .info,
                category: .codeQuality,
                messageTemplate: "Property wrapper '{wrapperName}' is not suffixed with 'Wrapper'",
                suggestion: "Rename to '{wrapperName}Wrapper' to clarify its role",
                description: "Detects property wrappers whose names don't end with 'Wrapper'"
            ),
            SyntaxPattern(
                name: .macroNegation,
                visitor: ExpectNegationVisitor.self,
                severity: .warning,
                category: .codeQuality,
                messageTemplate: "#expect/#require(!{expression}) negates inside the macro",
                suggestion: "Use == false instead for better failure diagnostics",
                description: "Detects #expect(!expr) and #require(!expr) which defeat "
                    + "Swift Testing's sub-expression capture"
            )
        ]
    }

    private func registerDelegatedPatterns() {
        registry.register(registrars: [
            LowercasedContains(),
            MultipleTypesPerFile(),
            ActorReentrancy(),
            ForceTry(),
            ForceUnwrap(),
            PrintStatement(),
            EmptyCatch(),
            TodoComment(),
            TaskDetached(),
            AsyncLetUnused(),
            ButtonClosureWrapping(),
            NonisolatedUnsafe(),
            TaskYieldOffload(),
            SwallowedTaskError(),
            CouldBePrivate(),
            PublicInAppTarget(),
            CouldBePrivateMember(),
            ProtocolCouldBePrivate(),
            TestMissingRequire(),
            TestMissingAssertion(),
            TestMissingExpect(),
            SwiftLintSuppression(),
            SwiftProjectLintSuppression(),
            VariableShadowing()
        ])
    }
}
