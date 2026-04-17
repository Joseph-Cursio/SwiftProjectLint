import SwiftSyntax

/// A per-file map from function name to its declared idempotency effect and/or
/// execution context.
///
/// Phase 1 of the idempotency trial is **deliberately per-file**. Cross-file
/// propagation is the proposal's Phase 3 and is explicitly out of scope —
/// see `docs/phase1/trial-scope.md` in the swiftIdempotency repo. A callee defined in
/// a sibling file will not resolve, which is working as specified for Phase 1.
public struct EffectSymbolTable: Sendable {

    public struct Entry: Sendable, Equatable {
        public let effect: DeclaredEffect?
        public let context: ContextEffect?
    }

    public private(set) var entriesByName: [String: Entry] = [:]

    public init() {}

    /// Builds a symbol table by walking every top-level and nested `FunctionDeclSyntax`
    /// in the source file. Method names inside types are recorded without the type
    /// qualifier, mirroring how `FunctionCallExprSyntax` callees appear when resolved
    /// against a per-file table.
    public static func build(from source: SourceFileSyntax) -> EffectSymbolTable {
        var table = EffectSymbolTable()
        let collector = FunctionDeclCollector()
        collector.walk(source)
        for funcDecl in collector.functions {
            let entry = Entry(
                effect: EffectAnnotationParser.parseEffect(leadingTrivia: funcDecl.leadingTrivia),
                context: EffectAnnotationParser.parseContext(leadingTrivia: funcDecl.leadingTrivia)
            )
            guard entry.effect != nil || entry.context != nil else { continue }
            table.entriesByName[funcDecl.name.text] = entry
        }
        return table
    }

    public func effect(for name: String) -> DeclaredEffect? {
        entriesByName[name]?.effect
    }

    public func context(for name: String) -> ContextEffect? {
        entriesByName[name]?.context
    }
}

/// Walks a source file and collects every `FunctionDeclSyntax`, including nested methods,
/// without descending into closures (closures can't declare named functions that become
/// call targets by simple name).
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
