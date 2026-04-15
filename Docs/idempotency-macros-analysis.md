# Idempotency Enforcement in Swift: Design Proposal

> A design for adding idempotency modeling to SwiftProjectLint via doc-comment annotations, Swift macros, and a phased static analysis engine.

---

## Overview

Swift has no first-class support for idempotency as a language or static-analysis concept. Functions that must be safe to call multiple times — event handlers, retry-wrapped network calls, upsert operations — carry that contract only in documentation or team convention. Violations are silent and often expensive.

This document proposes a multi-layer enforcement model for SwiftProjectLint:

1. **Annotation-based declaration** — `/// @lint.effect idempotent` and related doc-comment annotations establish intent, make assumptions reviewable, and give the linter a trigger point.
2. **Static body analysis** — the linter verifies that annotated functions actually call only idempotent operations, using an effect lattice with defined composition rules.
3. **Swift macro generation** — an `@Idempotent` peer macro generates companion test functions, enforcing the contract at runtime in addition to statically.
4. **Type-level safety** — protocols and strong types encode idempotency in the type system, enabling compile-time enforcement at generic boundaries.

Each layer is independently valuable and can be adopted incrementally.

---

## Foundational Concepts

### Idempotency Is Not Purity

The two properties are often conflated, but the enforcement model must treat them as distinct.

- **Purity**: No side effects; same inputs always produce the same outputs. `f(x) == f(x)` for any x.
- **Idempotency**: Calling multiple times produces the same *effect* as calling once. `f(f(x)) == f(x)`.

These overlap but are not equivalent:

```swift
// Pure but NOT idempotent
func append(to list: [Int], value: Int) -> [Int] {
    list + [value]  // deterministic, but f(f(x)) ≠ f(x)
}

// Idempotent but NOT pure
func setFlag(in db: Database, key: String) {
    db.set(key, true)  // has a side effect, but calling twice = calling once
}

// Neither
func chargeCard(amount: Int) { ... }

// Both
func compute(x: Int) -> Int { x * 2 }
```

The linter must reason about *effects on external state*, not just local non-determinism. A function that uses `UUID()` internally for a log trace is not necessarily non-idempotent — what matters is whether the non-deterministic value escapes the function boundary. This is covered in detail in the Effect Escaping section.

---

## Formalized Effect Lattice

A strict ordering defines how effects compose and conflict:

```
pure < idempotent < externallyIdempotent < non_idempotent
                  unknown (incomparable)
```

Where `unknown` is incomparable to `non_idempotent`; in enforcement, it is treated conservatively as `non_idempotent`.

`externallyIdempotent` sits between `idempotent` and `non_idempotent`: it represents operations that are made safe to retry via an external mechanism (idempotency keys, deduplication tables), rather than intrinsic function body properties. See the Idempotency Keys section for details.

**Composition rules** (for a function calling multiple callees):

| Callees include | Caller's inferred effect |
|---|---|
| pure only | pure |
| idempotent only | idempotent |
| any non_idempotent | non_idempotent |
| any unknown | unknown (warn; treat as non_idempotent in strict mode) |
| idempotent + unknown | unknown |

**Conflict detection** (declared annotation vs. inferred effect):

| Declared | Inferred | Lint Action |
|---|---|---|
| `idempotent` | `idempotent` | ✅ OK |
| `idempotent` | `non_idempotent` | ❌ Error |
| `idempotent` | `unknown` | ⚠️ Warning |
| `non_idempotent` | `idempotent` | ⚠️ Warning (over-declared) |
| `non_idempotent` | `non_idempotent` | ✅ OK |
| `externallyIdempotent` | `non_idempotent` | ✅ OK — key is the mechanism |
| `externallyIdempotent` | `idempotent` | ⚠️ Warning — simpler annotation applies |
| `idempotent` | `externallyIdempotent` | ❌ Error — declared stronger than body supports |
| (none) | `non_idempotent` | ℹ️ Suggestion to annotate |

---

## Annotation Grammar

### Doc-Comment Annotations

Doc-comment annotations serve as the primary declaration mechanism. They are additive — no structural changes to the codebase are required — and they document intent independently of any tooling.

The `@lint.` prefix avoids collision with DocC conventions (`@param`, `@returns`, `@throws`) and makes tool-specific annotations visually distinct:

```swift
/// @lint.effect idempotent
/// @lint.effect non_idempotent
/// @lint.effect externally_idempotent reason: "Stripe deduplicates on idempotency-key header"
/// @lint.context replayable
/// @lint.requires idempotency_key
/// @lint.unsafe reason: "provider guarantees deduplication"
```

**Why doc comments are the right default:**

- They tell reviewers "this function is expected to be safe to retry — be careful what you add"
- They make assumptions explicit during code review
- They force the author to commit to a semantic contract, rather than leaving it implicit
- They work incrementally: a codebase can adopt annotations gradually
- They mirror established practice: Swift's own `/// - Parameter`, Javadoc's `@throws`, Python docstrings — all valuable without compiler enforcement

Even when the linter can only verify 50% of violations, the annotations document the *intent* the linter checks against. That has independent value.

### Swift Macros as a Second Layer

Swift 5.9+ macros (`@attached(peer)`) can go further — surviving refactoring, enabling autocomplete, generating companion tests. Macros are a *second layer* that builds on the annotation contract, not a replacement for it.

