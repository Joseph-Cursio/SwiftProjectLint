import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects nondeterministic sources used inline in logic rather than injected
/// as a dependency: `Date()`, `UUID()`, `.random(in:)`, `.randomElement()`,
/// `.shuffled()`, the legacy C RNG/clock functions, and `Date.now` /
/// `Locale.current` / `TimeZone.current`.
///
/// Inline nondeterminism is the #1 blocker to property-testing pure logic: a
/// property can't pin the value or reproduce a counterexample, so the function
/// stops being a function of its inputs. A source supplied as a parameter
/// default (`init(id: UUID = UUID())`) is the injection seam, not inline use,
/// and is exempt.
final class NonInjectedNondeterminismVisitor: BasePatternVisitor {

    private var fileIsTestOrFixture = false

    private static let noArgInitTypes: Set<String> = ["Date", "UUID"]
    private static let bareFunctions: Set<String> = [
        "arc4random", "arc4random_uniform", "drand48", "CFAbsoluteTimeGetCurrent"
    ]
    private static let randomMembers: Set<String> = ["random", "randomElement", "shuffled"]

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        super.setFilePath(filePath)
        fileIsTestOrFixture = isTestOrFixtureFile()
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard !fileIsTestOrFixture, !isParameterDefaultValue(Syntax(node)) else {
            return .visitChildren
        }
        if let source = nondeterministicCallSource(node) {
            flag(source, at: Syntax(node))
        }
        return .visitChildren
    }

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        guard !fileIsTestOrFixture, !isParameterDefaultValue(Syntax(node)) else {
            return .visitChildren
        }
        guard let base = node.base?.as(DeclReferenceExprSyntax.self)?.baseName.text else {
            return .visitChildren
        }
        let name = node.declName.baseName.text
        if (base == "Date" && name == "now")
            || ((base == "Locale" || base == "TimeZone") && name == "current") {
            flag("\(base).\(name)", at: Syntax(node))
        }
        return .visitChildren
    }

    private func nondeterministicCallSource(_ node: FunctionCallExprSyntax) -> String? {
        // Bare init / function: `Date()`, `UUID()` (only the no-argument forms
        // are nondeterministic), `arc4random()`, `CFAbsoluteTimeGetCurrent()`.
        if let ref = node.calledExpression.as(DeclReferenceExprSyntax.self) {
            let name = ref.baseName.text
            if Self.noArgInitTypes.contains(name), node.arguments.isEmpty {
                return "\(name)()"
            }
            if Self.bareFunctions.contains(name) {
                return "\(name)()"
            }
        }
        // Member call: `Int.random(in:)`, `array.randomElement()`, `.shuffled()`.
        if let member = node.calledExpression.as(MemberAccessExprSyntax.self),
           Self.randomMembers.contains(member.declName.baseName.text) {
            // A `using:` argument injects the RNG — `Int.random(in: r, using: &rng)`
            // is reproducible from a seed, which is exactly the testable form. Only
            // the system-RNG forms (no `using:`) are non-injected nondeterminism.
            if node.arguments.contains(where: { $0.label?.text == "using" }) {
                return nil
            }
            return ".\(member.declName.baseName.text)(…)"
        }
        return nil
    }

    private func flag(_ source: String, at node: Syntax) {
        addIssue(
            severity: .warning,
            message: "Non-injected nondeterminism: `\(source)` makes this code unpredictable, so a "
                + "property-based test can't pin the value or reproduce a failure",
            filePath: getFilePath(for: node),
            lineNumber: getLineNumber(for: node),
            suggestion: "Inject the source (a clock `() -> Date`, a `RandomNumberGenerator`, a UUID "
                + "provider) so tests can control it.",
            ruleName: .nonInjectedNondeterminism
        )
    }

    /// True when `node` sits in a function/initializer parameter's default
    /// value — `init(id: UUID = UUID())` is the injection seam, not inline
    /// nondeterminism. Stops at a closure / code block so a call inside a
    /// default closure body is still flagged.
    private func isParameterDefaultValue(_ node: Syntax) -> Bool {
        var current = node.parent
        while let syntax = current {
            if syntax.is(ClosureExprSyntax.self) || syntax.is(CodeBlockSyntax.self) {
                return false
            }
            if syntax.is(FunctionParameterSyntax.self) {
                return true
            }
            current = syntax.parent
        }
        return false
    }
}
