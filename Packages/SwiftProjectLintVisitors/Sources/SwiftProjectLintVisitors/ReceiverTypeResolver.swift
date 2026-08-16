import SwiftEffectInference
import SwiftSyntax

/// The resolved type of a method-call receiver, expressed as a type-name
/// classification rather than a full Swift type.
///
/// Mirrors `SwiftEffectInference.ResolvedReceiverType`, re-declared locally for
/// the same reason `PurityInferrer` re-declares rather than aliases: a
/// `typealias` would make every module naming this type import SEI directly.
/// The two are kept in step by `ReceiverTypeResolver`'s mapping below, which is
/// exhaustive over both — a case added upstream fails to compile here rather
/// than silently mapping to `.unresolved`.
public enum ResolvedReceiverType: Equatable, Sendable {

    /// A well-known stdlib collection or wrapper type. The payload is the bare
    /// type name (`"Array"`, `"Set"`, `"Dictionary"`, `"String"`, `"Optional"`).
    /// Used by `StdlibExclusions` to suppress bare-name inference matches on
    /// stdlib operations.
    case stdlibCollection(String)

    /// A user-defined or non-excluded type, identified by name only.
    case named(String)

    /// The receiver's type cannot be determined from syntax alone — chained
    /// access, generic-parameter receivers, or an un-annotated computed
    /// property.
    case unresolved
}

/// Thin forwarder onto the receiver-type resolver in the shared leaf.
///
/// The implementation moved to `SwiftEffectInference.ReceiverShapes` with the
/// heuristic inferrer that is its only real caller. Before the move the two
/// copies differed **only in factoring** — SEI's had extracted
/// `literalOrConstructorShape`, `uppercaseTypeName` and `memberBlockMembers`
/// helpers out of the inline forms here — with no behavioural difference. The
/// 29 existing `resolve` assertions pass unchanged against the forwarded
/// version, which is what establishes that.
///
/// Resolution is **syntactic**: it reads what the source literally says
/// (parameter annotations, pattern-binding annotations, literal shapes) and
/// never performs semantic resolution. It also never guesses — anything
/// ambiguous returns `.unresolved`, which callers must treat as "no opinion"
/// rather than "not a stdlib type".
public enum ReceiverTypeResolver {

    /// Resolves the receiver of a method call. For `x.foo(y)` returns the
    /// resolution of `x`; for `foo(y)` (no receiver) returns `.unresolved`.
    public static func resolve(
        receiverOf call: FunctionCallExprSyntax,
        localTypes: Set<String> = []
    ) -> ResolvedReceiverType {
        map(ReceiverShapes.resolve(receiverOf: call, localTypes: localTypes))
    }

    /// Resolves a single receiver expression, for callers not routing through a
    /// `FunctionCallExprSyntax`.
    public static func resolve(
        _ expr: ExprSyntax,
        localTypes: Set<String> = []
    ) -> ResolvedReceiverType {
        map(ReceiverShapes.resolve(expr, localTypes: localTypes))
    }

    /// Translates the leaf's classification into the local one. Exhaustive by
    /// construction: no `default`, so a case added upstream is a compile error
    /// here and gets a considered mapping rather than a silent `.unresolved`.
    static func map(_ resolved: SwiftEffectInference.ResolvedReceiverType) -> ResolvedReceiverType {
        switch resolved {
        case .stdlibCollection(let name): return .stdlibCollection(name)
        case .named(let name): return .named(name)
        case .unresolved: return .unresolved
        }
    }

    /// The inverse, for handing a locally-held classification back to the leaf.
    static func unmap(_ resolved: ResolvedReceiverType) -> SwiftEffectInference.ResolvedReceiverType {
        switch resolved {
        case .stdlibCollection(let name): return .stdlibCollection(name)
        case .named(let name): return .named(name)
        case .unresolved: return .unresolved
        }
    }
}
