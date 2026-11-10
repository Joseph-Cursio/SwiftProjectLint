import Foundation
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// Walks a function body gathering the four signals, and **stops at a closure**: a kernel that lives
/// wholly inside one is `pureClosureCandidate`'s finding, and reporting it twice would teach the
/// reader that the two rules disagree when they do not.
struct Collector {

    private(set) var derivedBindings: [String] = []
    private(set) var hasFraction = false
    private(set) var fractionIsNamed = false
    private(set) var hasSlicingArithmetic = false
    private(set) var firstArithmeticSite: Syntax?
    private var comparisons: [ExprSyntax] = []

    /// A `var` whose initialiser is not an integer literal — a mutable value seeded from *outside*
    /// the kernel, e.g. `var index = current.queuedChunks`. A `var i = 0` is excluded: a literal
    /// seed has no resume concept and no clamp to owe.
    private var externallySeededVars: Set<String> = []

    /// Identifiers that appear inside slicing arithmetic — `index` and `chunkSize` in
    /// `dropFirst(index * chunkSize)`. The intersection with `externallySeededVars` is the resume
    /// index: a value sourced from outside that drives the slice.
    private var slicingIndexNames: Set<String> = []

    /// A resumable index is present when an externally-seeded `var` is the thing driving the slice.
    /// (B18.) This implies `hasSlicingArithmetic`, since `slicingIndexNames` is only ever populated
    /// alongside it.
    var hasResumableIndex: Bool {
        !externallySeededVars.isDisjoint(with: slicingIndexNames)
    }

    /// Calls that do not refute the kernel — a numeric conversion computes nothing you could not
    /// have written with an operator. Anything else in an initialiser means the binding is doing
    /// *work*, and work the analyser cannot see is work it must not vouch for.
    private static let pureConversions: Set<String> = [
        "Double", "Int", "Int64", "Int32", "UInt", "UInt64", "Float", "CGFloat"
    ]

    private static let slicingCalls: Set<String> = [
        "dropFirst", "dropLast", "prefix", "suffix", "removeFirst", "removeLast"
    ]

    private static let arithmeticOperators: Set<String> = ["+", "-", "*", "/", "%"]
    private static let comparisonOperators: Set<String> = ["<", ">", "<=", ">=", "==", "!="]

    // MARK: - The path/string shape

    private(set) var derivedPathBindings: [String] = []

    /// The subset of `derivedPathBindings` whose derivation used an operation that
    /// identifies a **path** rather than any string — see `pathSpecificNames`.
    private(set) var pathSpecificBindings: [String] = []
    private(set) var hasCountDrivenSlice = false

    /// Identifiers passed to a membership test — `dirName` in `skipped.contains(dirName)`.
    private var membershipArguments: Set<String> = []

    /// Calls that derive one string from another and nothing else. Every entry is total and
    /// allocation-only: none of them reads the disk, the clock or global state, so a binding built
    /// from them is a value the reader could have written by hand.
    ///
    /// `contains` is absent on purpose. It is the membership *test*, tracked separately as a
    /// governing use — counting it as a derivation too would let one expression satisfy both
    /// halves of the conjunction and collapse the gate.
    private static let pathCalls: Set<String> = [
        "hasPrefix", "hasSuffix", "starts", "dropFirst", "dropLast", "prefix", "suffix",
        "lowercased", "uppercased", "capitalized", "trimmingCharacters", "replacingOccurrences",
        "components", "split", "joined", "appendingPathComponent", "appendingPathExtension",
        "deletingLastPathComponent", "deletingPathExtension", "standardizingPath",
    ]

    /// Property reads that are part of a derivation rather than a call — `path.lastPathComponent`.
    private static let pathMembers: Set<String> = [
        "lastPathComponent", "pathExtension", "deletingLastPathComponent", "deletingPathExtension",
        "standardizedFileURL", "absoluteString", "count", "isEmpty",
    ]

    /// Wrappers that change a string's static type without computing anything.
    private static let pathConversions: Set<String> = [
        "String", "Substring", "NSString", "URL", "Character"
    ]

