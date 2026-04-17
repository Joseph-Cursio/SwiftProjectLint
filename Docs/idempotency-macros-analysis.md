# Idempotency Enforcement in Swift: Design Proposal

> A design for adding idempotency modeling to SwiftProjectLint via doc-comment annotations, Swift macros, and a phased static analysis engine.

---

## Preview: Idempotency in the real (non-computer) world

Idempotent systems are designed around desired end state, not state transitions. Non-idempotent systems require the caller to track history.


### Example 1: Car Door Lock (Idempotent)

The remote control on my car locks the doors—even if they’re already locked. I don’t need to remember whether I’ve locked the car; I can press the button again at any time and be confident the car will end up locked.

This is an example of idempotency in the real world. The action is defined in terms of the desired end state (“locked”), not a transition (“toggle lock”). Repeating the action doesn’t introduce new effects—it simply ensures the same outcome.

Notably, pressing the lock button when the doors are already locked has no mechanical effect at all—the latches don’t move, nothing changes in the car’s physical state. The only thing the user gains is peace of mind: the certainty that the car is locked, without having to remember whether they already locked it. This is a defining property of idempotent operations: the second (and third, and fourth) invocation is a no-op at the system level, but still serves a real purpose for the caller—confirmation without consequence.

⸻

### Example 2: Elevator Button (Idempotent Request)

Pressing the elevator button to go to a floor registers a request. Pressing it again doesn’t create additional requests or change the outcome—it simply ensures that the request has been made.

This is another form of idempotency. The system interprets repeated actions as the same intent, not as additional work. The user doesn’t need to track whether they’ve already pressed the button; repeating the action is safe and has no unintended side effects.
 
BTW: pressing an already lit elevator button does not make the elevator go any faster, even though I've seen so many people press it over and over again. They must believe in "ele-acceleration." 

⸻

### Example 3: Classroom Light Switches (Non-Idempotent / Ambiguous)

In a classroom with multiple entrances and multiple light switches, I often don’t know which switch controls which lights. Flipping a switch might turn lights on—or it might turn them off. Pressing the same switch again doesn’t reliably produce the same result; it depends on the current state, which I may not know.

This is not idempotent. The system behaves like a toggle, where each action changes state rather than ensuring a specific outcome. As a result, I have to remember or infer the current state before acting, increasing the chance of mistakes.

⸻

### Bridging Idea

Idempotent systems are designed around achieving a desired state, not transitioning between states. Because of this, they reduce the need for memory and make repeated actions safe.

In this document, the goal is to design software systems that behave more like the car lock or elevator button—and less like the classroom light switches.


| Property | Car Lock | Elevator Button | Light Switch |
|----------|----------|------------------|--------------|
| Requires memory | ❌ No | ❌ No | ✅ Yes |
| Safe to repeat | ✅ Yes | ✅ Yes | ❌ No |
| Outcome predictable | ✅ Yes | ✅ Yes | ❌ No |
| Mental model | Ensure state (“locked”) | Ensure request is registered | Toggle state |
| Repeated action effect | No additional effect | No additional effect | Reverses or changes state |
| Undo available | Not needed | Not needed | Sometimes (flip again) |
| User confidence | High | High | Low |

The light switch appears manageable because mistakes can often be undone by flipping it again. But this only works in simple, local systems. In more complex or distributed systems, actions are often irreversible, delayed, or have side effects that cannot be cleanly undone. In those cases, toggle-style behavior becomes dangerous, and idempotent “ensure state” operations become much more valuable.

In more complex or potentially dangerous situations, systems are often designed with a master control—such as a main power breaker or a water shutoff valve—that can be safely and repeatedly applied to bring the system to a known state. These controls are effectively idempotent: activating them repeatedly does not introduce additional risk, but simply ensures the system remains in that safe state.

---

## Overview

Swift has no first-class support for idempotency as a language or static-analysis concept. Functions that must be safe to call multiple times — event handlers, retry-wrapped network calls, upsert operations — carry that contract only in documentation or team convention. Violations are silent and often expensive.

This document proposes a multi-layer enforcement model for SwiftProjectLint:

1. **Annotation-based declaration** — `/// @lint.effect idempotent` and related doc-comment annotations establish intent, make assumptions reviewable, and give the linter a trigger point.
2. **Static body analysis** — the linter verifies that annotated functions actually call only idempotent operations, using an effect lattice with defined composition rules.
3. **Swift macro generation** — an `@Idempotent` peer macro generates companion test functions, enforcing the contract at runtime in addition to statically.
4. **Type-level safety** — protocols and strong types encode idempotency in the type system, enabling compile-time enforcement at generic boundaries.

Each layer is independently valuable and can be adopted incrementally.

### Start With Two Effects

Most of this document specifies the full model, but most codebases should not start with the full model. The minimal adoption path is two annotations:

- `/// @lint.effect idempotent` — this function is safe to call multiple times.
- `/// @lint.effect non_idempotent` — this function is not.

That pair plus basic call-graph validation catches the bulk of real bugs (retry-context violations, `@effect idempotent` functions calling known-non-idempotent APIs) with no false positives from heuristics and no structural changes to the codebase. The additional tiers — `externally_idempotent`, `transactional_idempotent`, the `@context` annotations, the `@Idempotent` macro, `IdempotencyKey`, protocol-based enforcement — are opt-in expansions for teams that have concrete bugs the two-effect model can't express. Treat the rest of this document as a menu, not a checklist.

---

### Level 1: Annotation (Intent Declaration)

At the first level, the goal is not to prove anything, but to clearly state intent. By annotating a function as idempotent (or not), you’re making an explicit claim about how it is supposed to behave when called multiple times. This shifts idempotency from an implicit assumption—often buried in comments or tribal knowledge—into something visible, reviewable, and enforceable. Think of this level as establishing a shared language: it allows developers, reviewers, and tools to align on what a piece of code is meant to guarantee before worrying about whether that guarantee actually holds.

⸻

### Level 2: Static Analysis (Reasoning About Code)

Once intent is declared, the next step is to reason about whether the code appears to honor it. Static analysis operates purely at compile time, examining function bodies, call graphs, and known effects to detect obvious violations or inconsistencies. It doesn’t try to be perfect—in fact, it can’t be—but it provides valuable early feedback by catching mismatches between declared intent and observable structure. At this level, the system acts like a skeptical reviewer: it asks, “Given what we can see, does this claim of idempotency make sense?”

⸻

### Level 3: Runtime Validation (Behavioral Probing)

Static reasoning has limits, especially when real-world behavior depends on runtime state, external systems, or timing. The third level introduces runtime validation to complement static analysis by observing how code actually behaves when executed. Rather than proving correctness, these checks act as probes—running functions multiple times, under varying conditions, to detect obvious violations of idempotency. This level helps bridge the gap between theory and reality, offering empirical signals that something may be wrong even when static analysis cannot detect it.

⸻

### Level 4: Type System & Composition (Guarantees by Construction)

The final level moves from checking behavior to structuring code so that correct behavior is easier to achieve and maintain. By encoding idempotency (and related properties) into types and abstractions, you enable the compiler and the design itself to enforce constraints through composition. Instead of repeatedly verifying that individual functions behave correctly, you build systems where idempotency naturally emerges from how components are combined. This is the most powerful level, but also the most demanding—it requires careful design of APIs and types so that guarantees are not just asserted or checked, but built into the architecture itself.

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

