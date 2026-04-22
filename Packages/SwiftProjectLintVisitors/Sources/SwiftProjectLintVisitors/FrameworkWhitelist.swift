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
    public static let hummingbird = "Hummingbird"
    public static let composableArchitecture = "ComposableArchitecture"
    public static let awsLambdaRuntime = "AWSLambdaRuntime"
    public static let httpPipeline = "HttpPipeline"

    /// Every framework this project recognises. Order-insensitive.
    /// Used as the default `enabledFrameworks` set when a project
    /// hasn't opted out of any framework's classifications.
    public static let knownFrameworks: Set<String> = [
        foundation, nio, awsLambdaEvents, logging, osLog, metrics, fluent,
        hummingbird, composableArchitecture, awsLambdaRuntime, httpPipeline
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

        // Hummingbird — error constructors (value types; throwing them
        // is the control-flow mechanism, but constructing the value
        // is pure).
        "HTTPError": hummingbird,
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
        "delete": fluent,
    ]

    /// Returns the framework that owns a given non-idempotent method
    /// name, or nil when the name isn't on any framework's list.
    public static func framework(forNonIdempotentMethod name: String) -> String? {
        nonIdempotentMethodsByFramework[name]
    }

    // MARK: - Idempotent methods (framework-gated)

    /// Maps a method name to the framework it belongs to, when the
    /// method is a known read-only / pure operation inside that
    /// framework. Fluent's query-builder reads are the motivating case:
    /// `db`, `query`, `all`, `first`, `filter` are all idempotent when
    /// invoked through FluentKit's `Database` / `QueryBuilder` surface,
    /// but have unrelated (usually also idempotent) senses elsewhere
    /// in Swift. Gating on `import FluentKit` resolves which module
    /// owns the name; the idempotent classification is correct for
    /// either interpretation, so a cross-framework false positive
    /// would only change the *reason* string, not the effect.
    ///
    /// HttpPipeline (slot 14) is the second framework on this table.
    /// `writeStatus`, `respond` etc. are freestanding curried functions
    /// in `pointfreeco/swift-web`'s HttpPipeline module, called via
    /// the `|>` and `>=>` pipe operators — `conn |> writeStatus(.ok)`
    /// reads as `writeStatus(.ok)(conn)`. They mutate `Conn<I, J, A>`
    /// state in a value-typed pipeline (each call returns a new `Conn`),
    /// so re-invocation with the same input yields the same response —
    /// observably idempotent at the response-builder boundary.
    /// 2-adopter evidence: isowords (12 fires) + pointfreeco www
    /// (4 fires) on `writeStatus` alone, plus `respond` shared shape.
    ///
    /// Unlike type-constructor whitelists, these are ordinary
    /// method-call names — they can appear as `.method()` on any
    /// receiver, or bare-style when chained after another call.
    /// The gate therefore does not require a receiver; the import
    /// presence is the load-bearing signal.
    private static let idempotentMethodsByFramework: [String: String] = [
        // FluentKit — query-builder reads.
        "db": fluent,
        "query": fluent,
        "all": fluent,
        "first": fluent,
        "filter": fluent,

        // HttpPipeline — response-pipeline primitives (pointfreeco/swift-web).
        // Both adopters use these via `|>` / `>=>` pipe-forward operators
        // on `Conn` state; each call is a value-typed mutation.
        "writeStatus": httpPipeline,
        "respond": httpPipeline,
    ]

    /// Returns the framework that owns a given idempotent method
    /// name, or nil when the name isn't on any framework's list.
    public static func framework(forIdempotentMethod name: String) -> String? {
        idempotentMethodsByFramework[name]
    }

    // MARK: - Per-framework reason phrasing (for diagnostic strings)

    /// Per-framework noun phrase used in the diagnostic reason string
    /// when a callee resolves through `idempotentMethodsByFramework`.
    /// Default (`"framework primitive"`) is generic and safe for any
    /// framework added without explicit phrasing.
    ///
    /// Existing per-framework phrasings:
    /// - FluentKit: `"query-builder read"` — matches the original
    ///   round-14 wording before slot 14 generalised the table.
    /// - HttpPipeline: `"pipeline primitive"` — accurate for
    ///   response-builder-pattern modules where the same name maps
    ///   to a curried `(Conn) -> Conn` primitive.
    private static let idempotentMethodPhrasingByFramework: [String: String] = [
        fluent: "query-builder read",
        httpPipeline: "pipeline primitive",
    ]

    /// Returns the per-framework noun phrase for the
    /// `idempotentMethodsByFramework` reason string. Falls back to
    /// `"framework primitive"` for any framework without an explicit
    /// override, so adding a new framework to the table doesn't
    /// require touching the inferrer.
    public static func idempotentMethodPhrasing(forFramework framework: String) -> String {
        idempotentMethodPhrasingByFramework[framework] ?? "framework primitive"
    }

    // MARK: - Idempotent receiver/method pairs (framework-gated)

    /// Idempotent `(receiver, method)` pairs — used when the method
    /// name alone is too ambiguous to whitelist but the combination
    /// is a specific framework idiom. Nested dictionary keyed by
    /// method first (matching the inferrer's lookup pattern) then
    /// by receiver name.
    ///
    /// Hummingbird's `request.decode(...)` and `parameters.require(...)`
    /// are the motivating pair. `decode` as a bare method would fire
    /// on any `.decode()` call in a Hummingbird-importing file (the
    /// existing codec-receiver path only matches `decoder` / `encoder`
    /// receivers), and `require` is generic enough to collide with
    /// user-defined validation helpers. Pinning to the specific
    /// framework-canonical receiver name avoids both problems.
    ///
    /// AWSLambdaRuntime's response-writer primitives
    /// (`outputWriter.write(...)`, `responseWriter.write(...)`,
    /// `responseWriter.finish()`) live here for the same reason:
    /// `write` is explicitly excluded from the bare-name whitelist
    /// (see `HeuristicEffectInferrer.nonIdempotentNames` commentary)
    /// because atomic-file / REST-semantics writes are idempotent but
    /// indistinguishable by name alone. The closure-parameter
    /// receiver names (`outputWriter` for `LambdaResponseWriter`,
    /// `responseWriter` for `LambdaResponseStreamWriter`) are the
    /// canonical names in the swift-aws-lambda-runtime v2.x handler
    /// signatures. The Lambda runtime's at-least-once contract
    /// dedup-guards invocation retries at its own boundary, so these
    /// calls are idempotent-in-replay by the runtime contract.
    ///
    /// Hummingbird Router DSL (slot 16) — `router.{get,post,put,patch,delete}`
    /// at route-registration sites. Hummingbird's `Router` exposes one
    /// HTTP-verb method per standard method, each of which registers a
    /// handler closure with the router's internal `TrieRouter`. From the
    /// retry-context lint's perspective these are startup-time registration
    /// calls, not request-scoped operations — annotating a `buildRouter()`
    /// or `addXRoutes(to router:)` helper with `@lint.context replayable`
    /// is a convenience to walk INTO the registered handler closures; the
    /// registration calls themselves should stay silent. Gating on the
    /// bare `router` receiver is the precision mechanism — it keeps the
    /// whitelist from silencing unrelated `.get` / `.post` / `.delete`
    /// methods on non-router receivers in the same file. 2-adopter
    /// evidence: `samalone/prospero` (3× `router.post` Run A + 11×
    /// `router.get` Run B) and
    /// `hummingbird-project/hummingbird-examples/open-telemetry`
    /// (1× `router.post` Run A + 2× `router.get` Run B) — identical
    /// rule-path shapes across both corpora.
    private static let idempotentReceiverMethodsByFramework: [String: [String: String]] = [
        "decode": ["request": hummingbird],
        "require": ["parameters": hummingbird],
        "write": [
            "outputWriter": awsLambdaRuntime,
            "responseWriter": awsLambdaRuntime,
        ],
        "finish": ["responseWriter": awsLambdaRuntime],
        "get": ["router": hummingbird],
        "post": ["router": hummingbird],
        "put": ["router": hummingbird],
        "patch": ["router": hummingbird],
        "delete": ["router": hummingbird],
    ]

    /// Returns the framework that owns a given idempotent
    /// `(receiver, method)` pair, or nil when the pair isn't listed.
    public static func framework(
        forIdempotentReceiver receiver: String,
        method: String
    ) -> String? {
        idempotentReceiverMethodsByFramework[method]?[receiver]
    }

    // MARK: - Bare-name overrides of the non-idempotent list (framework-gated)

    /// Bare-name callees that would otherwise hit
    /// `HeuristicEffectInferrer.nonIdempotentNames` but are structurally
    /// safe inside a specific framework's closure-parameter idiom. The
    /// bare-name check is consulted *before* the non-idempotent list so
    /// the framework import wins over the name heuristic.
    ///
    /// TCA's `Send<Action>` is the motivating case. Inside an `Effect`
    /// closure (`.run { send in ... await send(.action) ... }`) the
    /// `send` identifier is a closure parameter — calling it dispatches
    /// an action value through the reducer, which is a pure state
    /// transition, not a mail-sending side effect. The heuristic can't
    /// tell the closure-parameter `send` apart from a receiverless
    /// `mailer.send` by structure alone; the `ComposableArchitecture`
    /// import is the disambiguating signal.
    ///
    /// Precision:
    /// - Receiver must be nil — `mailer.send(.email)` keeps its
    ///   non-idempotent classification even in a TCA-importing file.
    /// - Exact-match only — `sendEmail(...)` still hits the prefix-match
    ///   non-idempotent path; only the literal callee name `send` is
    ///   exempted.
    private static let bareNameIdempotentOverridesByFramework: [String: String] = [
        "send": composableArchitecture,
    ]

    /// Returns the framework that owns a given bare-name override, or
    /// nil when the name isn't listed. Callers must additionally check
    /// that the call site has no receiver and that the framework is
    /// active in the current `FrameworkContext`.
    public static func framework(
        forBareNameIdempotentOverride name: String
    ) -> String? {
        bareNameIdempotentOverridesByFramework[name]
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