    mutating func walk(_ node: some SyntaxProtocol) {
        for child in node.children(viewMode: .sourceAccurate) {
            // A closure body belongs to `pureClosureCandidate`. Do not descend.
            if child.is(ClosureExprSyntax.self) { continue }

            if let binding = child.as(VariableDeclSyntax.self) {
                record(binding)
            }
            if let call = child.as(FunctionCallExprSyntax.self) {
                record(call)
            }
            if let sequence = child.as(SequenceExprSyntax.self) {
                record(sequence)
            }
            if let subscriptCall = child.as(SubscriptCallExprSyntax.self) {
                if containsArithmetic(Syntax(subscriptCall.arguments)) {
                    hasSlicingArithmetic = true
                    slicingIndexNames.formUnion(identifiers(in: Syntax(subscriptCall.arguments)))
                }
            }
            walk(child)
        }
    }

    /// `let totalChunks = (data.count + chunkSize - 1) / chunkSize` — arithmetic, no opaque calls.
    ///
    /// Also notes a **`var` seeded from a non-literal** — `var index = current.queuedChunks` — as an
    /// externally-sourced mutable index (B18), independent of whether its initialiser does
    /// arithmetic; the resume seed usually does none.
    private mutating func record(_ declaration: VariableDeclSyntax) {
        let isVar = declaration.bindingSpecifier.tokenKind == .keyword(.var)
        for binding in declaration.bindings {
            guard let value = binding.initializer?.value,
                  let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.text else {
                continue
            }
            // A binding that reads ambient state is not a kernel, whichever shape it has below:
            // this rule's own message claims the bindings "depend only on its parameters and
            // locals", and a clock read makes that claim false.
            //
            // `onlyPureCalls` cannot catch it. That walk visits `FunctionCallExprSyntax`, and
            // `ContinuousClock.now` is a member access with no call in it. `Date()` was already
            // refused because it *is* a call whose callee is not a pure conversion — which is why
            // only the clock-property spelling ever got through, and why the gap went unnoticed.
            guard !AmbientStateReads.occur(in: value) else { continue }

            if isVar, !value.is(IntegerLiteralExprSyntax.self) {
                externallySeededVars.insert(name)
            }
            guard containsArithmetic(Syntax(value)), onlyPureCalls(Syntax(value)) else {
                recordPathDerivation(name, value: value, at: declaration)
                continue
            }
            derivedBindings.append(name)
            if firstArithmeticSite == nil { firstArithmeticSite = Syntax(declaration) }
            if isFraction(Syntax(value)) {
                hasFraction = true
                fractionIsNamed = true
            }
        }
    }

    /// A binding that derives a string from other strings — reached only when the arithmetic test
    /// has already declined, so the two shapes never both claim one binding.
    ///
    /// Note this catches `let prefix = root.hasSuffix("/") ? root : root + "/"`, which the
    /// arithmetic path sees and rejects: `+` reads as an arithmetic operator, then `onlyPureCalls`
    /// refuses `hasSuffix`. Falling through to here is what turns that rejection into a finding
    /// instead of a silence.
    private mutating func recordPathDerivation(
        _ name: String, value: ExprSyntax, at declaration: VariableDeclSyntax
    ) {
        guard containsPathOperation(Syntax(value)), onlyPathSafeCalls(Syntax(value)) else { return }
        if PathEvidence.occurs(in: Syntax(value)) { pathSpecificBindings.append(name) }
        derivedPathBindings.append(name)
        if firstArithmeticSite == nil { firstArithmeticSite = Syntax(declaration) }
    }

    private mutating func record(_ call: FunctionCallExprSyntax) {
        guard let callee = call.calledExpression.as(MemberAccessExprSyntax.self) else { return }
        let name = callee.declName.baseName.text
        let arguments = Syntax(call.arguments)
        if Self.slicingCalls.contains(name), containsArithmetic(arguments) {
            hasSlicingArithmetic = true
            slicingIndexNames.formUnion(identifiers(in: arguments))
            if firstArithmeticSite == nil { firstArithmeticSite = Syntax(call) }
            return
        }
        // `dropFirst(prefix.count)` — a slice with no operator in it, and the exact expression the
        // arithmetic gate above walks past.
        if Self.slicingCalls.contains(name), referencesCount(arguments) {
            hasCountDrivenSlice = true
            if firstArithmeticSite == nil { firstArithmeticSite = Syntax(call) }
            return
        }
        // `skippedDirectories.contains(dirName)` — the governing use a classification kernel has.
        // A trailing-closure form (`contains(where:)`) is `pureClosureCandidate`'s finding, so only
        // the value form counts here.
        if name == "contains", call.trailingClosure == nil {
            membershipArguments.formUnion(identifiers(in: arguments))
        }
    }

