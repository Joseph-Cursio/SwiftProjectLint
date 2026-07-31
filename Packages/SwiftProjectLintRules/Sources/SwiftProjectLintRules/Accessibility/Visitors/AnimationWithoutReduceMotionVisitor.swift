import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects a SwiftUI view that animates without ever consulting the user's
/// Reduce Motion preference.
///
/// Reduce Motion is not a cosmetic setting. People with vestibular disorders
/// enable it because motion on screen causes nausea and dizziness, so a view
/// that scales, slides, or springs regardless of the setting can make an app
/// physically unpleasant to use.
///
/// This is a **struct-level** check, deliberately: asking "does this view ever
/// consider Reduce Motion?" once is far quieter than asking it of every
/// individual `.animation` call, and a single `reduceMotion` check usually
/// governs a whole view.
///
/// Flagged:
/// ```swift
/// struct MyView: View {
///     @State private var isLoading = false
///     var body: some View {
///         Text("Loading")
///             .transition(.scale)
///             .animation(.easeInOut, value: isLoading)
///     }
/// }
/// ```
///
/// Not flagged: any view mentioning `accessibilityReduceMotion` (however it uses
/// it) or UIKit's `UIAccessibility.isReduceMotionEnabled`; `.animation(nil, …)`,
/// which disables animation rather than adding it; and transitions that carry no
/// motion, `.opacity` and `.identity`.
final class AnimationWithoutReduceMotionVisitor: BasePatternVisitor {

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        if isTestOrFixtureFile() { return .visitChildren }
        guard isSwiftUIView(node) else { return .visitChildren }

        // Scan the member block rather than the struct, so a nested type's
        // animations are not attributed to its enclosing view — and a nested
        // type's Reduce Motion check does not excuse the outer one.
        let scanner = MotionScanner(viewMode: .sourceAccurate)
        scanner.walk(node.memberBlock)

        guard let trigger = scanner.firstTrigger, scanner.checksReduceMotion == false else {
            return .visitChildren
        }

        addIssue(
            severity: .info,
            message: "\(node.name.text) animates (\(trigger.description)) but never checks "
                + "accessibilityReduceMotion — motion plays regardless of the user's preference",
            filePath: getFilePath(for: Syntax(trigger.node)),
            lineNumber: getLineNumber(for: Syntax(trigger.node)),
            suggestion: "Read @Environment(\\.accessibilityReduceMotion) and use it to soften the "
                + "motion, e.g. .animation(reduceMotion ? nil : .easeInOut, value: isLoading) "
                + "or .transition(reduceMotion ? .identity : .scale).",
            ruleName: .animationWithoutReduceMotion
        )
        return .visitChildren
    }
}

/// Collects, from one view's members, whether it animates and whether it ever
/// consults Reduce Motion. Nested type declarations are skipped so each view is
/// judged on its own body.
private final class MotionScanner: SyntaxVisitor {

    struct Trigger {
        let description: String
        let node: FunctionCallExprSyntax
    }

    /// Identifiers that mean the view has consulted the preference. Any mention
    /// counts — reading it at all implies the author considered motion.
    private static let reduceMotionNames: Set<String> = [
        "accessibilityReduceMotion",
        "isReduceMotionEnabled"
    ]

    /// Transitions that move nothing, so they need no Reduce Motion handling.
    private static let motionlessTransitions: Set<String> = ["opacity", "identity"]

    private(set) var firstTrigger: Trigger?
    private(set) var checksReduceMotion = false

    override func visit(_ _: StructDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_ _: ClassDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_ _: EnumDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }
    override func visit(_ _: ActorDeclSyntax) -> SyntaxVisitorContinueKind { .skipChildren }

    override func visit(_ node: TokenSyntax) -> SyntaxVisitorContinueKind {
        if Self.reduceMotionNames.contains(node.text) {
            checksReduceMotion = true
        }
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if firstTrigger == nil, let description = triggerDescription(node) {
            firstTrigger = Trigger(description: description, node: node)
        }
        return .visitChildren
    }

    /// Names the animation this call introduces, or nil when it introduces none.
    private func triggerDescription(_ node: FunctionCallExprSyntax) -> String? {
        if node.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "withAnimation" {
            return "withAnimation"
        }

        guard let member = node.calledExpression.as(MemberAccessExprSyntax.self) else { return nil }

        switch member.declName.baseName.text {
        case "animation":
            // `.animation(nil, value:)` switches animation off — the opposite of the problem.
            guard let first = node.arguments.first,
                  first.expression.is(NilLiteralExprSyntax.self) == false else { return nil }
            return ".animation"

        case "transition":
            guard let first = node.arguments.first, carriesMotion(first.expression) else { return nil }
            return ".transition"

        default:
            return nil
        }
    }

    /// False for `.opacity` and `.identity`, which change no position or size.
    private func carriesMotion(_ expression: ExprSyntax) -> Bool {
        guard let member = expression.as(MemberAccessExprSyntax.self),
              member.base == nil else { return true }
        return Self.motionlessTransitions.contains(member.declName.baseName.text) == false
    }
}
