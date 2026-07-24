[← Back to Rules](RULES.md)

## Duplicate Enum Mapping

**Identifier:** `Duplicate Enum Mapping`
**Category:** Architecture
**Severity:** Info *(opt-in)*

### Rationale
When two `switch`es over the same enum return the **exact same value for every case**, they
are not two mappings — they are one mapping written twice. The classic instance is a
`var label: String { switch self { … } }` on the enum and a free `humanReadableTier(_:) ->
String` elsewhere that reproduces it case for case; the two must agree forever, and nothing
checks that they do. Centralizing the mapping onto the enum (or one extension) makes the
duplicate impossible: change a case's value in one place, and a newly-added case forces every
caller through one exhaustiveness error.

This is the strict sibling of [Scattered Enum Mapping](scattered-enum-mapping.md). See the
design note [`duplicate-enum-mapping-rule-design.md`](../design/duplicate-enum-mapping-rule-design.md)
for the full argument; in short:

| | Scattered Enum Mapping | **Duplicate Enum Mapping** |
|---|---|---|
| Matches on | case-set + return **kind** (loose) | case-set + **value per case** (exact) |
| Threshold | ≥ 3 sites across ≥ 2 files | **≥ 2 sites** |
| Finds | a *missing abstraction* | a *copied function* |

The exact-value match is what licenses the lower threshold: two `switch`es over `Severity`
both returning *some* `Color` might be a foreground map and a background map (so Scattered
needs three before it dares fire), but two that return the *same* color for each case have no
benign reading — one is a copy. They are complements, not competitors: one trades precision
for recall, the other the reverse.

### What counts as a mapping switch
A `switch` qualifies when:

- It has **≥ 3** `case .label:` arms whose patterns are leading-dot enum constants (`.error`,
  `.warning`, …). Value-binding / associated-value patterns (`.foo(let x)`) disqualify it.
- **Every arm body is a single expression** — `return X` or the implicit-return switch-
  expression form `X` — that is a **literal, a member, or a named initializer** (`"Verified"`,
  `5`, `.red`, `Color.red`, `Color(...)`). Arbitrary expressions (a call on a lowercase
  callee, an operator expression, a string interpolation) are not a constant map and
  disqualify the switch — the same gate Scattered Enum Mapping uses.

Each qualifying switch is reduced to its `case-label → value-text` map (plus any `default:`
value). Two switches **group** when those maps are identical — every case mapped to the exact
same value text.

### When it fires
A group of ≥ 2 switches at distinct source locations sharing one value map. If one member is
the enum's own `switch self` mapping, it is treated as the canonical home and only the
duplicates are reported, each pointed at it ("identical to the one already on the type … it is
that mapping copied"). Otherwise every site in the group is reported as an un-extracted copy
("written identically in N places … the same function copied").

### Known limitations / false-positive posture
- **Value text is compared, not values.** Two arms that are semantically equal but written
  differently (`Color(red: 1)` vs `Color(red: 1.0)`; different whitespace inside an
  initializer) do **not** group. This is conservative — it can miss a duplicate, never invent
  one.
- **`default:` participates.** A switch with a `default:` arm only groups with another that has
  an identical `default:` value; an exhaustive switch and a `default`-using one are treated as
  different mappings.
- **Name-keyed subject.** The subject enum is named by matching the case-label set against
  catalogued enums (by simple name). If no enum matches, the finding still fires and names the
  cases generically.
- **Implicit-member values (`.red`) are compared as bare text.** Two switches returning `.red`
  for the same cases group even if their result types differ — the exact-text match is the
  design, and the residual risk is why the rule is `Info` and opt-in. Suppress with
  `// swiftprojectlint:disable Duplicate Enum Mapping` (or the deliberate-boundary case is the
  natural home for a future `linked-to` sync contract).
- Thresholds (3 labels / 2 sites) are compile-time constants; per-rule YAML is a planned
  follow-up, matching the other Architecture cross-file rules.

### Violating Example
```swift
// Tier.swift — the canonical mapping lives on the enum.
enum Tier {
    case verified, strong, likely
    var label: String {
        switch self {
        case .verified: return "Verified"
        case .strong:   return "Strong"
        case .likely:   return "Likely"
        }
    }
}

// IndexProjection.swift — a byte-identical copy. FLAGGED: delete it, call `tier.label`.
func humanReadableTier(_ tier: Tier) -> String {
    switch tier {
    case .verified: return "Verified"
    case .strong:   return "Strong"
    case .likely:   return "Likely"
    }
}
```

### Non-Violating Examples
```swift
// Same enum and cases, but genuinely DIFFERENT values — a real second mapping, not a copy.
func foreground(_ sev: Severity) -> Color {
    switch sev {
    case .error:   return .red
    case .warning: return .orange
    case .info:    return .blue
    }
}

func background(_ sev: Severity) -> Color {
    switch sev {
    case .error:   return .pink     // ← different value ⇒ not grouped
    case .warning: return .yellow
    case .info:    return .teal
    }
}
```

```swift
// Centralized once — every consumer calls `tier.label`. Nothing to duplicate.
enum Tier {
    case verified, strong, likely
    var label: String {
        switch self {
        case .verified: return "Verified"
        case .strong:   return "Strong"
        case .likely:   return "Likely"
        }
    }
}
```
