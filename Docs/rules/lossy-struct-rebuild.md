[← Back to Rules](RULES.md)

## Lossy Struct Rebuild

**Identifier:** `Lossy Struct Rebuild`
**Category:** Code Quality
**Severity:** Warning

### Rationale

A value reconstructed field-by-field from one you already have will **silently lose any field you
forget** — provided its initialiser has defaulted parameters. And it usually does.

```swift
return Suggestion(
    templateName: suggestion.templateName,
    evidence: suggestion.evidence,
    score: suggestion.score,
    generator: metadata,                    // ← the one thing this copy meant to change
    explainability: suggestion.explainability,
    identity: suggestion.identity,
    liftedOrigin: suggestion.liftedOrigin,
    mockGenerator: suggestion.mockGenerator,
    carrier: suggestion.carrier
    // carrierTypeName:   ← forgotten. Defaults to nil. Compiles. Ships.
)
```

**The defaults are the entire mechanism.** If every parameter were required, omitting one would be a
compile error and this shape would be harmless. Because some have defaults, the omission type-checks
and produces a value that is correct in every visible respect and quietly missing part of itself.
Nothing goes red. The bug surfaces weeks later, as someone wondering why a field they definitely set
is `nil` three stages downstream.

That is why the rule fires **only** when the constructed type's initialiser has defaulted parameters.
Without them there is nothing to lose.

### Why this earns a rule

The shape is easy to write and nearly impossible to review: every argument looks right, and the bug
is in the argument that **isn't there**. Reviewers check what is on the page.

In one codebase a single type was rebuilt this way in **eight** places, and the same silent
field-drop was discovered and patched **three separate times** — each fix adding the missing argument
and leaving the trap armed for the next field:

| discovered | site | field silently lost |
|---|---|---|
| once | the generator-selection pass | `carrierTypeName` — the downstream index fell back to the wrong type |
| again | the cross-validation pass | `carrier`, `carrierTypeName`, `liftedOrigin`, `mockGenerator` — four at once |
| again | **all eight sites** | a newly added field, dropped everywhere it was copied |

Each fix was local, correct, and useless against the *next* field. That is what a rule is for.

### The fix

**Copy the value and mutate it.** A mutating copy cannot drop a field, and needs no edit when one is
added:

```swift
var copy = suggestion
copy.generator = metadata
return copy
```

**If the properties are `let`,** that fix is not available to you, and the rule's suggestion says so.
Funnel every rebuild through a **single** `with(…)` method on the type instead:

```swift
extension Suggestion {
    func withGenerator(_ metadata: GeneratorMetadata) -> Self {
        var copy = self       // requires `var` properties
        copy.generator = metadata
        return copy
    }
}
```

That still leaves one place to update rather than eight — a genuine improvement even where the fields
must stay immutable.

### Discussion

`LossyStructRebuildVisitor` fires on an initializer call `T(…)` where:

1. **`T`'s initialiser has defaulted parameters** — supplied project-wide by
   `DefaultedInitializerCollector`, which sees explicit `init`s with `= default` arguments *and*
   structs with no explicit `init` whose stored properties carry initialisers (Swift's synthesised
   memberwise init defaults those, and nobody wrote it down).
2. **Most of the arguments read from one source value** — the threshold is `m > n/2`, capped at
   `n − 1`, over at least three arguments.
3. **The source is the same type as `T`** — not a projection into a different one.

#### Two forms, and they are not equally trustworthy

```swift
Suggestion(templateName: other.templateName, …)   // ← names its source
Suggestion(templateName: templateName, …)         // ← `self.templateName`, with the `self.` left off
```

The first **names its source**, so the shape alone is strong evidence: when the source's type cannot
be resolved from the file, the ratio stands on its own and the rule reports anyway.

The second names nothing, and cannot be trusted on shape. A bare `origin: origin` reads the enclosing
function's **parameter** when one exists by that name, and a `static` function has no `self` at all —
so both are excluded. Without those gates, every factory that names its parameters after the type's
fields reads as a self-copy. (It did: nine false positives in one file, on the first cut of this
rule.)

#### The threshold is a majority, not a supermajority

Deliberately. **The dangerous rebuild is the one that changes several fields**, because the more it
changes, the likelier one gets forgotten. A 70% bar would exclude exactly that case — a nine-argument
rebuild that recomputes four of them slips under it, while being the precise shape in which the fifth
field goes missing.

### Non-Violating Examples

```swift
// The fix. Cannot drop a field, needs no edit when one is added.
var copy = suggestion
copy.generator = metadata
return copy

// A PROJECTION into a different type — a perfectly good thing to write, and it looks
// identical from the arguments alone.
SemanticIndexEntry(
    templateName: suggestion.templateName,
    score: suggestion.score,
    identity: suggestion.identity,
    tier: suggestion.tier
)

// A static factory building a FRESH value from its own parameters. `origin: origin`
// reads the parameter, not `self.origin` — and a `static` func has no `self`.
static func roundTrip(templateName: String, evidence: [Evidence], origin: Origin? = nil) -> Self {
    Self(templateName: templateName, evidence: evidence, origin: origin)
}

// A type whose initialiser has NO defaulted parameters: a forgotten field is a
// compile error, so nothing can be silently lost.
Point(x: other.x, y: other.y, z: other.z)
```

### Violating Examples

```swift
// Rebuilt field-by-field from a named value of the same type. `carrierTypeName` is
// not here, so it silently becomes nil.
func rebuild(_ suggestion: Suggestion, generator: GeneratorMetadata) -> Suggestion {
    Suggestion(
        templateName: suggestion.templateName,
        evidence: suggestion.evidence,
        score: suggestion.score,
        generator: generator,
        identity: suggestion.identity,
        carrier: suggestion.carrier
    )
}

// The same bug from inside the type — `self.` left off, which is the form it most
// often takes.
struct Suggestion {
    func withExplainability(_ block: ExplainabilityBlock) -> Self {
        Self(
            templateName: templateName,
            evidence: evidence,
            score: score,
            explainability: block,
            identity: identity
        )
    }
}
```

### Suppressing

If a rebuild is genuinely deliberate — you *mean* the omitted fields to take their defaults — say so
at the site, because the next reader cannot tell the difference between a reset and a mistake:

```swift
// swiftprojectlint:disable lossy-struct-rebuild
// Deliberate: this is a RESET, not a copy — the unlisted fields must return to their defaults.
```

Write the *reason*, not just the suppression. A bare disable comment says "I saw the warning"; it does
not say "and the omission is intended", which is the only thing a future reader needs to know.