### Observable Equivalence: What "Same Effect" Means

"Idempotent" is defined throughout this document as "calling twice produces the same effect as calling once." That phrase only has teeth if *effect* and *same* are pinned down.

**Working definition:**

> A function `f` is idempotent with respect to an observer `O` if, for any input `x`, the sequence `f(x); f(x)` leaves `O` in a state indistinguishable from the sequence `f(x)` alone.

Three parameters must be made concrete for any given function:

- **Observable state.** The surface the observer can inspect. For most business logic this is persistent storage (database rows, filesystem, object storage) plus outbound messages (emails, webhooks, queue publishes). It explicitly *excludes* internal trace IDs, debug logs, cache warmth, and wall-clock timestamps in audit rows that are present for forensics rather than semantics.
- **Equivalence relation.** Usually structural equality on the observable surface. Weaker relations are legitimate when documented — e.g. "equal modulo the `updated_at` column," "equal modulo log line ordering." The relation is part of the contract, not a universal constant.
- **Observer scope.** Who is watching. End users and downstream services are in scope; an internal APM agent counting function invocations is not.

The linter does not need to enforce a single global definition of equivalence. It needs each `@lint.effect idempotent` annotation to be *reviewable* against this frame: a reader should be able to ask "what's the observable state, what's the equivalence relation, who's the observer" and get a defensible answer. When the answer is non-obvious, the annotation should carry a `reason:` clause.

For the externally-idempotent tier, the observer is typically the external system's deduplication layer, and the equivalence relation is "the provider treats these calls as the same operation" — a claim grounded in the provider's contract, not in the function body.

### Partial Failure and the Retry Contract

Idempotency is frequently discussed as a property of successful calls — if `f(x); f(x)` both complete, they produce the same effect as `f(x)` alone. In production, the execution paths that matter most are the ones that *don't* complete. A function that begins, mutates external state, then throws leaves the observer in an intermediate state the retry has to reconcile.

The canonical failure mode:

```swift
// ❌ Each individual call is idempotent in isolation.
//    The composite is not — partial completion leaves state inconsistent.
func processPayment(id: PaymentID) async throws {
    try await chargeCard(id)               // succeeds, card is charged
    try await updateOrderStatus(id, .paid) // throws — network blip
}

// Retry re-enters. chargeCard with the same key is deduplicated server-side.
// updateOrderStatus retries and succeeds. OK — but only because chargeCard
// is externally idempotent on the key. If chargeCard were non-idempotent,
// the retry would double-charge.
```

This is not a theoretical edge case — it is the failure mode that motivates idempotency in most real systems. The proposal must therefore distinguish two contracts:

- **Unconditional idempotency**: the function is idempotent on *every* execution path, including paths that throw partway through. The observable state after any prefix of the function's execution is either the pre-call state or the post-call state, never an intermediate state that makes retry unsafe.
- **Atomic idempotency**: the function is idempotent *only* when its side effects commit atomically — typically because they are wrapped in a database transaction, a filesystem rename, or a single-message queue publish. If the atomic boundary is absent or broken, the function degrades to `non_idempotent`.

Atomic idempotency is introduced as a first-class effect tier below. Compensating actions (rolling back `processedIDs.insert(id)` in the actor reentrancy example) are the mechanism teams reach for when atomicity is not available — they should be documented with `@lint.effect idempotent reason: "compensates on throw"` so the claim is reviewable.

The enforcement rule is: every `@lint.effect idempotent` declaration is read as a claim that holds on *every* execution path through the function, including early-throw paths. A function that is idempotent only on the happy path must be declared `@lint.effect transactional_idempotent` (with an enforced transaction boundary) or `@lint.effect non_idempotent` (with a compensating-action story in prose).

---

## Formalized Effect Lattice

A strict ordering defines how effects compose and conflict:

```
pure < idempotent < { transactional_idempotent, externallyIdempotent } < non_idempotent
                                                                unknown (incomparable)
```

Where `unknown` is incomparable to `non_idempotent`; in enforcement, it is treated conservatively as `non_idempotent`. `transactional_idempotent` and `externallyIdempotent` sit at the same tier — both are *conditionally* idempotent, depending on an external mechanism (a transaction boundary or a deduplication key, respectively). Neither is strictly stronger than the other; they address different classes of non-idempotent operation.

`externallyIdempotent` represents operations that are made safe to retry via an external mechanism (idempotency keys, deduplication tables), rather than intrinsic function body properties. See the Idempotency Keys section for details.

`transactional_idempotent` represents operations whose side effects are individually non-idempotent but commit atomically — a single database transaction, an atomic rename, a single message publish. The retry contract holds because the observable state after any prefix of execution is either the pre-call state or the post-call state, never an intermediate one. See "Transactions as a Composition Boundary" below.

**Composition rules** (for a function calling multiple callees):

| Callees include | Caller's inferred effect |
|---|---|
| pure only | pure |
| idempotent only | idempotent |
| any non_idempotent (outside a transaction) | non_idempotent |
| multiple non_idempotent inside a single transaction | transactional_idempotent |
| any externally_idempotent | externally_idempotent (if sole source) or non_idempotent (if mixed outside a txn) |
| any unknown | unknown (warn; treat as non_idempotent in strict mode) |
| idempotent + unknown | unknown |

**Conflict detection** (declared annotation vs. inferred effect):

| Declared | Inferred | Lint Action |
|---|---|---|
| `idempotent` | `idempotent` | ✅ OK |
| `idempotent` | `non_idempotent` | ❌ Error |
| `idempotent` | `unknown` | ⚠️ Warning |
| `idempotent` | `transactional_idempotent` | ❌ Error — weaker guarantee than declared |
| `idempotent` | `externallyIdempotent` | ❌ Error — declared stronger than body supports |
| `transactional_idempotent` | `transactional_idempotent` | ✅ OK |
| `transactional_idempotent` | `non_idempotent` | ❌ Error — no transaction boundary detected |
| `transactional_idempotent` | `idempotent` | ⚠️ Warning — stronger annotation applies |
| `non_idempotent` | `idempotent` | ⚠️ Warning (over-declared) |
| `non_idempotent` | `non_idempotent` | ✅ OK |
| `externallyIdempotent` | `non_idempotent` | ✅ OK — key is the mechanism |
| `externallyIdempotent` | `idempotent` | ⚠️ Warning — simpler annotation applies |
| (none) | `non_idempotent` | ℹ️ Suggestion to annotate |

### Transactions as a Composition Boundary

A sequence of non-idempotent operations that commits atomically inside a single transaction is idempotent with respect to external observers — after any retry, the observable state is either "transaction never happened" or "transaction committed exactly once." The lattice recognizes this composite as `transactional_idempotent`.

```swift
/// @lint.effect transactional_idempotent
/// @lint.txn_boundary db.transaction
/// Each operation is non-idempotent in isolation; the transaction makes the
/// composite safe to retry.
func transferFunds(from: AccountID, to: AccountID, amount: Money) async throws {
    try await db.transaction { tx in
        try await tx.debit(from, amount)   // non_idempotent in isolation
        try await tx.credit(to, amount)    // non_idempotent in isolation
        try await tx.log(.transfer(from, to, amount))  // non_idempotent in isolation
    }
}
```

