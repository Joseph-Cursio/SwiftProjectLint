[← Back to Rules](RULES.md)

## Boolean Control Coupling

**Identifier:** `Boolean Control Coupling`
**Category:** Architecture
**Severity:** Warning

### Rationale
A `Bool` parameter that the function body uses to *choose between two code paths* is
**control coupling**: the caller reaches in and decides which behavior the callee runs.
The decision is real and important, but it's hidden behind a flag instead of being named.

This is the linter form of Adam Tornhill's argument in
[*Hidden Design Decisions — Refactoring Control Coupling*](https://adamtornhill.substack.com/p/hidden-design-decisions-refactoring):
replace the flag with a **strategy** — two named functions, or a protocol / closure passed
in — so each path has a name a reader (or an LLM) can see. His framing is that a named
strategy carries its intent in the type system, where a `true`/`false` carries it only in
the head of whoever wrote it.

```swift
// Control coupling: the caller picks the algorithm with a flag.
func export(_ report: Report, asPDF: Bool) {
    if asPDF {
        renderPDF(report)
        attachMetadata(report)
    } else {
        renderHTML(report)
        inlineStyles(report)
    }
}

// Strategy: each path is a named thing.
protocol ReportExporter { func export(_ report: Report) }
struct PDFExporter: ReportExporter  { func export(_ report: Report) { … } }
struct HTMLExporter: ReportExporter { func export(_ report: Report) { … } }
```

### Why this is *not* the same as Magic Boolean Parameter
[Magic Boolean Parameter](magic-boolean-parameter.md) is a **caller-side** readability rule:
it flags unlabeled boolean literals at the call site (`export(report, true)` — what is `true`?).
Swift's argument labels already fix most of that (`export(report, asPDF: true)` reads fine).

Boolean Control Coupling is **callee-side** and orthogonal: it doesn't care whether the call
site is labeled. It fires only when the parameter actually *drives a two-armed branch in the
body* — the part argument labels don't fix, because the function still does two things.

### Discussion
`BooleanControlCouplingVisitor` runs per-file. For every function and initializer **with a
body** it collects the internal names of its `Bool` parameters (including `Bool?`), then looks
for an `if` statement that:

1. **references one of those parameters** in its condition — directly (`if flag`), negated
   (`if !flag`), or as part of a compound condition (`if flag && ready`). An `obj.flag` member
   access that merely shares the name does **not** count; and
2. has a plain **`else { … }`** block — an `if` with no `else` is *optional behavior*
   (`if verbose { log() }`), not a choice between two strategies; and
3. has **two substantial arms**. An arm is substantial when it has **two or more statements**,
   or **contains a function/method call**. A single literal/value return (`return .red`,
   `return 0`) is *not* substantial — a boolean→value map is not this smell; and
4. is **not already-named dispatch** — both arms exactly one statement; and
5. is **not deferred initialization of one value** — a typed, uninitialized `let`/`var`
   immediately before the `if`, assigned as the final statement of each arm.

Gates 1–3 say what the branch must be. Gates 4 and 5 say what it must *not* be, and both
were added after the rule was measured across a 26-repository corpus; see
[Why gates 4 and 5 exist](#why-gates-4-and-5-exist). The bare presence of a `Bool`
parameter is **not** flagged.

#### Why gates 4 and 5 exist

Gate 3 is a disjunction — "two or more statements, **or** contains a call" — so a single
call clears it. But a single call is a **name**, and a name is what this rule asks the code
to produce. When both arms are one call, the split into two named functions has already
happened and the `if` is the one dispatch point that has to live somewhere; the rule was
reporting the residue of its own advice.

This documentation carried the proof before the corpus did. The canonical violating example
below used to be:

```swift
func price(isPremium: Bool) -> Int {
    if isPremium { return premiumPrice() } else { return standardPrice() }
}
```

with the suggestion *"split into two named functions (`premiumPrice()` / `standardPrice()`
called directly)"* — naming the two functions the example already had. The rationale example
further up (`export(_:asPDF:)`) is the shape that actually needs the advice, and it is the
one the rule now leads with.

Measured across 26 repositories, the rule fired eight times:

| site | flag | arms | verdict |
|---|---|---|---|
| `ConfigModel.swift:128` | `enabled` | `config.enableRule(name)` / `disableRule(name)` | gate 4 |
| `Discover+Render.swift:36` | `statsOnly` | `renderStats(…)` / `render(…)` | gate 4 |
| `MagicNumberVisitor.swift:143` | `isLayoutArg` | `recordLayoutNumber(…)` / `recordMagicNumber(…)` | gate 4 |
| `MagicNumberVisitor.swift:149` | `isLayoutArg` | as above, for float literals | gate 4 |
| `NativeSequenceDiagramView.swift:260` | `filled` | `context.fill(path, …)` / `context.stroke(path, …)` | gate 4 |
| `LiftedTestEmitter+Determinism.swift:53` | `isThrows` | both build `property` | gate 5 |
| `PRCommentGenerator.swift:182` | `includeLinks` | 2 statements / 1, both appending | **refactored** |
| `StreamingTokenizer.swift:18` | `buggy` | 1 statement / 5 | **true positive** |

Six of eight were the rule describing a correct site wrongly. The `filled` row is the sharpest:
`GraphicsContext.fill` and `.stroke` are SwiftUI's, so there is no split available at any price
— the finding could not be acted on even in principle.

**Gate 4 tests both arms rather than putting a floor under each one**, and the asymmetry is
the reason. A genuine two-algorithm branch is lopsided — `tokenizeStreaming(_:buggy:)` is one
line against five — so a floor on each arm would have silenced the one true positive while
sparing all five dispatch pairs.

**Gate 5 is the boolean→value exclusion gate 3 already states, extended past one line.**
Swift offers no other spelling for a `let` whose value takes statements to compute, so
needing three of them does not turn a value into a strategy. It is deliberately narrow: the
declaration must sit immediately before the `if`, carry no initializer, and each arm must end
in a plain `=` to it. Arms that merely happen to end by assigning the same variable —
`total += 10` / `total += 20` — are accumulation, not initialization, and still fire.

#### Exemptions
- **`override` methods** — the signature is inherited and can't be changed freely.
- **Protocol requirements / bodyless declarations** — nothing to refactor.
- **Test, fixture, mock, and example files** — via the shared path heuristic.
- **Standard-library capacity conventions** — a parameter named `keepCapacity` or
  `keepingCapacity` (on either the label or the internal name) is exempt. These mirror
  `Array.removeAll(keepingCapacity:)` and the many collection methods built on it; they
  branch two ways by design, but echoing the stdlib spelling is the point, so a strategy
  would fight the convention rather than clarify it.

#### Known limitations / false-positive posture
- **`else if` chains** are evaluated at the inner `if`. The flag driving a middle `else if`
  arm is caught; the chain as a whole is not analyzed structurally.
- **Value selection caught by the call gate.** This used to be listed here as an acceptable
  edge: *"an arm whose only work is `someLogger.log(...)` on both sides will fire even though
  it's arguably one behavior with two messages."* Corpus measurement made it the rule's
  dominant behavior — five of eight findings — which is a limitation large enough to be the
  rule not working. Gate 4 now handles it, and this entry is kept as the record of a
  known limitation that was bigger than it looked.
- **Spelling sensitivity: ternaries are invisible.** The rule sees `if`/`else` blocks only.
  In `LiftedTestEmitter+Determinism.swift:53` an `isAsync` flag selects between two paths via
  `isAsync ? … : …` on the line above the reported `isThrows` branch — the same coupling, in
  the same function, unreported. So the count is a census of *spelling* as much as of
  coupling. Extending to ternaries is tracked separately; most of what it would add looks like
  gate-5 value selection, which is the thing worth measuring before widening the rule.
- **Platform-convention flags** (`animated:`, `reversed:`, `ascending:`) rarely trip the
  two-substantial-arms gate, so they seldom fire — but if one genuinely branches two
  algorithms, it will, and that's usually correct.
- **Only `Bool`/`Bool?` parameters.** A flag smuggled through an enum with two cases is a
  different (and better) shape and is out of scope here.

Suppress a deliberate instance with `// swiftprojectlint:disable boolean-control-coupling`.

### Non-Violating Examples
```swift
// Stored, not branched — the bool is data, not a decision.
init(enabled: Bool) { self.enabled = enabled }

// Optional behavior — no else, so not two strategies.
func run(verbose: Bool) {
    doWork()
    if verbose { log() }
}

// Boolean → value map — single value per arm, no work.
func color(isError: Bool) -> String {
    if isError { return "red" } else { return "green" }
}

// Already-named dispatch (gate 4) — both paths have names; this is the one
// dispatch point that has to exist somewhere.
func record(_ argument: Argument, isLayoutArg: Bool) {
    if isLayoutArg {
        recordLayoutNumber(argument)
    } else {
        recordMagicNumber(argument)
    }
}

// Deferred initialization of one value (gate 5) — the branch picks a value, it
// just needs statements to build it.
func property(for call: String, isThrows: Bool) -> String {
    let property: String
    if isThrows {
        let guarded = "(try? " + call + ")"
        property = guarded + " == " + guarded
    } else {
        let plain = call
        property = equalityExpression(lhs: plain, rhs: plain)
    }
    return property
}
```

### Violating Examples
```swift
// Two algorithms behind a flag — the canonical control-coupling shape. Neither
// arm's work has a name yet, which is exactly what a strategy would give it.
func export(_ report: Report, asPDF: Bool) {
    if asPDF {
        renderPDF(report)
        attachMetadata(report)
    } else {
        renderHTML(report)
        inlineStyles(report)
    }
}

// Lopsided arms — one line against five. The shape of a planted algorithm swap,
// and the only finding in the 26-repository corpus the rule described correctly.
func tokenize(_ chunks: [String], buggy: Bool) -> [String] {
    for chunk in chunks {
        if buggy {
            tokens += split(chunk)
        } else {
            buffer += chunk
            var segments = split(buffer)
            let partial = segments.removeLast()
            tokens += segments
            buffer = partial
        }
    }
}
```

**Suggestion:** Replace the flag with a strategy — split into two named functions called
directly, or pass in a protocol / closure so each path is explicit and named at the call site.

Note the suggestion is only followable while the split has *not* been made. Once the two paths
are named, what remains is a dispatch point, and gate 4 stops reporting it.

---
