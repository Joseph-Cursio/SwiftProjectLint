import Foundation

/// Per-framework grouping of the `HeuristicEffectInferrer` whitelists.
///
/// Round 14 split the previously-monolithic `idempotentFrameworkTypes`
/// (PR #9) into per-framework groups so the inferrer can gate each group
/// by `import` presence in the file under analysis. Without this gate, a
/// user-defined `class Counter` in an adopter module with no `import
/// Metrics` would classify as observational just because the name matched
/// swift-metrics' `Counter`.
///
/// Gating is enforced in `HeuristicEffectInferrer` via
/// `FrameworkContext`, which combines:
///   - `imports` — the set of module names imported in the current file
///   - `enabledFrameworks` — per-project config override
///
/// Both are optional; when nil, the inferrer falls back to the pre-round-
/// 14 "apply every whitelist by name" behaviour for test backwards
/// compatibility.
public enum FrameworkWhitelist {

    // MARK: - Framework names (opaque strings — used as dictionary keys)

    public static let foundation = "Foundation"
    public static let nio = "NIOCore"
    public static let awsLambdaEvents = "AWSLambdaEvents"
    public static let logging = "Logging"
    public static let osLog = "os"
    public static let metrics = "Metrics"
    public static let fluent = "FluentKit"

    /// Every framework this project recognises. Order-insensitive.
    /// Used as the default `enabledFrameworks` set when a project
    /// hasn't opted out of any framework's classifications.
    public static let knownFrameworks: Set<String> = [
        foundation, nio, awsLambdaEvents, logging, osLog, metrics, fluent
    ]

    // MARK: - Idempotent type constructors (bare-identifier call)

    /// Maps a type-constructor name (as it appears in source) to the
    /// framework it comes from. `JSONDecoder` → `"Foundation"`. Lookup
    /// returns nil for names not on any framework's list.
    private static let idempotentTypesByFramework: [String: String] = [
        // Foundation — pure codec containers + immutable byte containers.
        // Configurable but no shared mutable state; equal inputs → equal outputs.
        "JSONDecoder": foundation,
        "JSONEncoder": foundation,
        "PropertyListDecoder": foundation,
        "PropertyListEncoder": foundation,
        "Data": foundation,

        // SwiftNIO — pure byte buffers and views.
        "ByteBuffer": nio,
        "ByteBufferAllocator": nio,

        // AWS Lambda events — response constructors (build a response
        // value from inputs; no side effects beyond allocation).
        "ALBTargetGroupResponse": awsLambdaEvents,
        "APIGatewayResponse": awsLambdaEvents,
        "APIGatewayV2Response": awsLambdaEvents,
    ]

    /// Returns the framework that owns a given idempotent type
    /// constructor, or nil when the name isn't on any framework's list.
    public static func framework(forIdempotentTypeConstructor name: String) -> String? {
        idempotentTypesByFramework[name]
    }

    // MARK: - Non-idempotent methods (receiver-based call)

    /// Maps a method name (as it appears in source on the receiver side)
    /// to the framework it comes from. `save` → `"FluentKit"`. Lookup
    /// returns nil for names not on any framework's list.
    ///
    /// Used for verbs that are *universally* non-idempotent inside a
    /// framework but ambiguous enough elsewhere that we don't want them
    /// in the global bare-name whitelist. Fluent's `save`/`update`/`delete`
    /// are the motivating case — called on any `Model`-conforming type
    /// they always hit the database, but `Set.update(with:)` in stdlib
    /// or `cache.save()` on an in-memory store have different semantics.
    /// Gating on `import FluentKit` resolves the ambiguity.
    private static let nonIdempotentMethodsByFramework: [String: String] = [
        "save": fluent,
        "update": fluent,
        "delete": fluent,
    ]

    /// Returns the framework that owns a given non-idempotent method
    /// name, or nil when the name isn't on any framework's list.
    public static func framework(forNonIdempotentMethod name: String) -> String? {
        nonIdempotentMethodsByFramework[name]
    }
}

/// Combines file-level imports and project-level config into an
/// "is this framework's whitelist active right now?" predicate. Used by
/// `HeuristicEffectInferrer` to gate per-framework classifications.
///
/// ## Semantics
///
/// `imports` is the **concrete** set of base module names the enclosing
/// source file imports (see `ImportCollector.imports(in:)`). An empty
/// set means "no framework-gated whitelists fire" — synthetic fixtures
/// without imports and adopter files that simply don't use a given
/// framework behave identically. Callers that want to bypass the gate
/// must supply the relevant framework name explicitly.
///
/// When `enabledFrameworks` is `nil`, treat every framework as enabled —
/// the default when a project hasn't set `enabled_framework_whitelists`
/// in its `.swiftprojectlint.yml`. A non-nil value restricts
/// classification to the listed frameworks.
///
/// Both the import gate and the config gate must be active for the
/// whitelist to fire.
public struct FrameworkContext: Sendable {
    public let imports: Set<String>
    public let enabled: Set<String>?

    public init(imports: Set<String>, enabled: Set<String>?) {
        self.imports = imports
        self.enabled = enabled
    }

    public func isFrameworkActive(_ framework: String) -> Bool {
        let importOK = imports.contains(framework)
        let enabledOK = enabled?.contains(framework) ?? true
        return importOK && enabledOK
    }
}
