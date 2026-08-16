import SwiftEffectInference

/// Thin forwarder onto the stdlib-mutation exclusion table in the shared leaf.
///
/// The table moved to `SwiftEffectInference.StdlibIdempotentMutations` with the
/// inferrer it suppresses for. Before the move the two copies differed only in
/// access modifiers.
///
/// ## What the table is for
///
/// `append` / `insert` / `remove` are correctly non-idempotent for a
/// user-defined persistent queue and **wrong** for `Array.append` or
/// `Set.insert`, so a `(typeName, methodName)` pair suppresses the bare-name
/// inference back to "no heuristic applied" rather than to a different verdict.
/// `Set.insert` is idempotent by set semantics; `Dictionary.updateValue` is
/// key-addressed and replay-safe.
///
/// Pair matches require the receiver to resolve to `.stdlibCollection(name)`.
/// A `.named` or `.unresolved` receiver is **never** excluded — the resolver
/// declines rather than guesses, and a declined resolution must not be read as
/// evidence that the receiver is not a stdlib type.
public enum StdlibExclusions {

    /// Whether `(receiver, method)` is a stdlib operation whose bare-name
    /// inference should be suppressed.
    public static func isExcluded(
        receiver: ResolvedReceiverType,
        method: String
    ) -> Bool {
        StdlibIdempotentMutations.isExcluded(
            receiver: ReceiverTypeResolver.unmap(receiver),
            method: method
        )
    }
}