**Enforcement — body analysis for `@lint.effect transactional_idempotent`:**

1. The function must contain exactly one transaction scope (by default: a call to a known transaction opener — `db.transaction`, `db.withTransaction`, `Connection.transaction`, etc.; configurable via project settings).
2. Every non-idempotent side effect must occur *inside* that transaction scope.
3. A non-idempotent call observed outside the transaction scope demotes the inferred effect to `non_idempotent` and triggers `transactionalIdempotencyViolation`.
4. `@lint.txn_boundary <identifier>` optionally names the transaction opener, for codebases that wrap the driver with a domain-specific helper (`ledger.withTransaction`, `UnitOfWork.run`).

**Limitation.** The linter cannot verify that the *database itself* provides the atomicity guarantee — this is an assumption about the driver and the storage engine, recorded via `@lint.assume db.transaction is atomic` or (more commonly) treated as a project-wide baseline. A transactional composite over a non-transactional store (e.g., two separate HTTP calls wrapped in a function named `transaction`) is outside the linter's reach and belongs in review.

### Branch-Sensitive Effect Inference

A function whose branches have different effects must be reconciled — the function's inferred effect is the *join* of its branches under the lattice, which in practice is almost always the weaker of the two:

```swift
// Branches disagree: one is idempotent, the other is not.
// Inferred effect: non_idempotent (the weaker join).
func save(_ user: User) async throws {
    if featureFlag.isOn(.upsert) {
        try await db.upsert(user)   // idempotent
    } else {
        try await db.insert(user)   // non_idempotent
    }
}
```

Silently collapsing this to `non_idempotent` surprises authors. The linter should emit a distinct diagnostic — `effectVariesByBranch` — that surfaces the disagreement and names the branches. This lets the author either reconcile the branches (make both idempotent), restructure the function, or explicitly annotate the weaker of the two.

**Join rules** (pairwise; extend to N branches by reduction):

| Branch A | Branch B | Join |
|---|---|---|
| pure | idempotent | idempotent |
| idempotent | idempotent | idempotent |
| idempotent | transactional_idempotent | transactional_idempotent (requires both branches inside the same transaction, else demote) |
| idempotent | externally_idempotent | externally_idempotent |
| idempotent | non_idempotent | non_idempotent (emit `effectVariesByBranch`) |
| transactional_idempotent | non_idempotent | non_idempotent (emit `effectVariesByBranch`) |
| externally_idempotent | non_idempotent | non_idempotent (emit `effectVariesByBranch`) |
| any | unknown | unknown (emit `effectVariesByBranch` if non-unknown branch is not unknown) |

The diagnostic is a warning by default and an error when the function is declared `@lint.effect idempotent` but has non-idempotent branches — the declared contract does not hold uniformly.

**Rule identifier:** `effectVariesByBranch`.

---

## Annotation Grammar

### Doc-Comment Annotations

Doc-comment annotations serve as the primary declaration mechanism. They are additive — no structural changes to the codebase are required — and they document intent independently of any tooling.

The `@lint.` prefix avoids collision with DocC conventions (`@param`, `@returns`, `@throws`) and makes tool-specific annotations visually distinct:

```swift
/// @lint.effect idempotent
/// @lint.effect idempotent(by: requestID)
/// @lint.effect non_idempotent
/// @lint.effect externally_idempotent reason: "Stripe deduplicates on idempotency-key header"
/// @lint.context replayable
/// @lint.requires idempotency_key
/// @lint.assume db.upsert is idempotent
/// @lint.unsafe reason: "provider guarantees deduplication"
```

### Scoped Idempotency: `idempotent(by: <parameter>)`

Some operations are idempotent only when repeated with the *same logical key*. Two calls with the same `requestID` are safe to collapse; two calls with different `requestID`s are two distinct operations, each of which happens exactly once.

```swift
/// @lint.effect idempotent(by: requestID)
/// Repeated calls with the same requestID produce a single logical effect.
/// Different requestIDs are independent operations.
func enqueueJob(requestID: JobID, payload: Data) async throws { ... }
```

**Enforcement implications:**

- The named parameter must exist on the function signature. Missing parameter → `scopedIdempotencyParameterNotFound`.
- At retry-context call sites, the scoping parameter must be stable across iterations (same rules as `IdempotencyKey`: input-derived, defined outside the retry scope, not freshly generated per attempt). Violations reuse `idempotencyKeyGeneratedInRetry`.
- For callers, `idempotent(by:)` is equivalent to `idempotent` — they may invoke it freely from `@context retry_safe` and `@context replayable` bodies, because the caller is expected to hold the key stable.

Scoped idempotency is the common case for most real systems; the unscoped `@lint.effect idempotent` is the degenerate form where the scope is "all calls to this function."

### `@lint.assume` — Declared, Auditable Assumptions

Much of the static analysis rests on claims the linter cannot verify: that a third-party library method is idempotent, that a database driver's `upsert` really is an upsert, that a specific HTTP endpoint deduplicates server-side. Rather than burying these claims in `@lint.unsafe reason:` escape hatches, they can be declared explicitly:

```swift
/// @lint.assume db.upsert is idempotent
/// @lint.assume stripe.PaymentIntents.create is externally_idempotent reason: "idempotency-key header"
/// @lint.assume Logger.log is pure
```

An assumption is a first-class annotation that:

- Binds a symbol (method, free function, type) to an asserted effect.
- Is *named and locatable* — the linter can list every assumption in the codebase as a single report, making them reviewable in bulk.
- Is *lintable itself* — a future rule can flag assumptions that reference symbols no longer present, are duplicated across files, or contradict each other.
- Is *scoped* — assumptions declared at file scope apply only within that file; assumptions declared in a top-level `Assumptions.swift` (by convention) apply project-wide.

Assumptions replace `@lint.unsafe` for the common case of "I know this external thing is idempotent." `@lint.unsafe` remains the escape hatch for cases where even an assumption would be too strong a claim to formalize.

Phase 1 treats assumptions as documentation only — they populate the symbol table without enforcement. Phase 2+ uses them during propagation: an assumed-idempotent callee contributes `idempotent` rather than `unknown` to the caller's inferred effect.

**Why doc comments are the right default:**

- They tell reviewers "this function is expected to be safe to retry — be careful what you add"
- They make assumptions explicit during code review
- They force the author to commit to a semantic contract, rather than leaving it implicit
- They work incrementally: a codebase can adopt annotations gradually
- They mirror established practice: Swift's own `/// - Parameter`, Javadoc's `@throws`, Python docstrings — all valuable without compiler enforcement

Even when the linter can only verify 50% of violations, the annotations document the *intent* the linter checks against. That has independent value.

### Effect Annotations on Closure Parameters

A generic retry wrapper cannot say anything useful about its callees without a mechanism to declare what it expects of its body argument. Extending the annotation grammar to closure parameter types closes this gap:

```swift
/// @lint.effect non_idempotent
/// @lint.param body requires idempotent
/// Retries `body` on transient failure. Body must be idempotent.
func withRetry<T>(
    maxAttempts: Int = 3,
    body: @escaping () async throws -> T
) async throws -> T { ... }
```

