import Foundation
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// Detects a `Bool` parameter that the function body uses to choose between two
/// *substantial* code paths — Adam Tornhill's "control coupling" smell. The
/// caller is reaching in to select which behavior the callee runs, a hidden
/// design decision better expressed as a strategy (two named functions, or a
/// protocol / closure passed in) so each path is named and discoverable.
///
/// Distinct from `MagicBooleanParameterVisitor`, which flags unlabeled boolean
/// *arguments* at call sites (a caller-side readability smell). This rule is
/// callee-side: it fires only when the parameter actually drives an `if`/`else`
/// with two non-trivial arms. Swift's argument labels already make the call site
/// readable, so the value here is in the *body*, not the call.
///
/// **"Non-trivial" is the whole rule, and it used to be stated two ways.** The
/// gate read "two or more statements, *or* contains a call", which makes a
/// single call non-trivial — and a single call is a *name*, which is precisely
/// what the rule asks the code to produce. Across the 26-repository corpus that
/// disagreement was not an edge case: six of the eight findings were a branch
/// choosing a value or an already-named operation, and at four of them the
/// suggested remedy was not merely unnecessary but impossible. The rule's own
/// documentation carried the proof — its canonical violating example is
/// `if isPremium { return premiumPrice() } else { return standardPrice() }`, and
/// the fix printed underneath it is "call `premiumPrice()` / `standardPrice()`
/// directly", naming the two functions the example already has.
///
/// So `isSubstantialArm` is now one of three gates, and the other two say what
/// the branch must *not* be: `isNamedDispatch` (both arms one statement) and
/// `isDeferredValueSelection` (both arms initializing one `let`). What survives
/// all three is a branch whose arms do unnamed work of visibly different shape —
/// the `export(asPDF:)` example in the rule doc, one line against five in
/// `pbt-book`'s `tokenizeStreaming`.
final class BooleanControlCouplingVisitor: BasePatternVisitor {

    /// The set of `Bool` parameter names in scope for each enclosing function /
    /// initializer, innermost last. Empty for overrides, bodyless declarations,
    /// and functions with no boolean parameters — so an `if` in those scopes
    /// never matches.
    private var boolParamStack: [Set<String>] = []

