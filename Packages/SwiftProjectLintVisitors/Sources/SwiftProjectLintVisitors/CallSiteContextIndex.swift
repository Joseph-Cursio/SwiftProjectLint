import SwiftSyntax

/// `ContextAnnotationParser.parseContextAtCallSite(of:)`, answered for every call in one file at once.
///
/// The per-call lookup walks up from the call to the code-block item enclosing it, then scans the
/// item's tokens as far as the call. In a member chain `x.a().a()…` every call sits a level deeper
/// in the same statement, so each lookup costs the chain's depth and a file's lookups cost its
/// square: a default-rules lint of one 2,000-link chain took most of a minute in a debug build,
/// because the idempotency visitors ask for every call they meet.
///
/// The index walks the file once, carrying the enclosing item down instead of finding it from each
/// call, and remembers the latest annotation it has passed instead of rescanning for it. A lookup
/// is then a dictionary probe.
///
/// It answers exactly what the per-call lookup answers, including on a tree that failed to parse.
/// That lookup reads the leading trivia of every token in the item from its first token through
/// the call's own first token, and keeps the last annotation found. A walk visits tokens in source
/// order and reaches a call's first token straight after the call itself, so each call is settled
/// there, once that token's trivia has been read: the latest annotation so far is the answer, if
/// the enclosing item had begun when it was written. A call with no token of its own is settled
/// when the walk leaves it; then nothing it could carry has been read. Without an enclosing item
/// only the call's own first token counts, which is the lookup's leading-trivia check.
public struct CallSiteContextIndex: Sendable {

    /// The tree the index was built from. A call from any other tree is looked up directly.
    private let tree: SourceFileSyntax?

    /// The context of every call in `tree` that has one.
    private let contexts: [SyntaxIdentifier: ContextEffect]

    /// An index of no file: every call is looked up directly, at the per-call cost.
    public init() {
        tree = nil
        contexts = [:]
    }

    public init(_ tree: SourceFileSyntax) {
        let resolver = Resolver()
        resolver.walk(tree)
        self.tree = tree
        contexts = resolver.contexts
    }

    /// The `@lint.context` that applies at `call`: what `parseContextAtCallSite(of:)` returns.
    public func context(of call: FunctionCallExprSyntax) -> ContextEffect? {
        guard let tree, SyntaxIdentifier.fromIndexInTree(call.id.indexInTree, relativeToRoot: tree) == call.id else {
            return ContextAnnotationParser.parseContextAtCallSite(of: call)
        }
        return contexts[call.id]
    }

    private final class Resolver: SyntaxVisitor {

        private struct Annotation {
            let position: AbsolutePosition
            let context: ContextEffect
        }

        private struct PendingCall {
            let id: SyntaxIdentifier
            /// Where the scan for this call begins: its enclosing item, else the call itself.
            let scanStart: AbsolutePosition
        }

        private(set) var contexts: [SyntaxIdentifier: ContextEffect] = [:]

        /// Where each code-block item the walk is inside begins, innermost last.
        private var itemStarts: [AbsolutePosition] = []

        /// The last annotation read, in source order.
        private var latest: Annotation?

        /// Calls entered since the last token: all of them begin at the next one.
        private var pending: [PendingCall] = []

        init() {
            super.init(viewMode: .sourceAccurate)
        }

        override func visit(_ node: CodeBlockItemSyntax) -> SyntaxVisitorContinueKind {
            itemStarts.append(node.position)
            return .visitChildren
        }

        override func visitPost(_: CodeBlockItemSyntax) {
            itemStarts.removeLast()
        }

        override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
            pending.append(PendingCall(id: node.id, scanStart: itemStarts.last ?? node.position))
            return .visitChildren
        }

        override func visitPost(_ node: FunctionCallExprSyntax) {
            // Still pending on the way out: the call has no token, so no trivia of its own.
            if pending.last?.id == node.id {
                settle(pending.removeLast())
            }
        }

        override func visit(_ token: TokenSyntax) -> SyntaxVisitorContinueKind {
            if let context = ContextAnnotationParser.parseContext(leadingTrivia: token.leadingTrivia) {
                latest = Annotation(position: token.position, context: context)
            }
            for call in pending {
                settle(call)
            }
            pending.removeAll(keepingCapacity: true)
            return .visitChildren
        }

        private func settle(_ call: PendingCall) {
            if let latest, latest.position >= call.scanStart {
                contexts[call.id] = latest.context
            }
        }
    }
}