**Enforcement:**

- At every call site of `withRetry`, the linter resolves the argument passed for `body` and checks its effect against the declared requirement.
- A literal closure is analyzed in-place using the same rules as a named function body.
- A named function reference (`withRetry(body: sendEmail)`) is looked up in the effect symbol table.
- A closure whose effect cannot be determined (captures an `unknown` callee, or is passed through multiple indirections) produces a warning rather than an error.

**Shorthand form** for the common case where the retry wrapper is the body's only user:

```swift
/// @lint.effect retry_safe_wrapper
func withRetry<T>(maxAttempts: Int = 3, body: @escaping () async throws -> T) async throws -> T
```

`@lint.effect retry_safe_wrapper` is sugar for `@lint.effect non_idempotent` + `@lint.param body requires idempotent_or_externally_idempotent`, matching the most common pattern exactly.

**Rule identifiers:**

```swift
case closureArgumentFailsEffectRequirement   // body argument does not meet declared @lint.param requirement
case retryWrapperMissingBodyRequirement      // @lint.effect retry_safe_wrapper without declared body effect
```

### Swift Macros as a Second Layer

Swift 5.9+ macros (`@attached(peer)`) can go further — surviving refactoring, enabling autocomplete, generating companion tests. Macros are a *second layer* that builds on the annotation contract, not a replacement for it.

| Mechanism | Audience | Value |
|---|---|---|
| `/// @lint.effect idempotent` | Human reviewers + linter | Documents intent; enables partial verification |
| `@Idempotent` macro | Compiler + test generator | Enforcement; automatic test generation |
| Both together | Everyone | Full spectrum |

The annotation grammar is the *lingua franca* that both humans and tools read. Macros can generate or verify the same annotations automatically.

### Suppression Grammar

`@lint.unsafe` is the right escape hatch for *semantic* suppressions — cases where the author is making a claim about external behavior that the linter cannot verify. It is the wrong mechanism for *mechanical* suppressions: a known-false-positive on a single line, a file that has not been migrated yet, a whole module excluded from a new rule. Teams that conflate these two uses end up with `@lint.unsafe reason: "temp"` scattered through the codebase, which poisons the `@lint.assume` audit trail.

A separate suppression grammar, modeled on SwiftLint's conventions, handles the mechanical case:

```swift
// Single line
// swift-idempotency:disable-next-line nonIdempotentInRetryContext
try await chargeCard(amount: 100)

// Block
// swift-idempotency:disable nonIdempotentInRetryContext
for attempt in 1...maxRetries {
    try await legacyNonIdempotentCall()
}
// swift-idempotency:enable nonIdempotentInRetryContext

// File scope — first line of the file
// swift-idempotency:disable-file actorReentrancyIdempotencyHazard
```

**Rules:**

- Suppressions name the specific rule identifier. Blanket `// swift-idempotency:disable` (no identifier) is not supported — it is the `catch (...)` of lint and makes the codebase unreviewable.
- A suppression with no matching violation in its scope is itself a diagnostic (`unusedSuppression`). This keeps suppressions from outliving the problem they were hiding.
- Project-level configuration (`.swift-idempotency.yml`) supports per-directory rule disables for incremental adoption — typically used to exclude a legacy module from a new rule while the migration is in flight.

**Rule identifiers:**

```swift
case unusedSuppression              // suppression directive with no violation in scope
case malformedSuppressionDirective  // unparseable // swift-idempotency: directive
```

The distinction to communicate in docs: `@lint.unsafe reason:` is a claim about *semantics* ("this really is idempotent, trust me"); `// swift-idempotency:disable-next-line` is a claim about *the linter* ("this rule is wrong here"). The two have different review implications, so they get different syntax.

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

/// @context dedup_guarded
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

### `@context dedup_guarded` — Assertion with Mechanism

This is the most nuanced context and the one most easily confused with `@effect idempotent`. The distinction matters:

- **`@effect idempotent`**: the linter *verifies* the function body is idempotent through analysis. The function must pass the body check.
- **`@context dedup_guarded`**: the function *asserts* it produces idempotent outcomes through a mechanism the linter cannot fully verify (idempotency keys, a deduplication table, a transactional guard). Body check is suppressed; mechanism check replaces it.

```swift
// ❌ Wrong annotation — linter flags chargeCard as non_idempotent in the body
/// @effect idempotent
func processPayment(id: PaymentID) async throws {
    try await chargeCard(amount: payment.amount, idempotencyKey: .init(from: id))
    try await updateOrderStatus(id, status: .paid)
}

// ✅ Correct annotation — asserts idempotency is handled via the key mechanism
/// @context dedup_guarded
func processPayment(id: PaymentID) async throws {
    try await chargeCard(amount: payment.amount, idempotencyKey: .init(from: id))
    try await updateOrderStatus(id, status: .paid)
}
```

Because the body check is suppressed, the linter instead requires *evidence of a mechanism*:

1. **Key mechanism**: the function accepts an `IdempotencyKey` parameter, or constructs one from its inputs before any non-idempotent calls. ✅
2. **Deduplication guard**: the function checks a processed-ID set or similar guard before non-idempotent work. ✅
3. **Explicit override**: `@lint.unsafe reason: "..."` suppresses the mechanism requirement with a documented justification. ✅ with warning
4. **No visible mechanism**: ❌ — annotation is unverifiable; emit `dedupGuardedWithoutMechanism`

From the caller's perspective, `@context dedup_guarded` behaves like `@effect idempotent`: the function is safe to call from retry contexts.

### Context Interaction Matrix

| Caller's context | Callee is `@context once` | Callee is `@context retry_safe` / `replayable` | Callee is `@context dedup_guarded` |
|---|---|---|---|
| `retry_safe` / `replayable` | ❌ Would call once-function multiple times | ✅ | ✅ |
| `once` | ✅ Both run once | ✅ | ✅ |
| `dedup_guarded` | ❌ Caller may run multiple times; violates callee's once contract | ✅ | ✅ |
| (no context) | ✅ No retry implied | ✅ | ✅ |

### Rule Identifiers (Context)

```swift
case onceOperationInRetryContext      // @context once function called inside retry_safe / replayable body
case onceOperationInRetryLoop         // @context once function called inside a detected retry loop
case dedupGuardedWithoutMechanism // @context dedup_guarded with no visible key or guard mechanism
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

### Effect Annotations on Protocol Requirements

The most powerful composition of the protocol layer and the annotation layer is declaring an effect on a protocol method *requirement*. The contract then becomes a covariant obligation on every conformer — every witness must supply a body that satisfies at least the declared effect.

```swift
public protocol Repository {
    associatedtype Entity: Identifiable

    /// @lint.effect idempotent
    func upsert(_ entity: Entity) async throws

    /// @lint.effect non_idempotent
    func insert(_ entity: Entity) async throws

