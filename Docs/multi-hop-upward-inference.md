# Multi-hop / fixed-point upward inference

> **Status: shipped April 2026.** This document originally captured the design before implementation. The four-step plan at the bottom landed as described, with the worklist optimisation (step 5 in spirit) deferred — current implementation iterates over every source on every pass and relies on rapid lattice convergence (2-3 passes typical). See `Docs/idempotency-macros-analysis.md` Phase 3 for the post-shipping summary.

---


## Background: what "upward inference" is

The lattice has four tiers, ranked least-to-most permissive:

```
observational  <  idempotent  <  externally_idempotent  <  non_idempotent
```

When a function is **annotated**, the linter takes its effect at face value. When it isn't, the linter has two ways to guess:

- **Downward heuristic** (`HeuristicEffectInferrer`): name-based. `func insert(...)` → `non_idempotent`. Cheap, fragile, looks at the name only.
- **Upward inference** (`UpwardEffectInferrer`): body-based. Walk the function's body, take the **least upper bound (lub)** of every direct callee's effect, and assign that to the function. A function that calls only `logger.info` is observational; a function whose body contains a `non_idempotent` call is itself `non_idempotent`.

Upward is a stronger signal than downward because it looks at what the function actually *does*, not what it's named.

## What "one-hop" means today

The currently shipped version (Phase 2.3, `UpwardEffectInferrer`) intentionally restricts the resolution function it consults:

```swift
// UpwardEffectInferrer.swift:24-29
/// The inferrer uses only **declared effects** and **heuristic-downward
/// effects** of body callees. It does **not** chain through other upward-
/// inferred callees.
```

So when inferring `A`'s effect, callee resolution returns:
1. `B`'s declared annotation (if any), else
2. `B`'s name-based heuristic (if it matches the whitelist), else
3. nothing.

It explicitly does **not** look up "did we just upward-infer B?"

### Concrete two-hop miss

```swift
func chargeCard(...) async throws { /* declared @lint.effect non_idempotent */ }

func processOrder(_ order: Order) async throws {       // un-annotated B
    try await chargeCard(order)                         // declared non_idempotent
}

/// @lint.context replayable
func handleWebhook(_ order: Order) async throws {      // A
    try await processOrder(order)
}
```