    /// Whether the expression reads a `.count` — what makes `dropFirst(prefix.count)` a derived
    /// slice rather than a constant one. `dropFirst(1)` is not a kernel.
    func referencesCount(_ node: Syntax) -> Bool {
        node.children(viewMode: .sourceAccurate).contains { child in
            if let member = child.as(MemberAccessExprSyntax.self),
               member.declName.baseName.text == "count" {
                return true
            }
            return referencesCount(child)
        }
    }

    /// Whether any of these derived names is the subject of a membership test.
    func membershipTestReferences(_ names: [String]) -> Bool {
        !membershipArguments.isDisjoint(with: Set(names))
    }

    /// A comparison that names one of these bindings — `parent == current`.
    ///
    /// Strictly `references`, with no `containsArithmetic` shortcut. That shortcut is right for the
    /// arithmetic shape, where any computed comparison is evidence, and wrong here: `+` on strings
    /// is concatenation, so a single `message + suffix` anywhere in the body would vouch for a
    /// derivation it has nothing to do with. Writing the loose version first and then finding it
    /// fired on unrelated bindings is what produced this method.
    func comparisonReferences(_ names: [String]) -> Bool {
        let derived = Set(names)
        return comparisons.contains { references(Syntax($0), anyOf: derived) }
    }

    func containsPathOperation(_ node: Syntax) -> Bool {
        for child in node.children(viewMode: .sourceAccurate) {
            if let member = child.as(MemberAccessExprSyntax.self) {
                let name = member.declName.baseName.text
                if Self.pathCalls.contains(name) || Self.pathMembers.contains(name) { return true }
            }
            if containsPathOperation(child) { return true }
        }
        return false
    }

    /// Every call in the subtree must be a known string derivation or a type conversion. Same
    /// posture as `onlyPureCalls`: the rule will not vouch for work it cannot see, so one unknown
    /// helper call disqualifies the binding.
    func onlyPathSafeCalls(_ node: Syntax) -> Bool {
        for child in node.children(viewMode: .sourceAccurate) {
            if let call = child.as(FunctionCallExprSyntax.self) {
                if let member = call.calledExpression.as(MemberAccessExprSyntax.self) {
                    guard Self.pathCalls.contains(member.declName.baseName.text) else { return false }
                } else if let reference = call.calledExpression.as(DeclReferenceExprSyntax.self) {
                    let name = reference.baseName.text
                    guard Self.pathConversions.contains(name) || Self.pureConversions.contains(name)
                    else { return false }
                } else {
                    return false
                }
            }
            guard onlyPathSafeCalls(child) else { return false }
        }
        return true
    }

    private mutating func record(_ sequence: SequenceExprSyntax) {
        let symbols = operators(in: Syntax(sequence))
        if !symbols.isDisjoint(with: Self.comparisonOperators) {
            comparisons.append(ExprSyntax(sequence))
        }
        if isFraction(Syntax(sequence)) {
            hasFraction = true
            if firstArithmeticSite == nil { firstArithmeticSite = Syntax(sequence) }
        }
    }

    /// A comparison counts only when it is *deciding something computed* — either a side does
    /// arithmetic (`progress - lastReported >= 0.01`) or a side is a value the kernel derived
    /// (`index < totalChunks`). A bare `status == .ok` decides nothing a generator could break.
    func governingComparisonReferencing(_ bindings: [String]) -> Bool {
        let derived = Set(bindings)
        return comparisons.contains { comparison in
            let node = Syntax(comparison)
            if containsArithmetic(node) { return true }
            return references(node, anyOf: derived)
        }
    }

    // MARK: - Syntactic predicates

    private func operators(in node: Syntax) -> Set<String> {
        var found: Set<String> = []
        for token in node.tokens(viewMode: .sourceAccurate) {
            guard case .binaryOperator = token.tokenKind else { continue }
            found.insert(token.text)
        }
        return found
    }

    func containsArithmetic(_ node: Syntax) -> Bool {
        !operators(in: node).isDisjoint(with: Self.arithmeticOperators)
    }

