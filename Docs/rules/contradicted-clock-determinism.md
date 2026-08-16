[← Back to Rules](RULES.md)

## Contradicted Clock Determinism

**Identifier:** `Contradicted Clock Determinism`
**Category:** Testability
**Severity:** Warning

### Rationale

**This is the only rule in the testability family that reports a contradiction rather than a smell.** The others describe code that *could* be more testable. This one says two parts of the same file disagree, and that a downstream tool is trusting the wrong half.

`@ClockDeterministic` — or its doc-comment spelling `/// @lint.determinism clock_deterministic` — is a claim an author makes: *"my result does not vary with wall-clock time, **given** an injected `Clock`."* It exists because `.pure` implies synchronous, so an `async` function can never occupy the effect lattice's bottom tier no matter how well-behaved it is. The marker is what lets a consumer relax its **async veto** and admit such a function to property-based verification anyway.

So the claim is load-bearing, and until this rule existed it was **parsed and never checked**. The author's word was the whole of the evidence. A wrong claim does not fail loudly — it produces a generated property test that passes locally and flakes later, which is the expensive failure mode the toolchain exists to prevent.

```swift
// Flagged — the annotation says one thing, the body does another
@ClockDeterministic
func expiry() async -> Date {
    Date(timeIntervalSinceNow: 3600)
}

// Flagged — the acquisition is in this body, even though the use looks injected
@ClockDeterministic
func tick() async -> ContinuousClock.Instant {
    let clock = ContinuousClock()
    return clock.now
}

// Clean — the clock arrives as a parameter, which is what the claim asserts
@ClockDeterministic
func debounce<C: Clock>(clock: C) async throws {
    try await Task.sleep(for: .seconds(1), tolerance: nil, clock: clock)
}
```

### What counts as reaching for a clock

The check refutes the **acquisition** of an ambient clock, not the *use* of one. An ambient clock has to be obtained somewhere, and obtaining it is syntactically distinctive in a way that using one is not — which is what lets `clock.now` on an injected parameter survive while `let clock = ContinuousClock()` does not.

| form | reported | why |
|---|---|---|
| `Date()`, `Date.now` | yes | reads the host clock |
| `Date(timeIntervalSinceNow:)` | yes | an offset *from* now still reads now |
| `Date(timeIntervalSince1970:)` | no | fixed reference point, deterministic |
| `ContinuousClock()`, `SuspendingClock()` | yes | constructing the host clock |
| `Task.sleep(for:)` | yes | falls back to the host clock |
| `Task.sleep(for:tolerance:clock:)` | no | sleeps on the clock it was handed |
| `clock.now` where `clock` is a parameter | no | the point of the claim |
| `UUID()`, `.shuffled()` | no | not the claim's subject — see below |

Nested closures are included: an acquisition inside `Task { }` is still this function reaching for a clock nobody passed in.

### Two limits worth knowing

**A clean result is not a verified claim.** The claim holds only when nothing in the function *or anything it transitively calls* reaches for ambient time, and absence like that cannot be established by a syntactic pass. The oracle behind this rule therefore refuses to *confirm* the claim and offers only to *contradict* it — one witness is enough for a violation, which is why the refuting direction is tractable where the confirming one is not. This rule catches authors who are wrong in a visible way, not authors who are wrong.

**Only clock nondeterminism counts.** `@ClockDeterministic` says the result does not vary with wall-clock time. It says nothing about a `UUID()` or a `.shuffled()`, so those do not contradict it — reporting them would fire on annotations that are perfectly honest about time. Inline randomness is [Non-Injected Nondeterminism](non-injected-nondeterminism.md)'s subject, and both rules read the same classifier so they cannot disagree about what an expression is.

### Not a duplicate of Non-Injected Nondeterminism

[Non-Injected Nondeterminism](non-injected-nondeterminism.md) reports inline clock reads in *any* function and says the code is hard to test. This rule fires only where the author claimed the opposite, and says the code contradicts itself.

That difference is deliberate in the implementation too: the underlying oracle returns nothing for an **unannotated** function. A function reaching for a clock without having claimed otherwise contradicts nothing, and reporting it here would be the tool inventing a claim in order to violate it.

### How to fix

Take the clock as a parameter and read it there — that is the shape the annotation describes, and it is what makes the function testable with a `TestClock`. If the function genuinely depends on ambient time, drop the annotation instead: a consumer is relaxing its async veto on the strength of it.

---

*Generated from visitor source code and test cases in SwiftProjectLint. To contribute a rule correction or new rule, see the [contributor guide](../CONTRIBUTING.md).*
