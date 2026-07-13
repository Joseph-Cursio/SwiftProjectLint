import SwiftEffectInference

/// The effect tier a declaration claims, or that inference assigns it.
///
/// An alias onto `SwiftEffectInference.Effect`, which is the single oracle for the effect
/// axis. The name is retained because it is the vocabulary the rule visitors and their
/// diagnostics are written in — a `DeclaredEffect` is what a *declaration* asserts, as
/// distinct from the `ContextEffect` it runs in. Consumers reference the cases through this
/// alias and must `import SwiftEffectInference` (MemberImportVisibility).
public typealias DeclaredEffect = Effect