    /// Parameter names that are established standard-library conventions for a
    /// capacity-retention flag — `Array.removeAll(keepingCapacity:)` and the
    /// many collection methods that mirror it. These flags branch two ways by
    /// design, but they deliberately echo the stdlib spelling; refactoring them
    /// to a strategy would fight the convention rather than clarify it, so they
    /// are exempt. Matched against both the argument label and the internal name.
    private static let conventionFlagNames: Set<String> = [
        "keepCapacity", "keepingCapacity"
    ]

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    // MARK: - Function / initializer context

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        boolParamStack.append(
            scopedBoolParams(node.signature.parameterClause, modifiers: node.modifiers, hasBody: node.body != nil)
        )
        return .visitChildren
    }

    override func visitPost(_: FunctionDeclSyntax) {
        boolParamStack.removeLast()
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        boolParamStack.append(
            scopedBoolParams(node.signature.parameterClause, modifiers: node.modifiers, hasBody: node.body != nil)
        )
        return .visitChildren
    }

    override func visitPost(_: InitializerDeclSyntax) {
        boolParamStack.removeLast()
    }

    // MARK: - Branch detection

    override func visit(_ node: IfExprSyntax) -> SyntaxVisitorContinueKind {
        // Require: not a test/fixture file, a boolean parameter in scope, and a
        // plain `else { … }` block (an `else if` chain is handled when its own
        // inner `if` is visited).
        guard isTestOrFixtureFile() == false,
              let params = boolParamStack.last, params.isEmpty == false,
              let elseBody = node.elseBody?.as(CodeBlockSyntax.self) else {
            return .visitChildren
        }

        // The condition must reference one of the boolean parameters directly
        // (not an `obj.flag` that merely shares the name).
        guard let paramName = referencedParameter(in: Syntax(node.conditions), names: params) else {
            return .visitChildren
        }

        // Both arms must be substantial — this is what separates "two strategies"
        // from "optional embellishment" (`if verbose { log() }`).
        guard isSubstantialArm(node.body), isSubstantialArm(elseBody) else {
            return .visitChildren
        }

        // The two paths already have names — nothing left to split.
        guard isNamedDispatch(node.body, elseBody) == false else {
            return .visitChildren
        }

        // The branch computes one value, it just needs statements to do it.
        guard isDeferredValueSelection(node, elseBody: elseBody) == false else {
            return .visitChildren
        }

        addIssue(
            severity: .warning,
            message: "Boolean parameter '\(paramName)' selects between two code paths — "
                + "this is control coupling (the caller decides which behavior runs).",
            filePath: getFilePath(for: Syntax(node)),
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: "Replace the flag with a strategy: split into two named functions, "
                + "or pass in a protocol / closure so each path is explicit and named.",
            ruleName: .booleanControlCoupling
        )
        return .visitChildren
    }

    // MARK: - Helpers

    /// Boolean parameter internal names for a function/initializer, or an empty
    /// set when the declaration can't (or shouldn't) be analyzed — no body, an
    /// `override` (the signature is inherited and can't be changed freely), or
    /// no boolean parameters.
    private func scopedBoolParams(
        _ clause: FunctionParameterClauseSyntax,
        modifiers: DeclModifierListSyntax,
        hasBody: Bool
    ) -> Set<String> {
        guard hasBody,
              modifiers.contains(where: { $0.name.tokenKind == .keyword(.override) }) == false else {
            return []
        }
        var names: Set<String> = []
        for param in clause.parameters where isBoolType(param.type) {
            // The internal (body-visible) name is the second name when present
            // (`func f(animated flag: Bool)` → `flag`), else the first.
            let externalName = param.firstName.text
            let internalName = (param.secondName ?? param.firstName).text
            if internalName == "_" {
                continue
            }
            // Exempt stdlib-convention capacity flags (matched on either name).
            if Self.conventionFlagNames.contains(internalName)
                || Self.conventionFlagNames.contains(externalName) {
                continue
            }
            names.insert(internalName)
        }
        return names
    }

    private func isBoolType(_ type: TypeSyntax) -> Bool {
        if type.as(IdentifierTypeSyntax.self)?.name.text == "Bool" {
            return true
        }
        if let optional = type.as(OptionalTypeSyntax.self),
           optional.wrappedType.as(IdentifierTypeSyntax.self)?.name.text == "Bool" {
            return true
        }
        return false
    }

    /// Returns the name of a parameter referenced as a value inside `node`,
    /// ignoring identifiers that are the member half of an `obj.member` access
    /// (so `config.flag` does not match a parameter named `flag`).
    private func referencedParameter(in node: Syntax, names: Set<String>) -> String? {
        if let ref = node.as(DeclReferenceExprSyntax.self), names.contains(ref.baseName.text) {
            let isMemberRHS = node.parent?.as(MemberAccessExprSyntax.self)?.declName == ref
            if isMemberRHS == false {
                return ref.baseName.text
            }
        }
        for child in node.children(viewMode: .sourceAccurate) {
            if let found = referencedParameter(in: child, names: names) {
                return found
            }
        }
        return nil
    }

    /// Both arms are exactly one statement, so each path is already a single
    /// named thing and the `if` is the one dispatch point that has to exist
    /// somewhere. This rule's own remedy — "split into two named functions" —
    /// has already been applied here; re-applying it is not possible.
    ///
    /// Measured across the 26-repository corpus this matched **five of the
    /// eight** findings: `config.enableRule(name)` / `disableRule(name)`,
    /// `renderStats(…)` / `render(…)`, `recordLayoutNumber(…)` /
    /// `recordMagicNumber(…)` twice, and `context.fill(path, …)` /
    /// `context.stroke(path, …)` — the last a SwiftUI `GraphicsContext` pair
    /// that cannot be restructured at all. The rule was reporting the residue
    /// of its own advice.
    ///
    /// The symmetry is what carries the argument, which is why this tests both
    /// arms rather than putting a floor under each one. A genuine two-algorithm
    /// branch is lopsided — one line against five — and a floor on both arms
    /// would silence it while leaving the dispatch pairs untouched.
    private func isNamedDispatch(_ thenBody: CodeBlockSyntax, _ elseBody: CodeBlockSyntax) -> Bool {
        thenBody.statements.count == 1 && elseBody.statements.count == 1
    }

    /// Swift's deferred-initialization idiom: a `let`/`var` declared with a type
    /// and no value immediately before the `if`, assigned as the final statement
    /// of each arm. The branch selects a **value**, not a behavior — which this
    /// rule already declines when the value fits in one `return` (`return .red`).
    /// Needing three statements to build a string does not turn a value into a
    /// strategy; Swift simply offers no other spelling for a `let` whose value
    /// takes work.
    ///
    /// Deliberately narrow. It requires the declaration to sit immediately
    /// before the `if`, to carry no initializer, and each arm to end in a plain
    /// `=` to that binding. Arms that merely happen to end by assigning the same
    /// variable — `result += 10` / `result += 20` against a `var result = 0` —
    /// are not this idiom and still fire; a compound assignment is accumulation,
    /// not initialization.
    private func isDeferredValueSelection(_ node: IfExprSyntax, elseBody: CodeBlockSyntax) -> Bool {
        guard let target = deferredBindingPrecedingStatement(node) else {
            return false
        }
        return assignsAsFinalStatement(node.body, to: target)
            && assignsAsFinalStatement(elseBody, to: target)
    }

    /// The name bound by an uninitialized, explicitly typed, single-binding
    /// `let`/`var` immediately preceding `node` in its enclosing block.
    private func deferredBindingPrecedingStatement(_ node: IfExprSyntax) -> String? {
        var current = Syntax(node)
        while let parent = current.parent, current.is(CodeBlockItemSyntax.self) == false {
            current = parent
        }
        guard let item = current.as(CodeBlockItemSyntax.self),
              let list = item.parent?.as(CodeBlockItemListSyntax.self),
              let index = list.index(of: item),
              index != list.startIndex else {
            return nil
        }
        let previous = list[list.index(before: index)]
        guard let declaration = previous.item.as(VariableDeclSyntax.self),
              declaration.bindings.count == 1,
              let binding = declaration.bindings.first,
              binding.initializer == nil,
              binding.typeAnnotation != nil,
              let pattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
            return nil
        }
        return pattern.identifier.text
    }

    /// Whether `block`'s last statement is a plain `name = …` assignment.
    ///
    /// `SwiftParser` leaves binary expressions unfolded, so `a = b` arrives as a
    /// `SequenceExprSyntax` of `[a, =, b]` rather than an `InfixOperatorExprSyntax`
    /// — folding needs an operator table this visitor does not have. The infix
    /// shape is accepted too, for a caller that hands over a folded tree.
    ///
    /// `AssignmentExprSyntax` is the `=` token itself, so `+=` — which arrives as
    /// a `BinaryOperatorExprSyntax` in the same position — does not match. That
    /// is what keeps accumulation out of the deferred-initialization gate.
    private func assignsAsFinalStatement(_ block: CodeBlockSyntax, to name: String) -> Bool {
        guard let last = block.statements.last,
              let expression = last.item.as(ExprSyntax.self) else {
            return false
        }
        if let sequence = expression.as(SequenceExprSyntax.self) {
            var elements = sequence.elements.makeIterator()
            guard let target = elements.next()?.as(DeclReferenceExprSyntax.self),
                  elements.next()?.is(AssignmentExprSyntax.self) == true else {
                return false
            }
            return target.baseName.text == name
        }
        if let infix = expression.as(InfixOperatorExprSyntax.self) {
            guard infix.operator.is(AssignmentExprSyntax.self),
                  let target = infix.leftOperand.as(DeclReferenceExprSyntax.self) else {
                return false
            }
            return target.baseName.text == name
        }
        return false
    }

    /// An arm is "substantial" — i.e. real work, not a trivial value selection —
    /// when it has two or more statements, or contains a function/method call.
    /// This deliberately treats single literal/value returns (`return .red`,
    /// `return 0`) as *not* substantial: a boolean→value map is not the
    /// control-coupling smell this rule targets.
    ///
    /// On its own this is the weakest of the three gates, because a single call
    /// clears it. `isNamedDispatch` is what stops that from being the rule's
    /// dominant behavior; the two are meant to be read together.
    private func isSubstantialArm(_ block: CodeBlockSyntax) -> Bool {
        if block.statements.count >= 2 {
            return true
        }
        return containsCall(Syntax(block.statements))
    }

    private func containsCall(_ node: Syntax) -> Bool {
        if node.is(FunctionCallExprSyntax.self) {
            return true
        }
        for child in node.children(viewMode: .sourceAccurate) where containsCall(child) {
            return true
        }
        return false
    }
}