    /// @lint.effect externally_idempotent reason: "caller supplies key"
    func enqueue(_ entity: Entity, key: IdempotencyKey) async throws
}
```

**Enforcement.** When a type conforms to `Repository`, the linter checks every witness against the corresponding requirement's declared effect:

- Witness's declared annotation stronger than or equal to requirement: ✅
- Witness's declared annotation weaker than requirement: ❌ `protocolWitnessWeakerEffect`
- Witness has no annotation: inferred effect must meet the requirement, else ⚠️ or ❌ depending on strict mode
- Witness marked `@lint.unsafe`: ⚠️ — conformance by assertion, documented

This is the cleanest way to encode "every `Repository` implementation has an idempotent `upsert`" as a *machine-checkable* constraint, and it plays well with the existing `IdempotentOperation` marker protocol — the marker enforces the constraint at the type level, the requirement annotation enforces it at the method level, and the two together cover both the call-graph and the conformance surface.

**Generic callers** can then declare the effect they need from the repository method, and the linter can reason about it without inspecting the concrete type:

```swift
/// @context retry_safe
func syncRemoteState<R: Repository>(_ repo: R, entities: [R.Entity]) async throws {
    for entity in entities {
        try await repo.upsert(entity)  // ✅ — requirement declares idempotent
        try await repo.insert(entity)  // ❌ — requirement declares non_idempotent
    }
}
```

**Rule identifiers:**

```swift
case protocolWitnessWeakerEffect     // witness's effect is weaker than the requirement
case protocolRequirementUnannotated  // protocol method has no @lint.effect — suggestion in strict mode
```

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

**Pattern 8: `for try await` over an AsyncSequence that may emit duplicates**

```swift
for try await event in eventStream {
    try await chargeCard(amount: event.amount)  // ❌ if eventStream has at-least-once semantics
}
```

An `AsyncSequence` is itself a replayable context whenever its producer has at-least-once semantics — Kafka consumers, Kinesis shards, CloudWatch Logs subscribers, SwiftNIO channel reads during reconnection. The sequence type alone doesn't tell the linter whether repeats are possible; the consumption site should be annotated when relevant:

```swift
/// @context replayable reason: "Kinesis may re-deliver on shard rebalance"
for try await event in kinesisShard.events {
    try await processEvent(event)  // must be @lint.effect idempotent
}
```

Without an annotation the linter cannot know the semantics of an arbitrary `AsyncSequence`, so the default is no diagnostic — this is an opt-in replayable context rather than an inferred one.

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

## End-to-End Worked Example: Lambda SQS Handler

To anchor the abstract framework, consider a realistic Lambda function that consumes SQS messages and processes orders. SQS delivers at-least-once, so every handler runs in an objectively replayable context.

### Starting Point: Unannotated

```swift
struct OrderHandler: EventLoopLambdaHandler {
    typealias Event = SQSEvent
    typealias Output = Void

    let db: OrderDatabase
    let stripe: StripeClient
    let mailer: MailerClient

    func handle(_ event: SQSEvent, context: LambdaContext) async throws {
        for record in event.records {
            let order = try JSONDecoder().decode(Order.self, from: record.body)

            try await db.insert(order)
            let receipt = try await stripe.charge(
                amount: order.amount,
                customerID: order.customerID
            )
            try await mailer.send(
                to: order.email,
                subject: "Order confirmed",
                body: "Receipt: \(receipt.id)"
            )
            try await db.update(order.id, status: .confirmed)
        }
    }
}
```

Four distinct idempotency bugs, all live in production:

1. `db.insert(order)` — a duplicate SQS delivery inserts the order a second time.
2. `stripe.charge` without an idempotency key — duplicate charge on retry.
3. `mailer.send` without a deduplication key — customer receives two confirmation emails.
4. The composite is non-atomic — if any of the four steps throws after earlier steps succeed, retry replays the successful ones.

### Phase 1: Declare Context and Intent

The first pass adds annotations without any code changes. The annotations make the contract reviewable and turn on the linter.

```swift
/// @context replayable
/// SQS provides at-least-once delivery. Handler must be idempotent.
func handle(_ event: SQSEvent, context: LambdaContext) async throws {
    for record in event.records {
        let order = try JSONDecoder().decode(Order.self, from: record.body)

        try await db.insert(order)           // ❌ nonIdempotentInReplayableContext
        let receipt = try await stripe.charge(...)  // ❌ nonIdempotentInReplayableContext
        try await mailer.send(...)           // ❌ nonIdempotentInReplayableContext
        try await db.update(order.id, ...)   // ❌ nonIdempotentInReplayableContext
    }
}
```

Four lint violations. The team now has a written contract and a failing build — which is the whole point of Phase 1.

### Phase 2: Fix the Individual Calls

```swift
public protocol OrderDatabase {
    /// @lint.effect idempotent
    func upsert(_ order: Order) async throws

    /// @lint.effect idempotent(by: id)
    func setStatus(_ id: OrderID, _ status: OrderStatus) async throws
}

extension StripeClient {
    /// @lint.effect externally_idempotent reason: "Stripe dedupes on idempotency-key header"
    /// @lint.requires idempotency_key
    func charge(
        amount: Money,
        customerID: CustomerID,
        idempotencyKey: IdempotencyKey
    ) async throws -> Receipt { ... }
}

extension MailerClient {
    /// @lint.effect externally_idempotent reason: "dedupe by message ID, 24h window"
    /// @lint.requires idempotency_key
    func send(
        to: EmailAddress,
        subject: String,
        body: String,
        deduplicationID: IdempotencyKey
    ) async throws { ... }
}
```

Each primitive now carries an accurate effect annotation. `stripe.charge` and `mailer.send` require idempotency keys. The handler is rewritten to supply them:

```swift
/// @context replayable
func handle(_ event: SQSEvent, context: LambdaContext) async throws {
    for record in event.records {
        let order = try JSONDecoder().decode(Order.self, from: record.body)
        let key = IdempotencyKey(from: order)  // derived from order fields — stable across retries

        try await db.upsert(order)                          // ✅ idempotent
        let receipt = try await stripe.charge(              // ✅ externally_idempotent
            amount: order.amount,
            customerID: order.customerID,
            idempotencyKey: key
        )
        try await mailer.send(                              // ✅ externally_idempotent
            to: order.email,
            subject: "Order confirmed",
            body: "Receipt: \(receipt.id)",
            deduplicationID: key
        )
        try await db.setStatus(order.id, .confirmed)        // ✅ idempotent(by: id)
    }
}
```

The linter is silent. Every call site is reviewable against a named effect. But the composite still has the partial-failure bug: if `mailer.send` throws after `stripe.charge` succeeds, retry replays the charge (safely, via the key) and re-attempts the email (also safely) — but the observable state transiently includes "charge succeeded, no email sent, order not marked confirmed."

### Phase 3: Introduce the Atomic Boundary

Some of this is tolerable (the transient state resolves on retry). The remaining concern is the unbounded fan-out if the *handler itself* keeps failing: a message that poisons the queue replays indefinitely. The canonical fix is a processed-message guard keyed on the SQS message ID, which makes the handler `@context dedup_guarded`:

```swift
/// @context dedup_guarded
/// Mechanism: processedMessageIDs set (see body) dedupes on SQS message ID.
func handle(_ event: SQSEvent, context: LambdaContext) async throws {
    for record in event.records {
        // Claim the slot before any side-effecting work — actor reentrancy rule.
        guard try await db.claimMessageID(record.messageID) else {
            context.logger.info("Skipping already-processed message \(record.messageID)")
            continue
        }

        do {
            try await processOrder(record)
        } catch {
            try await db.releaseMessageID(record.messageID)
            throw error
        }
    }
}