| Mechanism | Audience | Value |
|---|---|---|
| `/// @lint.effect idempotent` | Human reviewers + linter | Documents intent; enables partial verification |
| `@Idempotent` macro | Compiler + test generator | Enforcement; automatic test generation |
| Both together | Everyone | Full spectrum |

The annotation grammar is the *lingua franca* that both humans and tools read. Macros can generate or verify the same annotations automatically.

---

## Context Annotations

Beyond annotating a function's own properties, it is useful to annotate the *execution context* in which a function runs. This catches a different class of bugs — violations that arise not from what a function does, but from where it is called.

```swift
/// @context replayable
/// At-least-once delivery; handler may run multiple times for same event
func handleOrderCreated(event: OrderCreatedEvent) async throws { ... }

/// @context retry_safe
/// Will be retried on transient failure; must be idempotent
func syncUserProfile(userID: UserID) async throws { ... }

/// @context once
/// Expected to run exactly once; non-idempotent operations OK
func migrateDatabase(from: SchemaVersion) async throws { ... }

/// @context idempotent_caller
/// This function ensures idempotency through its own mechanism; body check suppressed
func processPayment(id: PaymentID) async throws { ... }
```

### `@context replayable` and `@context retry_safe`

These two contexts place **requirements on callees**. The function may execute multiple times; therefore everything it calls must tolerate multiple executions.

**Enforcement — body analysis:**
- Callees annotated `@lint.effect pure` or `@lint.effect idempotent`: ✅ OK
- Callees annotated `@lint.effect externally_idempotent`: ⚠️ Warning — weaker contract, accepted with justification
- Callees annotated `@lint.effect non_idempotent`: ❌ Error
- Callees with no annotation and inferred `non_idempotent`: ❌ Error (Phase 2+)
- Callees with no annotation and inferred `unknown`: ⚠️ Warning

