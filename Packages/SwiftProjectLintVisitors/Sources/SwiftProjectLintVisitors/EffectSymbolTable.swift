import SwiftSyntax

/// A map from function signature (name + argument labels) to its declared
/// idempotency effect and/or execution context, built per-file or across the
/// whole project.
///
/// ## Keying
/// Entries are keyed on `FunctionSignature` — the canonical bare-receiver form
/// `name(label1:label2:…)` — rather than bare names. Two declarations collide
/// only if they would be indistinguishable at a call site without type info.
/// This is the OI-4 Phase-1.1 refinement: the bare-name policy (every repeat
/// of a name withdraws the entry) over-suppressed on protocol-oriented APIs,
/// where a single function has three or more declarations sharing a name
/// (protocol requirement + extension defaults + concrete conformance) but
/// differing signatures.
///
/// ## Collision policy
/// Unannotated declarations do **not** participate in collision detection.
/// The user's annotation expresses intent; an unannotated sibling is noise, not
/// ambiguity. Semantics:
///
/// - Zero annotated declarations for a signature → no entry.
/// - Exactly one annotated declaration → entry stored.
/// - Multiple annotated declarations with matching `(effect, context)` →
///   entry stored (counts as one logical declaration).
/// - Multiple annotated declarations with conflicting `(effect, context)` →
///   entry withdrawn (`nil` lookup).
///
/// This policy is strictly more permissive than the bare-name version and
/// fixes the round-2 trial's `MemoryPersistDriver.create` case, where the
/// concrete implementation's annotation was being withdrawn by collision
/// with the unannotated protocol requirement and extension default.
public struct EffectSymbolTable: Sendable {

    public struct Entry: Sendable, Equatable {
        public let effect: DeclaredEffect?
        public let context: ContextEffect?
    }

    public private(set) var entriesBySignature: [FunctionSignature: Entry] = [:]

    /// Count of **annotated** definitions seen per signature. Unannotated
    /// declarations are not recorded here — only annotated ones participate in
    /// collision detection.
    private var annotatedCounts: [FunctionSignature: Int] = [:]

    public init() {}

    /// Builds a symbol table by walking every top-level and nested
    /// `FunctionDeclSyntax` in the source file.
    public static func build(from source: SourceFileSyntax) -> EffectSymbolTable {
        var table = EffectSymbolTable()
        table.merge(source: source)
        return table
    }

    /// Adds every annotated `FunctionDeclSyntax` in `source` to this table,
    /// applying the collision policy on duplicate signatures. Call repeatedly
    /// to accumulate entries across files; the collision semantics apply
    /// uniformly within and across file boundaries.
    public mutating func merge(source: SourceFileSyntax) {
        let collector = FunctionDeclCollector()
        collector.walk(source)
        for funcDecl in collector.functions {
            let effect = EffectAnnotationParser.parseEffect(leadingTrivia: funcDecl.leadingTrivia)
            let context = EffectAnnotationParser.parseContext(leadingTrivia: funcDecl.leadingTrivia)
            let signature = FunctionSignature.from(declaration: funcDecl)
            record(signature: signature, effect: effect, context: context)
        }
    }

    /// Records one annotated occurrence of a function signature. Unannotated
    /// declarations (both `effect` and `context` nil) are ignored entirely —
    /// they neither add entries nor count toward collision.
    public mutating func record(
        signature: FunctionSignature,
        effect: DeclaredEffect?,
        context: ContextEffect?
    ) {
        guard effect != nil || context != nil else { return }

        annotatedCounts[signature, default: 0] += 1
        let count = annotatedCounts[signature] ?? 0

        if count == 1 {
            entriesBySignature[signature] = Entry(effect: effect, context: context)
            return
        }

        // Two-or-more annotated declarations of the same signature: keep only
        // when semantically identical, otherwise withdraw the entry.
        if let existing = entriesBySignature[signature],
           existing.effect == effect,
           existing.context == context {
            return
        }
        entriesBySignature.removeValue(forKey: signature)
    }

    /// Returns the declared effect for `signature`, or `nil` if the signature
    /// has no annotated entry (zero declarations, or withdrawn by collision).
    public func effect(for signature: FunctionSignature) -> DeclaredEffect? {
        entriesBySignature[signature]?.effect
    }

    /// Returns the declared context for `signature`, or `nil`.
    public func context(for signature: FunctionSignature) -> ContextEffect? {
        entriesBySignature[signature]?.context
    }

    /// `true` if two or more annotated declarations of `signature` were
    /// encountered. Useful for diagnostics and targeted tests.
    public func isCollision(signature: FunctionSignature) -> Bool {
        (annotatedCounts[signature] ?? 0) > 1
    }
}

/// Walks a source file and collects every `FunctionDeclSyntax`, including
/// nested methods, without descending into closures (closures can't declare
/// named functions that become call targets by simple name).
final class FunctionDeclCollector: SyntaxVisitor {
    var functions: [FunctionDeclSyntax] = []

    init() {
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        functions.append(node)
        return .visitChildren
    }

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        .skipChildren
    }
}
