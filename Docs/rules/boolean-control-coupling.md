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
   `return 0`) is *not* substantial — a boolean→value map is not this smell.

The "substantial both arms + mandatory else" gate is what keeps the rule quiet. The bare
presence of a `Bool` parameter is **not** flagged.

#### Exemptions
- **`override` methods** — the signature is inherited and can't be changed freely.
- **Protocol requirements / bodyless declarations** — nothing to refactor.
- **Test, fixture, mock, and example files** — via the shared path heuristic.

#### Known limitations / false-positive posture
- **`else if` chains** are evaluated at the inner `if`. The flag driving a middle `else if`
  arm is caught; the chain as a whole is not analyzed structurally.
- **Value selection caught by the call gate.** An arm whose only work is `someLogger.log(...)`
  on both sides will fire even though it's arguably one behavior with two messages. It's a
  `Warning`; suppress per-site if intended.
- **Platform-convention flags** (`animated:`, `reversed:`, `ascending:`) rarely trip the
  two-substantial-arms gate, so they seldom fire — but if one genuinely branches two
  algorithms, it will, and that's usually correct.
- **Only `Bool`/`Bool?` parameters.** A flag smuggled through an enum with two cases is a
  different (and better) shape and is out of scope here.

Suppress a deliberate instance with `// swiftprojectlint:disable Boolean Control Coupling`.

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
```

### Violating Examples
```swift
// Two algorithms behind a flag — the canonical control-coupling shape.
func price(isPremium: Bool) -> Int {
    if isPremium {
        return premiumPrice()
    } else {
        return standardPrice()
    }
}
```

**Suggestion:** Replace the flag with a strategy — split into two named functions
(`premiumPrice()` / `standardPrice()` called directly), or pass in a protocol / closure
so each path is explicit and named at the call site.

---