/// @lint.effect idempotent
private func processOrder(_ record: SQSRecord) async throws {
    let order = try JSONDecoder().decode(Order.self, from: record.body)
    let key = IdempotencyKey(from: order)
    try await db.upsert(order)
    _ = try await stripe.charge(amount: order.amount, customerID: order.customerID, idempotencyKey: key)
    try await mailer.send(to: order.email, subject: "...", body: "...", deduplicationID: key)
    try await db.setStatus(order.id, .confirmed)
}
```

The linter now verifies two distinct contracts:

1. `handle` is `@context dedup_guarded` — the body check is suppressed, but the linter verifies a deduplication guard exists (`claimMessageID` before any non-idempotent call).
2. `processOrder` is `@lint.effect idempotent` — the body check runs, and every callee meets the contract.

### What the Linter Catches Going Forward

Six months later, a junior engineer adds a metrics call:

```swift
private func processOrder(_ record: SQSRecord) async throws {
    metrics.increment("orders.processed")  // ❌ idempotencyViolation
    // ...
}
```

`metrics.increment` is `@lint.effect non_idempotent` (each call increments the counter). The linter fires immediately in review. The engineer either moves the increment into the `@context dedup_guarded` body (where double-counting is acceptable because `claimMessageID` dedupes) or switches to an idempotent `metrics.gauge` pattern.

This is the loop the proposal is designed to enable: declare the contract once, catch regressions automatically on every change.

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

**Performance budget.** Target end-to-end analysis times, measured on a developer laptop (Apple Silicon, SSD):

| Project size | Phase 1 (annotation parse) | Phase 2 (heuristic inference) | Phase 3 (call-graph propagation) |
|---|---|---|---|
| 100 files, ~20k LoC | < 500 ms | < 2 s | < 5 s |
| 1,000 files, ~200k LoC | < 5 s | < 20 s | < 60 s |
| 10,000 files, ~2M LoC | < 60 s | < 4 min | < 15 min |

Phase 3 must support *incremental* analysis — re-running on a changed file should reuse the prior call graph and recompute only the affected subgraph. Without incremental support, the cross-file analysis is a CI-only check; with it, it's editor-friendly.

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

## Edge Cases and Implementation Notes

A handful of secondary concerns that are too small to warrant dedicated sections but should be specified before implementation.

**Empty and trivial function bodies.** A function with an empty body, or a body containing only `return`, is trivially idempotent — it has no observable effect. The body analysis should short-circuit to `pure` in this case rather than `unknown`. A function whose body consists only of pure-declared callees is similarly `pure`. This matters for initializer stubs, no-op protocol witnesses, and generated code — the default `unknown` would flood such codebases with warnings in strict mode.

**Annotation grammar versioning.** The `@lint.effect` grammar will evolve. A new tier (beyond `transactional_idempotent`) or a new annotation (some future `@lint.effect at_most_once`) must not silently change the interpretation of existing annotations. The proposal adopts a project-level version pin via configuration file:

```yaml
# .swift-idempotency.yml
grammar_version: 1
```

Unrecognized annotations against a pinned grammar version are a warning (`unknownAnnotationVersion`), not an error — a newer linter reading an older project should be lenient. A newer annotation used against a pinned older grammar is flagged so teams see when they're reaching for a feature that isn't available under their current pin.

**Generated code.** Code produced by Sourcery, Swift macros (including `@Idempotent` itself), or protobuf code generators typically has no hand-written doc comments. Two mechanisms support annotation on generated code:

1. *Generator-side annotation injection* — the generator's template emits `/// @lint.effect` comments based on the source specification. This is the preferred approach for team-owned generators.
2. *Symbol-level project annotation* — an `Assumptions.swift`-style file declares effects for generated symbols that cannot be modified at generation time. This is the fallback for third-party generated code.

Generated files may be excluded wholesale via `// swift-idempotency:disable-file` or via project configuration (`exclude_paths: [Generated/**]`), at the cost of losing cross-file propagation into those files.

**Strict mode default for unannotated functions.** In non-strict mode, an unannotated function is treated as `unknown` — no diagnostic unless it participates in a conflict elsewhere. In strict mode, all functions with observable side effects (detected heuristically in Phase 2) must carry an annotation; missing annotations are a warning. The recommended migration path is: enable the linter in non-strict mode, get to green, annotate progressively, flip strict mode on once coverage is acceptable. Per-directory strict-mode configuration supports the common case of "strict in the new domain module, lenient in legacy code."

**Rule identifiers introduced in this section:**

```swift
case unknownAnnotationVersion  // annotation not defined in the pinned grammar version
```

---

## Open Issues

These questions are unresolved and should be revisited before implementation of the relevant rules begins.

### OI-1: Scope of `actorReentrancyIdempotencyHazard`

The rule is currently specified to fire inside actor method bodies. The same check-suspend-act bug is possible in any `@MainActor`-isolated class or in any context where a suspension point separates a read-guard from a write. Should the rule apply only to `ActorDeclSyntax` bodies, or also to `@MainActor` class methods and other explicitly isolated contexts?

Expanding scope reduces missed detections but increases false positive risk on code that isn't actually using the guard as an idempotency mechanism.

### OI-2: Depth of `@context once` call-site analysis

Phase 1 of `@context once` enforcement would detect direct call sites: a `@context once`-annotated function appearing inside a for-loop, a known retry wrapper, or a `@context retry_safe` / `replayable` function body — visible in the AST at parse time.

Phase 2 would add transitive propagation: if `A` calls `B` and `B` calls a `@context once` function, and `A` is in a retry context, the violation is still real but requires a call graph rather than single-pass AST traversal.

The question is whether Phase 1 alone delivers enough value to ship, or whether the gap (violations that only appear transitively) is large enough that Phase 2 should be a prerequisite. This depends on how `@context once` annotations are actually used in practice — a question that can only be answered against a real codebase.

---

## Q&A: Addressing Common Critiques

These questions reflect critiques raised during review. Most concern design decisions that are already resolved in the document body; they are answered here to prevent re-litigation.

---

**Q: Isn't binary classification (idempotent / not) too limiting for real systems? What about idempotency per key, or within a time window?**

A: The effect lattice is not binary. It has five positions: `pure`, `idempotent`, `externallyIdempotent`, `non_idempotent`, and `unknown`. Scoped idempotency (`idempotent(by: requestID)`) is part of the annotation grammar and enforces that the scoping parameter is stable across retry iterations. Key-based idempotency is separately modeled as `externallyIdempotent`, with its own annotation (`/// @lint.effect externally_idempotent reason: "..."`) and enforcement rules that differ from intrinsic `idempotent`. Time-windowed or conditionally idempotent operations remain a gap — they fall under `unknown` with a `@lint.assume` or `@lint.unsafe reason:` escape hatch.

---

**Q: Static analysis will always hit a ceiling — the linter can't know about database constraints, external API guarantees, etc.**