What the linter does today:
- Inferring `processOrder`: callee `chargeCard` is declared `non_idempotent`. Lub → `processOrder` is upward-inferred `non_idempotent`. ✓
- Inferring `handleWebhook`: callee `processOrder` is un-annotated. The resolver returns `nil` (one-hop rule: don't chain upward). Lub of `[]` → no inference. ✗
- `nonIdempotentInRetryContext` looks up `processOrder`'s effect at the call site, gets `nil`, and **stays silent**. The webhook bug is missed.

That's the "two-hop chain" limitation. The bug is real, the data to detect it exists, but the rule is intentionally blind to it.

## Why one-hop was the first slice

Two reasons in the source comment:

1. **Order-invariance.** With one-hop, `inferEffects` can run in any file order and produces the same answer. If `processOrder` were inferred first and then `handleWebhook` consulted that result, the answer would depend on which was processed first — unless you keep iterating until nothing changes.
2. **Implementation simplicity.** A single pass over un-annotated functions, mapping each to a lub. No worklist, no convergence check, no termination proof.

## What multi-hop would do

Extend resolution to also consult prior upward-inferred results:

```
declared > collision-withdraw > upward-inferred > heuristic-downward > silent
                                ^^^^^^^^^^^^^^^
                                consult THIS pass's results too
```

In the example, `handleWebhook`'s resolver would now find `processOrder` in the upward-inferred map (`non_idempotent`), and the rule would fire.

## Why a "fixed-point" algorithm is needed

Once you allow chaining, processing order matters. Consider three functions:

```swift
func a() { b() }
func b() { c() }
func c() { /* @lint.effect non_idempotent */ }
```

Order 1 (c, b, a): infer `c` (declared) → infer `b` (sees `c` non_idempotent) → infer `a` (sees `b` non_idempotent). Done in one pass. Everything resolves to non_idempotent.

Order 2 (a, b, c): infer `a` (sees `b` un-resolved → nil) → infer `b` (sees `c` declared → non_idempotent) → never revisits `a`. `a` stays un-inferred.

To get the right answer regardless of order, you iterate:

```
repeat:
    for each un-annotated function f:
        new_effect = lub(resolve(callee) for callee in body of f)
        if new_effect != current_effect[f]:
            current_effect[f] = new_effect
            changed = true
until not changed
```

This is the **fixed-point** — keep recomputing until no effect changes in a full sweep, then you know everything is consistent.

### Why it terminates

The lattice has finite height (4 tiers). For any function, the inferred effect can only **rise** (more permissive) across iterations — once you've seen evidence that `f` is non_idempotent, you can't un-see it. So each function's effect changes at most 3 times (`observational → idempotent → externally_idempotent → non_idempotent`). With N functions, the worst case is `O(N × 4)` iterations of a `O(N)` sweep, i.e. `O(N²)` work — but in practice convergence happens in 2–3 iterations because most functions don't sit deep in chains.

### Standard fixed-point speedup: worklist

Naive iteration re-examines every function on every pass. The textbook optimization is a **worklist algorithm**:

1. Build a reverse call graph: callee → set of callers.
2. Compute initial effects for every function (one pass).
3. Worklist starts with everything that changed.
4. Pop `f` from the worklist. For each caller of `f`, recompute its effect. If it changed, push that caller onto the worklist.
5. Repeat until empty.

Same answer, much less work — only functions whose callees actually changed get reprocessed.

## What this would unlock

- **Webhook chains.** The Stripe-style "handler → service → driver → externalCall" pattern (the canonical pointfreeco trial shape) often has 2–4 unannotated hops between the `@lint.context replayable` boundary and the `@lint.effect non_idempotent` leaf. One-hop catches only the bottom hop.
- **Refactoring resilience.** Today, extracting an intermediate helper (`processOrder` above) silently breaks idempotency analysis. With multi-hop, helpers don't degrade detection.
- **Less annotation pressure.** Currently, users have to annotate intermediates to make the chain visible. Multi-hop would let them annotate only the leaves.

## What it costs

- **Order-invariance gone for free:** mitigated by fixed-point, but you have to actually build the call graph and run the iteration.
- **Cross-file complexity.** Today, `EffectSymbolTable.merge(source:)` accumulates declared effects file-by-file and emits during `finalizeAnalysis`. Multi-hop would need to defer upward inference until *after* the symbol table is complete (already true — Phase 2.3 runs in `finalizeAnalysis`), then run the worklist over the whole project graph at once. That's a structural change to where inference fits in the analysis pipeline.
- **Diagnostic provenance.** Today the message says "callee `B` whose effect is inferred non_idempotent from name." With multi-hop you need to say something like "callee `B` whose effect is inferred non_idempotent from its body, which calls `C` declared non_idempotent." Users need to be able to follow the chain to verify the diagnostic isn't a phantom.
- **Collision interaction.** The OI-4 collision policy (when two annotated declarations of the same signature disagree, withdraw the entry and stay silent) interacts subtly with multi-hop: a withdrawn entry should poison the chain, not silently drop out of the lub. That's a design call, not a free choice.

## Suggested next-step shape

If you wanted to land this, the smallest viable slice would be:

1. Keep one-hop as the default; add a `multiHop: Bool` flag to `UpwardEffectInferrer.inferEffects`.
2. In `finalizeAnalysis`, run a worklist over the merged symbol table, treating each pass's results as input to the next.
3. Add a depth counter to diagnostic messages ("…inferred via 2-hop chain through `processOrder`").
4. Cap depth at, say, 5 hops as a circuit breaker — if convergence somehow doesn't happen, you'd rather fail visibly than spin.
