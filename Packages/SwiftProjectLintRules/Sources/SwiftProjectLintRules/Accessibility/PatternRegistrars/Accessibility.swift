import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

/// Registers patterns related to accessibility best practices in SwiftUI.
/// This registrar handles patterns for accessibility labels, hints, and color usage.

class Accessibility: BasePatternRegistrar {
    override func registerPatterns() {
        let patterns = [
            SyntaxPattern(
                name: .missingAccessibilityLabel,
                visitor: AccessibilityVisitor.self,
                severity: .warning,
                category: .accessibility,
                messageTemplate: "Missing accessibility label for {element}",
                suggestion: "Add accessibilityLabel modifier to improve accessibility",
                description: "Detects UI elements missing accessibility labels"
            ),
            SyntaxPattern(
                name: .missingAccessibilityHint,
                visitor: AccessibilityVisitor.self,
                severity: .info,
                category: .accessibility,
                messageTemplate: "Consider adding accessibility hint for {element}",
                suggestion: "Add accessibilityHint modifier to provide additional context",
                description: "Detects UI elements that could benefit from accessibility hints"
            ),
            SyntaxPattern(
                name: .inaccessibleColorUsage,
                visitor: AccessibilityVisitor.self,
                severity: .warning,
                category: .accessibility,
                messageTemplate: "Color usage may not be accessible for colorblind users",
                suggestion: "Use semantic colors or add alternative indicators beyond color",
                description: "Detects color usage that may not be accessible to colorblind users"
            ),
            SyntaxPattern(
                name: .iconOnlyButtonMissingLabel,
                visitor: AccessibilityVisitor.self,
                severity: .warning,
                category: .accessibility,
                messageTemplate: "Icon-only button is invisible to VoiceOver",
                suggestion: "Use Button(\"Label\", systemImage: \"name\", action: ...) "
                    + "with .labelStyle(.iconOnly), or add .accessibilityLabel(\"description\")",
                description: "Detects buttons containing only an image without an accessibility label"
            ),
            SyntaxPattern(
                name: .longTextAccessibility,
                visitor: AccessibilityVisitor.self,
                severity: .info,
                category: .accessibility,
                messageTemplate: "Long text content may benefit from accessibility features",
                suggestion: "Add .accessibilityLabel(), .accessibilityHint(), or .accessibilityValue()",
                description: "Detects long text content that could benefit from accessibility modifiers"
            )
        ]
        registry.register(patterns: patterns)

        let onTapGesturePattern = SyntaxPattern(
            name: .onTapGestureInsteadOfButton,
            visitor: OnTapGestureInsteadOfButtonVisitor.self,
            severity: .warning,
            category: .accessibility,
            messageTemplate: "Prefer Button over .onTapGesture for accessibility",
            suggestion: "Replace .onTapGesture { ... } with a Button",
            description: "Detects .onTapGesture calls that bypass button " +
                "accessibility traits, keyboard focus, and haptic feedback"
        )
        registry.register(patterns: [onTapGesturePattern])

        let tapTargetPattern = SyntaxPattern(
            name: .tapTargetTooSmall,
            visitor: TapTargetTooSmallVisitor.self,
            severity: .warning,
            category: .accessibility,
            messageTemplate: "Interactive element below 44pt minimum tap target",
            suggestion: "Increase frame to at least 44\u{00D7}44pt or add padding",
            description: "Detects interactive elements with frame dimensions "
                + "below the 44pt minimum tap target size."
        )
        registry.register(patterns: [tapTargetPattern])

        let dynamicTypePattern = SyntaxPattern(
            name: .missingDynamicTypeSupport,
            visitor: MissingDynamicTypeSupportVisitor.self,
            severity: .info,
            category: .accessibility,
            messageTemplate: ".lineLimit(1) on dynamic text may truncate "
                + "at larger Dynamic Type sizes",
            suggestion: "Allow multiple lines, add .minimumScaleFactor(), "
                + "or provide full text via .accessibilityLabel().",
            description: "Detects .lineLimit(1) on dynamic text content "
                + "that may truncate at larger text sizes. Disabled by default."
        )
        registry.register(patterns: [dynamicTypePattern])

        let decorativeImagePattern = SyntaxPattern(
            name: .decorativeImageMissingTrait,
            visitor: DecorativeImageMissingTraitVisitor.self,
            severity: .info,
            category: .accessibility,
            messageTemplate: "Decorative image may need "
                + ".accessibilityHidden(true)",
            suggestion: "Add .accessibilityHidden(true) if decorative, "
                + "or .accessibilityLabel() if meaningful.",
            description: "Detects likely decorative images without "
                + "accessibility handling. Disabled by default."
        )
        registry.register(patterns: [decorativeImagePattern])

        registry.register(registrars: [HardcodedFontSize()])
    }
} 
