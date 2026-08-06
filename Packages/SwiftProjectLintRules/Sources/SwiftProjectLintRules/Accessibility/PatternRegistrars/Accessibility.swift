import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// Registers patterns related to accessibility best practices in SwiftUI.
/// This registrar handles patterns for accessibility labels, hints, and color usage.

class Accessibility: BasePatternRegistrar {
    override func registerPatterns() {
        registerCorePatterns()
        registerInteractionPatterns()
        registerStateAndGroupingPatterns()
        registerConflictPatterns()
        registry.register(registrars: [
            HardcodedFontSize(),
            ControlMissingAccessibilityLabel(),
            IsButtonTraitWithoutAction(),
            AnimationWithoutReduceMotion(),
            UnlabeledControl()
        ])
    }

    private func registerCorePatterns() {
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
    }

    private func registerInteractionPatterns() {
        registry.register(patterns: [
            SyntaxPattern(
                name: .onTapGestureInsteadOfButton,
                visitor: OnTapGestureInsteadOfButtonVisitor.self,
                severity: .warning,
                category: .accessibility,
                messageTemplate: "Prefer Button over .onTapGesture for accessibility",
                suggestion: "Replace .onTapGesture { ... } with a Button",
                description: "Detects .onTapGesture calls that bypass button "
                    + "accessibility traits, keyboard focus, and haptic feedback"
            ),
            // The same visitor's second finding, registered so the rule can be selected.
            //
            // `OnTapGestureInsteadOfButtonVisitor` raises two findings from one walk: a tap gesture
            // that should be a Button, and an *allowed* multi-tap gesture that VoiceOver cannot
            // discover. Only the first had a pattern, and `SourcePatternDetector.runVisitors`
            // filters a visitor's output to the requested rule names — so the second was produced
            // and then dropped on every default run. The rule fired only for a user who named it
            // in `enabled_only` alongside this one, which required already knowing both that it
            // existed and that it was coupled.
            //
            // Costs no extra work: `runVisitors` groups patterns by visitor type and walks once,
            // so this entry adds a name to the requested set and nothing else. The visitor passes
            // an explicit severity for each finding and never reads `pattern.severity`, so which
            // of the two patterns happens to initialise it does not matter.
            SyntaxPattern(
                name: .onTapGestureMissingAccessibility,
                visitor: OnTapGestureInsteadOfButtonVisitor.self,
                severity: .info,
                category: .accessibility,
                messageTemplate: "Multi-tap or location-aware onTapGesture is invisible to VoiceOver",
                suggestion: "Add .accessibilityAddTraits(.isButton) and "
                    + ".accessibilityLabel(\"description\")",
                description: "Detects allowed multi-tap and location-aware .onTapGesture calls "
                    + "that VoiceOver users cannot discover"
            ),
            SyntaxPattern(
                name: .tapTargetTooSmall,
                visitor: TapTargetTooSmallVisitor.self,
                severity: .warning,
                category: .accessibility,
                messageTemplate: "Interactive element below 44pt minimum tap target",
                suggestion: "Increase frame to at least 44\u{00D7}44pt or add padding",
                description: "Detects interactive elements with frame dimensions "
                    + "below the 44pt minimum tap target size."
            ),
            SyntaxPattern(
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
            ),
            SyntaxPattern(
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
        ])
    }

    private func registerStateAndGroupingPatterns() {
        registry.register(patterns: [
            SyntaxPattern(
                name: .toggleButtonMissingSelectedTrait,
                visitor: ToggleButtonMissingSelectedTraitVisitor.self,
                severity: .warning,
                category: .accessibility,
                messageTemplate: "Button with conditional appearance may need "
                    + ".accessibilityAddTraits to communicate selected state",
                suggestion: "Add .accessibilityAddTraits(isSelected ? .isSelected : []) "
                    + "so VoiceOver announces the selection state.",
                description: "Detects buttons with ternary-driven visuals "
                    + "that lack .accessibilityAddTraits for selected state."
            ),
            SyntaxPattern(
                name: .buttonTogglingBool,
                visitor: ButtonTogglingBoolVisitor.self,
                severity: .info,
                category: .accessibility,
                messageTemplate: "Button that toggles a Bool could be a Toggle "
                    + "with a custom ToggleStyle",
                suggestion: "Use Toggle with a custom ToggleStyle to get "
                    + "semantic accessibility traits automatically.",
                description: "Detects buttons whose action calls .toggle() "
                    + "on a Bool, suggesting a Toggle would be more accessible."
            ),
            SyntaxPattern(
                name: .stackMissingAccessibilityGrouping,
                visitor: StackAccessibilityGroupingVisitor.self,
                severity: .info,
                category: .accessibility,
                messageTemplate: "Stack with label\u{2013}value Text pair may need "
                    + ".accessibilityElement(children:) for VoiceOver grouping",
                suggestion: "Add .accessibilityElement(children: .combine) so "
                    + "VoiceOver reads the label and value together.",
                description: "Detects VStack/HStack with exactly two Text children "
                    + "and no interactive elements that lack accessibility grouping."
            )
        ])
    }

    private func registerConflictPatterns() {
        registry.register(patterns: [
            SyntaxPattern(
                name: .accessibilityHiddenConflict,
                visitor: AccessibilityHiddenConflictVisitor.self,
                severity: .warning,
                category: .accessibility,
                messageTemplate: ".accessibilityHidden(true) conflicts with "
                    + "other accessibility modifiers on the same view",
                suggestion: "Remove the conflicting modifiers, or replace "
                    + ".accessibilityHidden(true) with "
                    + ".accessibilityElement(children: .ignore).",
                description: "Detects views with .accessibilityHidden(true) "
                    + "alongside other accessibility attributes that become unreachable."
            ),
            SyntaxPattern(
                name: .sortPriorityWithoutContainer,
                visitor: SortPriorityWithoutContainerVisitor.self,
                severity: .warning,
                category: .accessibility,
                messageTemplate: ".accessibilitySortPriority() has no effect without "
                    + ".accessibilityElement(children: .contain) on the parent stack",
                suggestion: "Add .accessibilityElement(children: .contain) to the "
                    + "enclosing stack for sort priorities to take effect.",
                description: "Detects sort priority modifiers inside stacks "
                    + "that lack the required accessibility container modifier."
            )
        ])
    }
}