**Distinction between the two:** `replayable` implies the system delivers the call (event bus, message queue — outside the function's control). `retry_safe` implies the function or its caller initiates the retry on failure. Enforcement is identical; the distinction is documentary.

### `@context once` — The Inverse Guarantee

`@context once` is the complement of `retry_safe`. It does not constrain callees — a once-only migration is *allowed* to call non-idempotent operations, because that's the whole point. Instead, it places **requirements on callers**: this function must not be invoked in any retry context.

**Enforcement — call site analysis:**

```swift
// ❌ Error: retry context calls a once-only function — may execute it multiple times
/// @context retry_safe
func rebuildSearchIndex() async throws {
    try await migrateDatabase(from: .v1)  // @context once — cannot be called here
}

// ❌ Error: once-only function called inside an explicit retry loop
for attempt in 1...maxRetries {
    try await migrateDatabase(from: .v1)  // ❌
}

// ✅ OK: called from a non-retry context
func runStartupSequence() async throws {
    try await migrateDatabase(from: .v1)
}
```

A `@context once` function may freely call anything — it runs once, so all other guarantees are preserved. The violation arises only when it appears in a retry context.

**Limitation:** if a `@context once` function is stored as a closure and called later, the static analysis cannot detect the eventual call site. Call-site checking only works for direct invocations visible in the AST.

### `@context idempotent_caller` — Assertion with Mechanism

This is the most nuanced context and the one most easily confused with `@effect idempotent`. The distinction matters:

- **`@effect idempotent`**: the linter *verifies* the function body is idempotent through analysis. The function must pass the body check.
- **`@context idempotent_caller`**: the function *asserts* it produces idempotent outcomes through a mechanism the linter cannot fully verify (idempotency keys, a deduplication table, a transactional guard). Body check is suppressed; mechanism check replaces it.

```swift
// ❌ Wrong annotation — linter flags chargeCard as non_idempotent in the body
/// @effect idempotent
func processPayment(id: PaymentID) async throws {
    try await chargeCard(amount: payment.amount, idempotencyKey: .init(from: id))
    try await updateOrderStatus(id, status: .paid)
}

// ✅ Correct annotation — asserts idempotency is handled via the key mechanism
/// @context idempotent_caller
func processPayment(id: PaymentID) async throws {
    try await chargeCard(amount: payment.amount, idempotencyKey: .init(from: id))
    try await updateOrderStatus(id, status: .paid)
}
```

Because the body check is suppressed, the linter instead requires *evidence of a mechanism*:

1. **Key mechanism**: the function accepts an `IdempotencyKey` parameter, or constructs one from its inputs before any non-idempotent calls. ✅
2. **Deduplication guard**: the function checks a processed-ID set or similar guard before non-idempotent work. ✅
3. **Explicit override**: `@lint.unsafe reason: "..."` suppresses the mechanism requirement with a documented justification. ✅ with warning
4. **No visible mechanism**: ❌ — annotation is unverifiable; emit `idempotentCallerWithoutMechanism`

From the caller's perspective, `@context idempotent_caller` behaves like `@effect idempotent`: the function is safe to call from retry contexts.

### Context Interaction Matrix

| Caller's context | Callee is `@context once` | Callee is `@context retry_safe` / `replayable` | Callee is `@context idempotent_caller` |
|---|---|---|---|
| `retry_safe` / `replayable` | ❌ Would call once-function multiple times | ✅ | ✅ |
| `once` | ✅ Both run once | ✅ | ✅ |
| `idempotent_caller` | ❌ Caller may run multiple times; violates callee's once contract | ✅ | ✅ |
| (no context) | ✅ No retry implied | ✅ | ✅ |

### Rule Identifiers (Context)

```swift
case onceOperationInRetryContext      // @context once function called inside retry_safe / replayable body
case onceOperationInRetryLoop         // @context once function called inside a detected retry loop
case idempotentCallerWithoutMechanism // @context idempotent_caller with no visible key or guard mechanism
case retryContextCallingOnce          // retry_safe / replayable context directly calls @context once
```

---

## Swift Macro–Based Test Generation

### `@attached(peer)` — Generate a Companion Test

```swift
@attached(peer, names: prefixed(idempotency_test_))
public macro Idempotent() = #externalMacro(module: "IdempotencyMacros", type: "IdempotentMacro")
```

The instinct — generate a test that calls the function twice with the same inputs and asserts equivalent outcomes — is correct. The execution is harder than it first appears.

### The State-Capture Problem

The naive generated test has a fundamental flaw:

```swift
// ❌ MockDatabase() and snapshot() are conjured from nothing
@Test("Idempotency: upsertUser")
func idempotency_test_upsertUser() throws {
    let db = MockDatabase()          // macro cannot know this type exists
    try upsertUser(id: testUserID, name: "Alice")
    let stateAfterFirst = db.snapshot()  // macro cannot know this method exists
    try upsertUser(id: testUserID, name: "Alice")
    let stateAfterSecond = db.snapshot()
    #expect(stateAfterFirst == stateAfterSecond)
}
```

The macro has access to the function's *signature* — its name, parameters, return type, and effect specifiers. It has no access to the function's *dependencies*. A function returning `Void` gives the macro nothing to compare automatically.

The solution is a protocol that types opt into:

```swift
public protocol IdempotencyTestable {
    associatedtype IdempotencyState: Equatable
    func captureIdempotencyState() -> IdempotencyState
}
```

### Tiered Generation Strategy

**Tier 1 — Non-Void return type (fully automatic)**

When the function returns an `Equatable` value, the macro compares return values directly:

```swift
@Idempotent
func findUser(id: UserID) throws -> User { ... }

// Generated:
@Test("Idempotency: findUser")
func idempotency_test_findUser() throws {
    let result1 = try findUser(id: testUserID)
    let result2 = try findUser(id: testUserID)
    #expect(result1 == result2)
}
```

Limitation: only captures the return value. A function that returns a stable value but mutates external state will pass this test incorrectly.

**Tier 2 — Containing type conforms to `IdempotencyTestable` (state capture)**

```swift
extension UserRepository: IdempotencyTestable {
    struct State: Equatable { let users: [User]; let auditLog: [AuditEntry] }
    func captureIdempotencyState() -> State {
        State(users: db.allUsers(), auditLog: db.allAuditEntries())
    }
}

// Generated — captures full observable state, not just return value:
@Test("Idempotency: upsertUser")
func idempotency_test_upsertUser() throws {
    try upsertUser(id: testUserID, name: "Alice")
    let stateAfterFirst = captureIdempotencyState()
    try upsertUser(id: testUserID, name: "Alice")
    let stateAfterSecond = captureIdempotencyState()
    #expect(stateAfterFirst == stateAfterSecond)
}
```

**Tier 3 — Void return, no `IdempotencyTestable` (stub with guidance)**

When the macro can't determine what to compare, it generates a compilable stub with explicit TODOs:

```swift
// Generated stub — complete the state capture sections before running
@Test("Idempotency: sendNotification — STUB: complete state capture")
func idempotency_test_sendNotification() throws {
    // TODO: inject a spy/mock for the notification service before calling
    try sendNotification(to: testUserID, message: "Hello")
    let stateAfterFirst: Void = ()  // TODO: replace with state capture expression
    try sendNotification(to: testUserID, message: "Hello")
    let stateAfterSecond: Void = ()  // TODO: replace with state capture expression
    // TODO: #expect(stateAfterFirst == stateAfterSecond)
}
```

The stub compiles; the `Void` comparisons are trivially equal so the test passes. A failing TODO lint warning tells the author what to fill in.

### Actor-Isolated Functions

When `@Idempotent` is applied to an actor method, the generated peer must cross the actor boundary for state capture, requiring `async` on the test even if the method is synchronous:

```swift
actor UserCache {
    @Idempotent
    func upsertUser(_ user: User) { ... }
}

// Generated — note async even though upsertUser is sync:
@Test("Idempotency: UserCache.upsertUser")
func idempotency_test_UserCache_upsertUser() async throws {
    let cache = UserCache()
    await cache.upsertUser(testUser)
    let stateAfterFirst = await cache.captureIdempotencyState()
    await cache.upsertUser(testUser)
    let stateAfterSecond = await cache.captureIdempotencyState()
    #expect(stateAfterFirst == stateAfterSecond)
}
```

The macro detects actor context via the `ActorDeclSyntax` parent and forces `async` on the generated test regardless of the method's own `effectSpecifiers`.

### Property-Based Testing

The fixed-input double-call pattern only tests one point in the input space. A function that is idempotent for `name: "Alice"` but not for `name: ""` will pass undetected.

When all parameter types conform to `IdempotencyTestInputProvider`, the macro generates a parameterized test:

```swift
public protocol IdempotencyTestInputProvider {
    static var idempotencyTestValues: [Self] { get }
}

// Generated parameterized test
@Test("Idempotency: upsertUser", arguments: zip(
    [UserID("u1"), UserID("u2"), UserID("u3")],
    ["Alice", "Bob", ""]
))
func idempotency_test_upsertUser(id: UserID, name: String) throws {
    try upsertUser(id: id, name: name)
    let stateAfterFirst = captureIdempotencyState()
    try upsertUser(id: id, name: name)
    let stateAfterSecond = captureIdempotencyState()
    #expect(stateAfterFirst == stateAfterSecond)
}
```

When parameter types don't conform, it falls back to a single call with placeholder literals.

### `#assertIdempotent` — Freestanding Macro

```swift
// Simple form — return value only
#assertIdempotent {
    try await chargeCard(amount: 100, key: idempotencyKey)
}

// State-capture form — provide a capturing closure for side effects
#assertIdempotent(capturing: { processor.captureIdempotencyState() }) {
    try await processor.chargeCard(amount: 100, key: idempotencyKey)
}
```

The second form expands to:

```swift
let _state1 = processor.captureIdempotencyState()
try await processor.chargeCard(amount: 100, key: idempotencyKey)
let _stateAfter1 = processor.captureIdempotencyState()
try await processor.chargeCard(amount: 100, key: idempotencyKey)
let _stateAfter2 = processor.captureIdempotencyState()
#expect(_stateAfter1 == _stateAfter2, "Second call produced different state than first")
```

The pre-call capture (`_state1`) is available for debugging when the assertion fails, to show what state existed before either call.

---

## Protocol-Based Type Safety

### Pattern A: Marker Protocols

```swift
public protocol IdempotentOperation {}
public protocol NonIdempotentOperation {}
```

Pure declarations of intent — no added interface, just a conformance the linter and type system can detect. Analogous to `Sendable` or `Hashable` without synthesis.

**Strength**: Zero boilerplate; drop-in on existing types.  
**Weakness**: Protocols attach to *types*, not free functions. Most Swift APIs are methods or free functions — neither is directly addressable.

### Pattern B: Operation Objects (Command Pattern)

```swift
public protocol IdempotentOperation {
    associatedtype Input
    associatedtype Output
    func execute(_ input: Input) throws -> Output
}
```

The killer feature is generic constraints at call sites — this is where protocols outperform any annotation:

```swift
// Compiler enforces idempotency — passing a NonIdempotentOperation here is a compile error
func withRetry<Op: IdempotentOperation>(
    _ operation: Op,
    input: Op.Input,
    maxRetries: Int = 3
) throws -> Op.Output {
    var lastError: Error?
    for _ in 0..<maxRetries {
        do { return try operation.execute(input) }
        catch { lastError = error }
    }
    throw lastError!
}
```

No annotation system can do this. `/// @lint.effect idempotent` produces a lint warning at best; `Op: IdempotentOperation` is a hard compile error.

### Pattern C: Effect-Tagged Function Wrappers

A middle ground — wrap free functions in typed containers without requiring full operation objects:

```swift
public struct Idempotent<Input, Output> {
    public let run: (Input) throws -> Output
}

public struct NonIdempotent<Input, Output> {
    public let run: (Input) throws -> Output
}

// Retry context — type system enforces the constraint
func withRetry<I, O>(_ op: Idempotent<I, O>, input: I) throws -> O { ... }
```

This brings the effect into the *value* rather than the *type definition*, which works for free functions and closures without restructuring.

### The Critical Limitation: Protocols Don't Verify Behavior

A type can lie:

```swift
struct LyingOperation: IdempotentOperation {
    func execute(_ id: UserID) throws -> User {
        try db.insert(User(id: UUID(), ...))  // non-idempotent — but conforms
    }
}
```

This is the same problem as `Sendable` with `@unchecked` — conformance is a *declaration*, not a *proof*. The linter's role: when a type conforms to `IdempotentOperation`, verify the body. The protocol replaces `/// @lint.effect idempotent` as the trigger; the body-checking logic is identical.

### The `@unchecked` Escape Hatch

```swift
struct ExternalServiceCall: @unchecked IdempotentOperation {
    func execute(_ id: PaymentID) throws -> Receipt {
        // External API guarantees idempotency via idempotency key,
        // but we can't prove it from the body alone
        try paymentGateway.charge(id, idempotencyKey: id.rawValue)
    }
}
```

`@unchecked` suppresses the body check while preserving the type-system constraint — callers still get the compile-time guarantee even though it's asserted rather than proven.

### Composition

Protocols compose naturally where annotations cannot:

```swift
// Conditional conformance — a chain of idempotent operations is idempotent
extension ChainedOperation: IdempotentOperation
    where First: IdempotentOperation, Second: IdempotentOperation {}

// Protocol hierarchy — pure is strictly stronger than idempotent
public protocol PureOperation: IdempotentOperation {}

// Existentials (Swift 5.7+) for heterogeneous retry queues
func validateQueue(_ ops: [any IdempotentOperation]) { ... }
```

### Honest Trade-offs vs. Annotations

| Dimension | Protocols | Doc-comment annotations |
|---|---|---|
| Compiler enforcement | Hard errors via generic constraints | Never — lint only |
| Free functions | Can't attach directly (Pattern C works around this) | Works naturally |
| Refactoring safety | Conformances travel with the type | Comments can be orphaned |
| Incrementally adoptable | Requires operation-object restructuring | Additive, no restructuring |
| Composability | First-class via generics | No composition model |
| Existing codebase fit | Requires architectural buy-in | Drop-in on any function |

The right answer is **both**: protocols for new operation-object code where the compile-time guarantee matters; annotations for existing APIs and free functions where structural change isn't feasible.

---

## Effect Escaping Analysis

A naive heuristic approach — flagging `UUID()`, `Date()`, `array.append` as always non-idempotent — produces significant false positives in practice:

```swift
// UUID used for internal tracing only — the function IS idempotent at business logic level
/// @lint.effect idempotent
func processPayment(id: PaymentID, amount: Int) {
    let traceID = UUID()  // internal only, not persisted, not returned
    log.trace(traceID, "processing \(id)")
    db.upsert(Payment(id: id, amount: amount))
}
```

Flagging `UUID()` here is wrong. The linter must distinguish between non-determinism that **escapes** the function boundary and non-determinism that is **local and discarded**:

```swift
// Non-idempotent value is LOCAL and DISCARDED — function may still be idempotent
func processPayment(id: PaymentID) {
    let spanID = UUID()         // local trace, not persisted
    log.debug("span: \(spanID)")
    db.upsert(Payment(id: id))  // idempotent
}

// Non-idempotent value ESCAPES as return value — function is non-idempotent
func createUser() -> User {
    User(id: UUID())  // UUID escapes — each call returns a different User
}

// Non-idempotent value ESCAPES via persistence — function is non-idempotent
func createAuditEntry(action: String) {
    db.insert(AuditLog(id: UUID(), action: action))  // UUID persisted
}
```

Implementing escape analysis properly requires data-flow tracking. A practical approximation for the SwiftSyntax-based approach:

1. Flag `UUID()`, `Date()`, etc. as **potentially non-idempotent sources**
2. Track whether the value is:
   - Passed to a `db.insert` / `db.create` / `append` → **likely escapes** → flag
   - Used only in logging calls or local scope → **likely local** → suppress
3. Annotate ambiguous cases and let the author decide

---

## Retry Pattern Detection

Detect known retry patterns syntactically and enforce idempotency on their bodies:

```swift
// Pattern 1: Named retry function
retry {
    chargeCard(amount: 100)  // ❌
}

// Pattern 2: For loop with retry semantics
for attempt in 1...maxRetries {
    try await chargeCard(amount: 100)  // ❌
}

// Pattern 3: URLSession with retry middleware
session.dataTask(retryPolicy: .exponential) { ... chargeCard(...) }
```

Detection strategy:
- Maintain a **known retry call list**: `retry(_:)`, `withRetry(_:)`, `retryable(_:)`, etc.
- Detect `for` loops iterating over `1...N` or `0..<N` that contain `try await` calls
- Check function bodies passed to known retry wrappers for `@lint.effect non_idempotent` calls

---

## Swift Concurrency Interactions

Swift concurrency creates two independent problems for idempotency analysis: actors introduce a new class of idempotency bug that doesn't exist in synchronous code, and the async/await ecosystem introduces retry patterns the detection heuristics above don't cover.

### Actors Don't Imply Idempotency

Actor isolation serializes *access* to state — it prevents concurrent mutation. It does not prevent repeated mutation:

```swift
actor UserCache {
    // Idempotent — setting a key to the same value is safe to repeat
    func upsert(_ user: User) {
        users[user.id] = user
    }

    // Non-idempotent — appending grows the collection on every call
    func append(_ user: User) {
        users[user.id] = user
        auditLog.append(user)  // ❌ each call adds another entry
    }
}
```

The linter treats actor method bodies exactly like any other function body — actor isolation is irrelevant to idempotency analysis.

### Actor Reentrancy Breaks the Check-Then-Act Pattern

Actors in Swift are *reentrant*: when an actor method hits an `await`, it suspends and other callers can enter. The classic "check then act" idempotency guard fails silently across a suspension point:

```swift
actor PaymentProcessor {
    private var processedIDs: Set<PaymentID> = []

    func process(_ id: PaymentID) async throws {
        // ❌ Reentrancy hazard: another caller can enter between the guard and the insert
        guard !processedIDs.contains(id) else { return }
        try await chargeCard(id)  // suspension point — actor is now open to re-entry
        processedIDs.insert(id)   // too late
    }
}
```

Two concurrent callers both pass the `guard`, both `await chargeCard`, both charge the card. The actor serialized their *reads* of `processedIDs` but not the full check-suspend-act sequence.

The fix is to claim the slot *before* the suspension point:

```swift
actor PaymentProcessor {
    func process(_ id: PaymentID) async throws {
        guard !processedIDs.contains(id) else { return }
        processedIDs.insert(id)  // ✅ claim before any suspension
        do {
            try await chargeCard(id)
        } catch {
            processedIDs.remove(id)  // compensate on failure
            throw error
        }
    }
}
```

**This is a detectable pattern.** The linter can flag:

```
Inside an actor method:
  guard !collection.contains(id) → ...
  [one or more await expressions]
  collection.insert(id)           ← insert appears AFTER a suspension
```

New rule: `actorReentrancyIdempotencyHazard`.

### Additional Retry Patterns Introduced by Swift Concurrency

**Pattern 4: Unstructured `Task` inside a retry loop**

```swift
for attempt in 1...maxRetries {
    let task = Task { try await chargeCard(amount: 100) }  // ❌ — body is detached
    _ = try await task.value
}
```

The `try await` is on `task.value`, not on `chargeCard` directly. The `ForStmtSyntax` heuristic must trace into `Task { }` closures.

**Pattern 5: `withThrowingTaskGroup` used as a retry mechanism**

```swift
try await withThrowingTaskGroup(of: Receipt.self) { group in
    for attempt in 1...maxRetries {
        group.addTask { try await chargeCard(amount: 100) }  // ❌ parallel retries
    }
    return try await group.next()!
}
```

A `for` loop over `addTask` is structurally a retry loop.

**Pattern 6: Recursive async retry**

```swift
func retryableCharge(attempt: Int = 0) async throws -> Receipt {
    do {
        return try await chargeCard(amount: 100)  // ❌
    } catch where attempt < 3 {
        return try await retryableCharge(attempt: attempt + 1)
    }
}
```

Detection requires identifying recursive calls in `catch` blocks.

**Pattern 7: SwiftUI `.task {}` view modifier**

```swift
.task {
    try? await chargeCard(amount: 100)  // ❌ — runs every time the view appears
}
```

`.task {}` is called each time the view appears. Navigating back and forth replays the body — functionally equivalent to a retry for idempotency purposes. This is a high-value lint target in SwiftUI codebases.

### Async/Await Annotations

The `async` keyword does not change a function's effect classification — a function is idempotent or not independent of whether it suspends. The annotation grammar applies directly:

```swift
/// @lint.effect idempotent
func upsertUser(id: UserID) async throws { ... }  // async doesn't change the effect
```

Generated test peers must mirror `effectSpecifiers` from `FunctionDeclSyntax` (`asyncSpecifier`, `throwsSpecifier`):

```swift
// Generated — async variant
@Test("Idempotency: upsertUser")
func idempotency_test_upsertUser() async throws {
    try await upsertUser(id: testUserID, name: "Alice")
    let stateAfterFirst = captureIdempotencyState()
    try await upsertUser(id: testUserID, name: "Alice")
    let stateAfterSecond = captureIdempotencyState()
    #expect(stateAfterFirst == stateAfterSecond)
}
```

### Rule Identifiers (Concurrency)

```swift
case actorReentrancyIdempotencyHazard  // guard-await-insert ordering violation in actor method
case nonIdempotentInTaskRetry          // non-idempotent call inside Task { } within retry loop
case nonIdempotentInTaskGroup          // non-idempotent addTask inside counted retry loop
case nonIdempotentInRecursiveRetry     // non-idempotent call in recursive catch-and-retry pattern
case nonIdempotentInSwiftUITask        // non-idempotent call in .task {} view modifier
```

---

## Idempotency Keys as a First-Class Concept

Idempotency keys represent a categorically different form of idempotency from the function-level analysis above. They make a *non-idempotent operation* safe to retry by outsourcing deduplication to an external system.

### The `externallyIdempotent` Effect State

The effect lattice (see Foundational Concepts) includes `externallyIdempotent` between `idempotent` and `non_idempotent`. It's weaker than intrinsic idempotency in two ways:

- It depends on an external system's stateful contract, not the local function body
- A wrong key (unstable, colliding, or too broadly scoped) silently degrades it back to `non_idempotent`

```swift
/// @lint.effect externally_idempotent reason: "Stripe deduplicates on idempotency-key header"
func chargeCard(amount: Int, idempotencyKey: IdempotencyKey) throws -> Receipt { ... }
```

### Key Quality: What Makes a Key Valid

Three properties of a valid key:
1. **Stable across retries** — identical value on every retry of the same logical operation
2. **Input-derived or pre-generated** — not sourced from fresh entropy at the call site
3. **Correctly scoped** — unique per logical operation, not reused across different operations

```swift
// ❌ New key generated each iteration
for attempt in 1...maxRetries {
    let key = UUID().uuidString
    try chargeCard(amount: 100, idempotencyKey: key)
}

// ✅ Key derived deterministically from inputs
let key = IdempotencyKey(from: paymentRequest)
for attempt in 1...maxRetries {
    try chargeCard(amount: 100, idempotencyKey: key)
}
```

### `IdempotencyKey` as a Strong Type

The most effective lint target is eliminating `String` as the key parameter type:

```swift
public struct IdempotencyKey: Hashable, Sendable {
    public let rawValue: String

    public init(from source: some IdempotencyKeySource) {
        self.rawValue = source.idempotencyKeyValue
    }

    public init(preGenerated value: String) {
        self.rawValue = value
    }
    // No init from UUID() — there is no path that accepts raw entropy.
}

public protocol IdempotencyKeySource {
    var idempotencyKeyValue: String { get }
}

extension PaymentRequest: IdempotencyKeySource {
    var idempotencyKeyValue: String {
        "\(userID):\(amount):\(currency):\(orderID)"
    }
}
```

With this type in place, passing `UUID().uuidString` directly as a key is a compile error, not a lint warning.

### Lintable Bad Patterns

Even without the strong type, several patterns are detectable by the linter:

**Pattern 1: `UUID()` passed directly as idempotency key**

```swift
// Detectable: argument labeled idempotencyKey receives UUID()
try chargeCard(amount: 100, idempotencyKey: UUID().uuidString)  // ❌
```

Detection: at any call site where an argument label matches `/idempotency.?key/i`, check if the argument expression is or contains `UUID()` or `Date()`.

**Pattern 2: Key generated inside a retry loop body**

```swift
for attempt in 1...maxRetries {
    let key = UUID().uuidString           // ❌ key is generated fresh each iteration
    try chargeCard(amount: 100, idempotencyKey: key)
}
```

Detection: inside a retry context body, flag any `let key = UUID()` whose binding is used as an idempotency key argument in the same scope. The key must be defined *outside* the retry scope.

**Pattern 3: `@lint.requires idempotency_key` function called without a key in retry context**

When a function is annotated `@lint.requires idempotency_key`, call sites inside retry contexts that omit the key argument are flagged.

### `@lint.requires idempotency_key` — Enforcement Definition

The linter enforces this in two directions:

**On the declaration:** the annotated function must have a parameter whose label matches `/idempotency.?key/i`. If the function body doesn't use that parameter to dedup or pass it to an external system, that's a warning (annotation without mechanism).

**On call sites:** inside any retry context, a call to a `@lint.requires idempotency_key` function must provide a key argument whose value is not derived from fresh entropy in the retry scope.

### Rule Identifiers (Idempotency Keys)

```swift
case unstableIdempotencyKey         // UUID() or other fresh entropy used as key value
case idempotencyKeyGeneratedInRetry // key binding created inside retry scope body
case missingIdempotencyKey          // @lint.requires idempotency_key function called without key in retry context
case idempotencyKeyMechanismMissing // @lint.effect externally_idempotent declared but no key parameter found
```

---

## Integration with SwiftProjectLint

### New Visitor: `IdempotencyVisitor`

```swift
// Sources/Core/Architecture/Visitors/IdempotencyVisitor.swift

final class IdempotencyVisitor: BasePatternVisitor {

    // Pass 1: Extract annotations from doc comments
    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        let effects = EffectAnnotationParser.parse(from: node.leadingTrivia)
        symbolTable.register(node.name.text, effects: effects)
        return .visitChildren
    }

    // Pass 2: Check call expressions in annotated contexts
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let currentContext = currentFunctionContext else { return .visitChildren }
        if currentContext.declaredEffect == .idempotent {
            checkCalleeIdempotency(node)
        }
        return .visitChildren
    }

    // Detect retry patterns
    override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
        if isRetryPattern(node) {
            retryContextStack.push(.retryLoop(node))
        }
        return .visitChildren
    }

    // Detect IdempotentOperation conformance
    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        if conformsTo(node, protocol: "IdempotentOperation") {
            scheduleBodyCheck(for: node, effect: .idempotent)
        }
        return .visitChildren
    }
}
```

### New Rule Identifiers

```swift
// In RuleIdentifier enum
case idempotencyViolation                // @effect idempotent calls @effect non_idempotent
case nonIdempotentInRetryContext         // non-idempotent call inside retry wrapper
case nonIdempotentInReplayableContext    // non-idempotent in @context replayable
case uuidEscapesIdempotentFunction      // UUID() result persisted inside @effect idempotent
case mixedIdempotencyEffects            // function has both idempotent and non-idempotent callees
case unannotatedSideEffectFunction      // function has side effects but no @effect annotation
```

### Cross-File Support via `CrossFileAnalysisEngine`

Effect propagation that is truly meaningful requires cross-file analysis — most violations span files. The existing `CrossFileAnalysisEngine` hosts the inter-file symbol table needed for Phase 3 propagation. The `IdempotencyVisitor` populates the table per-file; the engine computes the call graph and re-runs violation checks.

---

## Phased Implementation Roadmap

### Phase 1: Static Annotation Enforcement (no inference)
- Parse `/// @lint.effect` annotations from `leadingTrivia`
- Build a per-file effect table: `[FunctionName: DeclaredEffect]`
- Rule: If `@effect idempotent` function calls another function explicitly annotated `@effect non_idempotent` → error
- No inference. Zero false positives from heuristics.

### Phase 2: Heuristic Inference
- Flag known sources: `UUID()`, `Date()`, `arc4random()`
- Flag known mutations: `array.append`, `db.insert` (not `db.upsert`)
- Flag known network patterns: `URLSession.dataTask` with POST
- Apply escape analysis to reduce false positives
- Surface as warnings (not errors) unless overridden by annotation

### Phase 3: Call Graph Propagation
- Use `CrossFileAnalysisEngine` to build a cross-file call graph
- Propagate effects upward: if B is `non_idempotent` and A calls B, A is inferred `non_idempotent`
- Surface as suggestions where unannotated functions have inferred `non_idempotent` effects

### Phase 4: Context Enforcement
- Support `@lint.context` annotations
- Enforce that functions in replayable/retry contexts only call idempotent operations

### Phase 5: Macro-Based Generation (requires Swift macro support)
- `@Idempotent` macro generates peer test functions using the tiered strategy above
- Requires a separate `IdempotencyMacros` target in `Package.swift`

---

## Scope: What Belongs in This Repo

This proposal has drifted into designing a general-purpose effect system for Swift — one that involves a new macro library (`IdempotencyMacros`), new protocols (`IdempotencyTestable`, `IdempotencyKeySource`, `IdempotencyKey`), a strong type system for keys, and runtime test generation. That's a distributable Swift package, not a lint rule.

SwiftProjectLint's job is to analyze code that already exists. A linter is a *consumer* of contracts, not a *definer* of them. The natural split is:

**A separate package** — `SwiftIdempotency` or similar — that defines:
- The `@Idempotent` macro
- `IdempotencyTestable`, `IdempotencyKeySource`
- `IdempotencyKey` strong type
- `#assertIdempotent`

Projects adopt this package and annotate their code with it.

**SwiftProjectLint's actual role** — detect violations against those contracts:
- Flag non-idempotent calls inside `@Idempotent`-annotated functions
- Detect retry contexts calling unannotated functions
- Flag `UUID()` passed as an idempotency key
- Detect the actor reentrancy pattern

This is also a cleaner adoption story. A team can use the `SwiftIdempotency` package purely for the `@Idempotent` macro and generated tests, with no linter involved. A team that wants enforcement adds SwiftProjectLint on top.

The linter proposal that actually belongs in this repo is probably just Phase 1 and the retry/actor pattern detection — maybe 3-4 rule identifiers, one visitor, and a doc-comment annotation parser. The rest of this document is designing the ecosystem around it.

---

## Recommended First Step

Implement **Phase 1** — pure annotation enforcement with zero inference:

1. An `EffectAnnotationParser` that reads `/// @lint.effect` from `leadingTrivia`
2. A per-file `EffectSymbolTable` mapping function names to declared effects
3. An `IdempotencyVisitor` that cross-references calls within annotated functions
4. Two `RuleIdentifier` cases: `idempotencyViolation` and `nonIdempotentInRetryContext`

This delivers real value immediately, with no false positives from heuristics, and establishes the foundation for phases 2–5.

---

*Document prepared April 2026.*

---

## Target Codebase for Validation

When choosing an open-source Swift library to validate these ideas against, the natural instinct is **apple/swift-nio** — it's Apple-maintained, uses event-driven handlers, and has idempotency-adjacent concerns. On closer inspection it's the wrong target for this work.

### Why SwiftNIO Fights You

- **Reference-type handlers** — NIO's `ChannelHandler` types are class-based with shared mutable state. Static body analysis on reference types is noisier and produces more ambiguous results than on value types or free functions.
- **Runtime enforcement already in place** — The idempotency contracts NIO cares about (e.g. `EventLoopPromise` can only be fulfilled once) are already crash-enforced at runtime. Annotation-layer detection adds less marginal value when the runtime already catches the violation.
- **Below the business logic layer** — NIO sits at the transport and channel-pipeline level. The violations this system is designed to catch (duplicate charges, double-sent emails, repeated database inserts) don't live in NIO code. The interesting idempotency bugs live in the application code *above* it.
- **Harder to demo** — It's not immediately obvious to outside readers why NIO channel pipeline code carries `@context replayable` annotations. The connection between the annotation and the bug it prevents requires significant context.

### Stronger Targets

**apple/swift-aws-lambda-runtime** is the strongest proof-of-concept target:

- Lambda's SQS and SNS triggers are *at-least-once delivery* by specification — every handler is objectively `@context replayable`, not a judgment call.
- The library's own documentation tells users their handlers must be idempotent. The annotation system would make this explicit and machine-checkable.
- Violations are real and costly: duplicate DynamoDB writes, double-charges, double-sent confirmation emails.
- The library is small enough that a meaningful fraction of it can be annotated to demonstrate the system end-to-end.

**vapor/vapor** is the best target for breadth:

- HTTP middleware pipeline, ORM `create` vs. `upsert`, payment webhook handlers — this is where developers write the non-idempotent bugs this linter catches.
- The `req.db.create()` vs. `req.db.upsert()` distinction maps directly onto the effect lattice.
- Large enough that real-world variance in the violation patterns can be observed.

**pointfreeco/swift-composable-architecture** is the best target for the protocol and type-safety layer:

- Reducers are required to be pure; side effects go in `Effect`. The `pure < idempotent < non_idempotent` lattice maps almost exactly onto TCA's reducer/effect split.
- Violations (side effects in reducers) are common, well-understood, and the community already cares about them.
- Good for demonstrating that `IdempotentOperation` protocol conformance on a `Reducer` type is equivalent to TCA's own architectural constraint — just made compiler-checkable.

**grpc/grpc-swift** complements the key-based model:

- gRPC has explicit retry policies in the proto spec. Service handler annotations map directly to `@context retry_safe`.
- Interceptors are a natural place for idempotency key injection — maps to `@lint.requires idempotency_key`.

### Recommended Approach

Start with **swift-aws-lambda-runtime** for Phase 1 validation: the `@context replayable` annotation is objectively correct on every handler, so there's no ambiguity about whether the annotation is accurate. Pick two or three handlers that contain a known non-idempotent call (a `db.insert`, a notification send), annotate them, and verify the linter fires. Then add the compensating fix (`db.upsert`, deduplication guard) and verify it goes silent. That's a clear, repeatable demonstration of the system working correctly against real production code.
