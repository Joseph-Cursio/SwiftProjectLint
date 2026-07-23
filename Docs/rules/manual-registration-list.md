[← Back to Rules](RULES.md)

## Manual Registration List

**Identifier:** `Manual Registration List`
**Category:** Architecture
**Severity:** Info

### Rationale
A run of consecutive statements that each register one item — `register…`, `add…`, `append`,
`record` — is a list maintained by hand. Such a list silently loses entries: a template,
category, or factory added elsewhere is only wired in if someone remembers to add a line here,
and forgetting is not a compile error. The omission is invisible until something is missing at
runtime.

A data-driven registry — one declared array, iterated once — removes the failure mode. The new
entry goes in the array, and the loop cannot skip it.

This rule flags the *shape* before it has cost anything. Its cross-file counterpart,
[Parallel List Drift](parallel-list-drift.md), flags a hand-maintained list that has **already**
fallen behind the enumeration it mirrors. The two compose: this rule tells you a list is
fragile, that one tells you it has broken.

### Discussion
`ManualRegistrationListVisitor` runs per-file. It scans each statement list for a maximal run
of consecutive expression statements that call the **same** registration-verb method, and flags
any run of **5** or more.

Three constraints keep the rule quiet on ordinary code:

- **The callee must match at a camelCase boundary.** `registerFactory` matches the verb
  `register`; `address` does not match `add`. The verb vocabulary lives in `RegistrationVerb`,
  shared with [Parallel List Drift](parallel-list-drift.md) so a verb added for one rule is
  honoured by the other.
- **The run must be the same callee.** Interleaved or alternating calls do not accumulate, so
  assertion-heavy tests and mixed setup blocks do not trip it.
- **Output-building `append`/`insert`/`put` of string text is excluded.** `lines.append("…")`
  or `out.append("\(x)")` in a renderer or emitter constructs a report line by line — each
  entry is unique text joined later, not a distinct component that could be silently omitted
  from a registry. The unambiguous registration verbs (`register`, `bind`, `connect`, …) still
  count even with a string argument, so a register-by-name registry (`commands.register("build")`)
  is unaffected; only the collection verbs get the string exclusion. This was the rule's dominant
  false positive: measured across the author's projects it went from **5 of 23** findings actionable
  to **5 of 5**, the 18 excluded runs all being renderers building output.

Recognized verbs: `register`, `add`, `append`, `insert`, `put`, `record`, `bind`, `connect`,
`install`, `mount`, `wire`, `enroll` (the last three plus `register`/`bind`/`connect` are the
"unambiguous" set exempt from the output-building exclusion above).

#### Known limitations / false-positive posture
- **Five is a heuristic.** Shorter runs are usually incidental repetition; a genuinely fragile
  four-entry list is not reported.
- **Order-dependent registration is not detected.** If the entries must be registered in a
  specific order, an array plus a loop preserves that — but the rule cannot verify it, so the
  suggestion is worth a moment's thought rather than a mechanical rewrite.
- **Runs must be consecutive.** A hand-maintained list interrupted by logging or conditional
  statements is not flagged.
- The rule reports the *shape*, not a defect. It is `Info`.

### Non-Violating Examples
```swift
// Already data-driven — a new entry cannot be omitted from the loop.
let factories = [StateManagement.self, Performance.self, Security.self,
                 Accessibility.self, Networking.self]
for factory in factories { registry.register(factory) }
```

```swift
// Below the threshold of five.
registry.register(a)
registry.register(b)
registry.register(c)
```

```swift
// `address` does not match the verb `add` — the boundary must be camelCase.
person.address(line1)
person.address(line2)
person.address(line3)
person.address(line4)
person.address(line5)
```

```swift
// Output-building, not a registry: each append is unique text joined later, so a forgotten
// line is not a silent-omission bug. `append` of string content is excluded.
var lines: [String] = []
lines.append("Summary")
lines.append("")
lines.append("  • \(first)")
lines.append("  • \(second)")
lines.append("Done")
return lines.joined(separator: "\n")
```

### Violating Examples
```swift
// Twelve consecutive registrations of the same method — a hand-maintained list.
SourcePatternRegistry.registerFactory { registry, visitorRegistry in
    StateManagement(registry: registry, visitorRegistry: visitorRegistry)
}
SourcePatternRegistry.registerFactory { registry, visitorRegistry in
    Performance(registry: registry, visitorRegistry: visitorRegistry)
}
SourcePatternRegistry.registerFactory { registry, visitorRegistry in
    Security(registry: registry, visitorRegistry: visitorRegistry)
}
// … nine more
```

**Suggestion:** Drive these from a declared array iterated once, so a new entry cannot be
omitted from this list.

#### Real-world discovery
SwiftProjectLint's own `BuiltInRules.registerAll()` is exactly this shape — 12 consecutive
`registerFactory` calls — and is the case that motivated the rule, from the same investigation
that produced the data-driven registry refactor in the sibling project **SwiftInferProperties**.

The follow-up is instructive: running [Parallel List Drift](parallel-list-drift.md) over the
same file showed that this hand-maintained list had **already** drifted from the
`PatternCategory` enum it mirrors, missing two of its fourteen entries. The fragile shape and
the realised defect were both present in the same twelve lines.

---