A: Correct, and the design accounts for this explicitly. The static body check is one layer of four. For operations where the idempotency guarantee lives outside the function body, `@context dedup_guarded` suppresses the body check and replaces it with a mechanism check (presence of an `IdempotencyKey` parameter, a deduplication guard, or an explicit `@lint.unsafe reason:`). `@lint.assume db.upsert_is_idempotent`-style declarations are a possible future extension for annotating third-party boundaries, but are not in Phase 1. The point of the static layer is not complete verification — it's catching violations that *are* locally visible, which is a significant subset of real bugs.

---

**Q: Macro-generated tests aren't strong enough — they don't catch race conditions or distributed retries.**

A: Agreed, and the document says so explicitly in the Tiered Generation Strategy section: "the fixed-input double-call pattern only tests one point in the input space." The macro tier is positioned as a heuristic that catches the simplest class of idempotency violations (a function that returns a different value on the second call, or a method whose captured state differs after repeated calls). It is not a proof of idempotency. The value proposition is: *zero-cost test scaffolding that catches obvious violations and makes the intent reviewable*, not exhaustive verification. Concurrency and distributed-system testing require purpose-built harnesses that are out of scope for a peer macro.

---

**Q: The type-level modeling is underdeveloped — shouldn't protocols be a more central abstraction?**

A: The document covers three protocol patterns (marker, operation object, effect-tagged wrapper), conditional conformance, the `@unchecked` escape hatch, and an explicit trade-off table comparing protocols to doc-comment annotations on five dimensions. The conclusion is that both are needed: protocols for new code structured around operation objects where compile-time generic constraints are worth the architectural buy-in; annotations for existing APIs and free functions where structural change is not feasible. Making protocols the *core* abstraction would require architectural restructuring of existing codebases, which contradicts the incremental adoption requirement. The annotation layer is the lingua franca; the protocol layer is an opt-in for code that can afford the structure.

---

**Q: Concurrency integration is missing.**

A: The Swift Concurrency Interactions section covers: actors don't imply idempotency; actor reentrancy breaks check-then-act patterns (including a detectable rule and fix pattern); four additional async retry patterns (`Task { }` in a loop, `withThrowingTaskGroup`, recursive async retry, and SwiftUI `.task {}`); and how `effectSpecifiers` propagate into generated macro test peers. The rule `actorReentrancyIdempotencyHazard` is the most original contribution in the concurrency section — it is both detectable with SwiftSyntax and absent from existing linting tools.

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

---

## Related Work

This proposal sits in a crowded field of effect systems, purity annotations, and retry framework conventions. A short survey situates the design against prior art and clarifies what is and isn't novel.

**Koka (Microsoft Research)** formalizes effects as a first-class part of the type system. A function's type includes its effect row — `io`, `exn`, `div`, user-defined — and the compiler verifies effect composition. Koka is the closest academic ancestor of the effect lattice proposed here. The trade-off is stark: Koka's system is total and provable at the cost of requiring the language itself to support it. SwiftProjectLint cannot change Swift's type system, so this proposal re-uses Koka's intuition (effects as a lattice, composition rules, conservative handling of unknown) in a layered form compatible with an existing language.

**Java's `@Idempotent` annotations** exist in several ecosystems — Spring, MicroProfile Fault Tolerance, Resilience4j, JAX-RS. Most are *runtime* annotations: they configure retry middleware rather than feed a static checker. Spring's `@Retryable` marks a method for the retry infrastructure; Resilience4j's `@Retry` does the same. None of these verify that the method body is actually idempotent. The Swift proposal's contribution is treating the annotation as a *verifiable claim* rather than a *runtime configuration directive*.

**Rust's effect discussion** centers on `const fn` (compile-time-evaluable functions) and `unsafe fn` (functions with memory-safety preconditions). Both are properties the compiler enforces, and both are explicit about the escape hatch (`const fn` with runtime-only calls is rejected; `unsafe` blocks are explicit and reviewable). The Rust community has repeatedly discussed effect systems for purity, async context, and "no-panic" — none have shipped. The lesson the proposal takes: explicit effect declarations are more socially durable than inferred effects, even when inference is technically possible.

**Haskell's IO monad** is the canonical example of effect tracking. Every side-effecting computation has type `IO a`; the type system prevents pure code from calling into effectful code without acknowledgment. The trade-off is the same as Koka's — total correctness at the cost of structural demands on the language. Haskell's experience also shows the limit: `IO` says "there is a side effect," not "this side effect is idempotent." Finer-grained distinctions (e.g., `IO` vs. `ReaderT` vs. specific effect type classes) require additional structure. This is why the lattice in this proposal has five positions rather than a binary pure/impure split.

**SwiftLint's custom rules** are the closest existing tooling in the Swift ecosystem. They are pattern-based (regex, syntax matches) rather than effect-based — a SwiftLint rule can flag "any call to `UUID()` inside a function named `create*`" but cannot reason about call graphs or composition. This proposal is deliberately a layer above what SwiftLint can express, which is why it's proposed as part of SwiftProjectLint rather than as SwiftLint rules.

**Akka's `At-Least-Once Delivery`** and **Kafka Streams' exactly-once semantics** are distributed-systems frameworks that *make* idempotency the responsibility of the application developer, typically with helper APIs for deduplication keys and processed-ID tracking. The `@context replayable` annotation is the static-analysis counterpart to the implicit "your handler had better be idempotent" contract that these frameworks impose.

**What's novel here.** The specific combination of: (a) doc-comment annotations as the interoperable surface between humans and tooling, (b) the `externally_idempotent` and `transactional_idempotent` tiers as first-class effect positions (most prior work treats external-dedup and transaction-atomicity as implementation concerns rather than type-level distinctions), and (c) the `actorReentrancyIdempotencyHazard` rule — which catches the guard-suspend-insert anti-pattern specific to Swift actor reentrancy and does not have an equivalent in any linter surveyed — is the original contribution. The rest is a synthesis of existing ideas applied to the Swift ecosystem.

---

## What's Novel Here — Expanded

The paragraph above names three contributions. This section walks through each in detail — what exists in prior art, what this proposal adds, and why the combination matters.

### (a) Doc-comment annotations as the human/tooling interoperability surface

**What already exists.** Effect information is typically carried in one of three places:

- *The type system itself* (Koka effect rows, Haskell's `IO`, Rust `async`/`unsafe`/`const`). Strong guarantees, but requires the language to cooperate.
- *Attributes/annotations tied to a framework* (Java's `@Retryable`, Spring's `@Idempotent`, JAX-RS, Resilience4j). These are runtime configuration directives — they tell the retry framework what to do, not the compiler or a checker what to verify.
- *Linter-specific DSLs* (SwiftLint custom rules, ESLint config, CodeQL queries). These live in tool-owned files, not the source; a human reading the function cannot see the claim.

**What the proposal does differently.** It treats the Swift doc-comment grammar (`/// @lint.effect idempotent`, `/// @context replayable`, `/// @lint.assume ...`) as a *shared surface* with three consumers reading the same token:

1. The **human reviewer** reads the doc comment during code review — the claim is adjacent to the function signature, gets copy-pasted in PR descriptions, and renders in DocC.
2. The **linter** parses the same comment into structured effects and runs the body/call-graph checks described in the lattice section.
3. The **macro** (`@GenerateIdempotencyTests`) reads the same annotation to decide whether to synthesize a double-call test peer, what equivalence check to emit, and whether to mirror `async`/`throws` into the generated `@Test`.

The novel part isn't inventing annotations — it's positioning them as **interoperable data** rather than as configuration for one specific tool. Every annotation is simultaneously documentation, a verifiable claim, and test-generation input. If any of the three consumers is missing, the annotation still has value to the remaining two. That asymmetry is why incremental adoption works: a team can start by *just writing the comments* (documentation value only), add the linter later (verification), and add the macro last (test scaffolding) without rewriting the source.

This also explains why the proposal rejects protocol-only modeling. A protocol conformance carries the same information but *only* to the type system; the human reading `struct ChargeCard: IdempotentOperation` has no reason clause, no equivalence relation, and no `@lint.assume` escape hatch. The doc comment carries the same machine-readable claim *plus* the prose context a reviewer needs.

### (b) `externally_idempotent` and `transactional_idempotent` as first-class lattice positions

**What already exists.** Most prior systems use a binary split — pure/impure, idempotent/non-idempotent, safe-to-retry/not. When more nuance is needed, it's pushed into the framework layer:

- Stripe, AWS SDKs, and similar clients handle idempotency-key-based dedup as an *implementation detail* of the client library. The type signature doesn't distinguish `chargeCard(amount:)` from `chargeCard(amount:idempotencyKey:)` in a way the compiler or a linter can reason about.
- Database transaction boundaries are enforced at runtime (the DB throws if you commit twice) but don't propagate upward as a function-level property. A function that wraps several non-idempotent writes in `db.transaction { … }` has no standard way to declare "the composite is retry-safe."
- Akka's at-least-once delivery, Kafka's exactly-once semantics, and AWS Lambda's SQS trigger all *require* idempotency in the handler but provide no type- or annotation-level way to say "this handler satisfies that requirement via mechanism X."

**What the proposal does.** It promotes these two conditionally-idempotent modes to explicit, equally-ranked positions in the lattice:

```
pure < idempotent < { transactional_idempotent, externallyIdempotent } < non_idempotent
                                                                unknown (incomparable)
```

And — this is the important part — each carries *different enforcement rules* in the linter:

| Effect position | What the body check verifies |
|---|---|
| `idempotent` | No non-idempotent callees on any path, including throw paths |
| `transactional_idempotent` | All non-idempotent writes live inside a detected `db.transaction { }` / atomic-rename / single-publish boundary; demoted if any write escapes |
| `externallyIdempotent` | Function has an `IdempotencyKey` parameter; key is stable across retries (derived from inputs, not fresh entropy); `reason:` clause names the external mechanism |
| `non_idempotent` | No check; but caller composition rules propagate it |

These aren't cosmetic labels. The composition table has separate rows for each, the conflict-detection table has different lint actions for each declared/inferred pairing, and the annotation grammar has dedicated sub-directives (`@lint.txn_boundary db.transaction`, `@lint.assume stripe.PaymentIntents.create is externally_idempotent`, `IdempotencyKey` type).

**Why this matters.** The two most common production idempotency patterns are:

1. "It's idempotent *because* we pass an idempotency key to the provider." (externally_idempotent)
2. "It's idempotent *because* multiple non-idempotent writes commit atomically in one transaction." (transactional_idempotent)

A binary lattice forces both into either `idempotent` (which lies about the body) or `non_idempotent` (which over-reports and suppresses the retry-safety information the caller needs). The three-tier model captures both accurately *and* generates distinct, actionable diagnostics:

- A `transactional_idempotent` function whose body has a write outside the transaction block gets a specific "write escapes transaction boundary" error, not a generic "body is non-idempotent."
- An `externallyIdempotent` function whose key parameter is set from `UUID().uuidString` in a retry loop gets "key sourced from fresh entropy at call site," not a generic warning.

Most prior work treats these as "library-level concerns" outside the scope of an effect system. Treating them as type-level distinctions is the contribution.

### (c) `actorReentrancyIdempotencyHazard` — the guard-suspend-insert rule

**What already exists.** Swift actor reentrancy is documented in the language (SE-0306), and the general hazard is known to concurrency experts. But no shipped linter surveyed here (SwiftLint, swift-format, the Swift compiler's own warnings, SwiftSyntax-based third-party rules) has a rule that specifically targets the check-then-act-across-a-suspension pattern.

**What the pattern is.** In an actor method:

```swift
guard !processedIDs.contains(id) else { return }   // check
try await chargeCard(id)                           // suspension point — actor reopens
processedIDs.insert(id)                            // act, too late
```

Actor isolation serializes *each individual await-free segment* of the method, but at the `await` the actor is open to other callers. Two concurrent callers with the same `id` both pass the guard, both `await chargeCard`, both charge the card. The runtime won't catch this — the actor did serialize reads; it just couldn't serialize the check-suspend-act sequence as a unit. The usual "actors prevent races" mental model fails silently here.

**Why this is AST-detectable.** The pattern has a precise structural signature:

- Inside a `FunctionDeclSyntax` whose parent is an `ActorDeclSyntax`
- A `GuardStmtSyntax` whose condition contains a membership check against a stored property (`!self.X.contains(...)`, `self.X[...] == nil`)
- Followed by one or more `AwaitExprSyntax` nodes on the fall-through path
- Followed by an insertion into the *same* stored property (`self.X.insert(...)`, `self.X[...] = ...`)

SwiftSyntax has all of these node types directly. The rule is a single-pass AST traversal — no call graph, no type inference, no cross-file analysis. It fits inside SwiftProjectLint's existing `BasePatternVisitor` architecture and mirrors the structure of the other rules in `Sources/Core/StateManagement/Visitors/`.

**Why this is the highest-value original rule.** The other concurrency rules in the proposal (`nonIdempotentInTaskRetry`, `nonIdempotentInTaskGroup`, `nonIdempotentInRecursiveRetry`, `nonIdempotentInSwiftUITask`) depend on having classified the callee as `non_idempotent` — they are downstream of the effect lattice. `actorReentrancyIdempotencyHazard` is different: it fires on structural grounds alone, independent of any annotation on `chargeCard`. That means it delivers value on day one of enabling the linter, before any team has annotated anything. It's also a bug pattern that very few Swift developers recognize — actor reentrancy interacting with idempotency is subtle enough that even careful concurrency code gets it wrong, and the bug is invisible in single-threaded tests.

The fix pattern is as detectable as the bug pattern (claim the slot before the suspension, compensate in `catch`), so the linter can offer a targeted diagnostic with a concrete rewrite, not just a warning.

### Why the combination is the contribution

Each of the three pieces has partial analogs in prior work:

- Effect annotations exist in Java-land (but as runtime config).
- Multi-tiered idempotency is discussed in distributed systems literature (but not as a type-level lattice).
- Actor reentrancy hazards are documented (but not mechanically checked).

The proposal's claim is that pulling the three together — **annotations as the shared surface**, **a lattice rich enough to model the real patterns**, **and at least one concurrency rule that is detectable without the lattice** — produces a system that is adoptable incrementally (unlike Koka), verifiable (unlike Spring's `@Retryable`), and catches a class of bug (actor reentrancy idempotency) that no existing Swift tool catches. None of the three alone is the novelty; the synthesis is.