    /// The bare identifiers appearing in a slice expression — `index`, `chunkSize` in
    /// `dropFirst(index * chunkSize)`. Used to find which names actually drive a slice. (B18.)
    private func identifiers(in node: Syntax) -> Set<String> {
        var found: Set<String> = []
        for token in node.tokens(viewMode: .sourceAccurate) {
            if case .identifier = token.tokenKind { found.insert(token.text) }
        }
        return found
    }

    /// `a / Double(b)` — a division whose **divisor** carries a numeric conversion. This is the
    /// progress shape, and every progress bug in this codebase is a case of it not reaching 1.0.
    ///
    /// **The divisor, because that is where a fraction differs from a rate.** The first version
    /// asked only whether a conversion appeared anywhere in the expression, and that is true of
    /// `Double(totalTokens) / totalSeconds` — tokens per second, which is unbounded. Three of the
    /// corpus's seven "progress" findings were rates and layout coordinates being told that
    /// *"progress should be monotonic, stay within 0...1, and terminate at 1.0"*, which sends a
    /// reader to clamp a number that must not be clamped.
    ///
    /// A fraction's denominator is **the whole**: a count, so it had to be converted. A rate's
    /// denominator is a duration, which is already floating-point and needs no conversion:
    ///
    /// | expression | divisor converted | what it is |
    /// | --- | --- | --- |
    /// | `Double(data.count) / Double(expectedBytes)` | yes | download progress |
    /// | `CGFloat(iteration) / CGFloat(max(iterations - 1, 1))` | yes | layout-pass progress |
    /// | `acceptedAll / Double(totalAll)` | yes | an acceptance rate in `0...1` |
    /// | `Double(totalTokens) / totalSeconds` | **no** | tokens per second |
    /// | `Double(chunks) / genTime` | **no** | chunks per second |
    ///
    /// **A first attempt required a conversion on *both* sides and was measured to be worse.** It
    /// rejected the two rates correctly and also dropped `acceptedAll / Double(totalAll)`, a genuine
    /// bounded fraction whose numerator is already a `Double` — and dropping it cost the whole
    /// finding rather than just the label, because a kernel has to govern something and the fraction
    /// was what it governed. Reading only the divisor keeps all three fractions and rejects both
    /// rates.
    func isFraction(_ node: Syntax) -> Bool {
        guard let division = divisionOperands(in: node) else { return false }
        return containsConversion(division.divisor)
    }

    /// The two sides of the first `/` in `node`, or `nil` when there is no division.
    ///
    /// Handles both spellings: `SwiftParser` leaves `a / b` unfolded as a `SequenceExprSyntax` of
    /// three elements, and a caller that has folded operators hands over an
    /// `InfixOperatorExprSyntax`.
    private func divisionOperands(in node: Syntax) -> (dividend: Syntax, divisor: Syntax)? {
        if let infix = node.as(InfixOperatorExprSyntax.self),
           infix.operator.as(BinaryOperatorExprSyntax.self)?.operator.text == "/" {
            return (Syntax(infix.leftOperand), Syntax(infix.rightOperand))
        }
        if let sequence = node.as(SequenceExprSyntax.self) {
            let elements = Array(sequence.elements)
            for index in elements.indices.dropFirst().dropLast()
            where elements[index].as(BinaryOperatorExprSyntax.self)?.operator.text == "/" {
                return (Syntax(elements[index - 1]), Syntax(elements[index + 1]))
            }
        }
        for child in node.children(viewMode: .sourceAccurate) {
            if let found = divisionOperands(in: child) { return found }
        }
        return nil
    }

    func containsConversion(_ node: Syntax) -> Bool {
        node.tokens(viewMode: .sourceAccurate).contains { Self.pureConversions.contains($0.text) }
    }

    /// Any call that is not a numeric conversion refutes the binding. Conservative on purpose: the
    /// kernel must be arithmetic the rule can *see*, not a call it would have to trust.
    func onlyPureCalls(_ node: Syntax) -> Bool {
        for call in node.children(viewMode: .sourceAccurate).compactMap({
            $0.as(FunctionCallExprSyntax.self)
        }) {
            let name = call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text
            guard let name, Self.pureConversions.contains(name) else { return false }
        }
        return node.children(viewMode: .sourceAccurate).allSatisfy { onlyPureCalls($0) }
    }

    func references(_ node: Syntax, anyOf names: Set<String>) -> Bool {
        guard !names.isEmpty else { return false }
        return node.tokens(viewMode: .sourceAccurate).contains { names.contains($0.text) }
    }
}
