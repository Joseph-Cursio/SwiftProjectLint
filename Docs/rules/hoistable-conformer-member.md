[← Back to Rules](RULES.md)

## Hoistable Conformer Member

**Identifier:** `Hoistable Conformer Member`
**Category:** Architecture
**Severity:** Info *(opt-in)*

### Rationale
When several types conform to the same protocol `P` and each carries an *identical*
implementation of some method or computed property — one that reads only `P`'s requirements
— that implementation is begging to be a single default on `extension P`. Leaving a copy in
each type means every change has to be made N times and the copies drift. Hoisting it gives
the behavior one home, available to every present and future conformer for free.

This is the behavioral inverse of [Could Adopt Protocol](could-adopt-protocol.md). That rule
finds a type whose *shape* matches a protocol it has not adopted. This rule starts from types
that have *already* adopted a protocol and asks whether their duplicated *behavior* belongs on
it. [Duplicate Struct Shape](duplicate-struct-shape.md) and
[Shared Domain-Enum Field](shared-domain-enum-field.md) cover the missing-*structure* cases;
this is the missing-*default-implementation* case.

### Discussion
`HoistableConformerMemberVisitor` is cross-file: the conformers and the protocol usually live
in different files, so a single-file linter never sees the duplication.

The visitor proceeds in two phases:

1. **Collect.** Record each protocol's requirement names and the members provided by its
   extensions; and, per concrete type (aggregated across its primary declaration *and* its
   extensions), record its conformances, all member names, and every *hoistable member* — an
   instance method with a body, or a computed instance property. For each it captures a
   normalized body (whitespace stripped, the optional `self.` receiver dropped) and the set of
   identifiers the body references. Stored properties, `static`/`class`/`lazy` members are
   excluded.

2. **Group and report.** Group members by `(signature, normalized body)`. A group spanning at
   least `minimumTypes` (default **3**) distinct types fires once per type when a common
   protocol `P` qualifies as a hoist target.

#### When a protocol qualifies as the hoist target
All four conditions must hold, so the suggested refactor actually compiles and is meaningful:

1. **Every owner conforms to `P`.** It must be a shared abstraction, not one type's protocol.
2. **The body touches only `P`'s requirements** — and at least one of them. The referenced
   *instance members* (identifiers that name a member of an owning type) must all be `P`
   requirements; if the body reaches for any other stored field or helper, the default
   implementation would not compile in `extension P`, so the rule stays silent. Requiring at
   least one requirement reference keeps it from firing on constant utility methods that merely
   coexist on conformers.
3. **The member is not itself a requirement of `P`.** A type fulfilling a requirement is the
   normal contract; turning it into a default is a different change (it alters what `P`
   demands), so v1 only factors out *incidental* shared behavior.
4. **No protocol extension already provides it.** If `extension P` already declares the member,
   the duplication is redundant *overrides* — a different smell — and "hoist it" is the wrong
   advice. This is also what makes the rule fall silent once the member has been hoisted.

When several protocols qualify, the most specific (fewest requirements) is reported.

#### Known limitations and false positives
- **Exact bodies only.** The grouping is on identical normalized text; near-duplicates
  (a reordered `||`, a renamed local) do not cluster. This biases hard toward precision.
- **Syntactic reference check.** "Instance member the body touches" is approximated by
  intersecting the body's identifiers with the owners' member names. Over-collection only ever
  makes the compile guard *stricter* (a false negative), never looser, so a reported hoist is
  safe to perform — but a deliberately type-specific implementation that merely *looks*
  identical may be suggested for hoisting. The rule is `Info` and opt-in for that reason;
  suppress per-type with `// swiftprojectlint:disable Hoistable Conformer Member`.
- **Mixed accessor styles.** A computed property written `{ … }` in one type and `{ get { … } }`
  in another will not cluster (different normalized body).

#### Scope note
This rule covers the *member-on-the-conformer* shape of duplication. It deliberately does not
attempt the *call-site* shape — repeated `collection.sorted { … }` / `Dictionary(grouping:)`
closures that could become `extension Sequence where Element: P` helpers — which requires
resolving the element type of each receiver and is tracked as a separate, higher-risk effort.

### Non-Violating Examples
```swift
// Already hoisted — the default lives once on the protocol, conformers carry nothing.
protocol Named {
    var rawKey: String { get }
    var name: String { get }
}
extension Named {
    func matches(_ query: String) -> Bool { rawKey.contains(query) || name.contains(query) }
}

struct Alpha: Named { let rawKey: String; let name: String }
struct Beta:  Named { let rawKey: String; let name: String }
```

```swift
// The body reaches a stored field (`tag`) that Named does not require, so it cannot move to
// extension Named. No finding.
struct Gamma: Named {
    let rawKey: String
    let name: String
    let tag: String
    func matches(_ query: String) -> Bool { rawKey.contains(query) || tag.contains(query) }
}
```

### Violating Examples
```swift
protocol Named {
    var rawKey: String { get }
    var name: String { get }
}

// Three conformers each implement `matches` identically using only Named's requirements.
// The rule fires on each, naming the others and the hoist target.
struct Alpha: Named {
    let rawKey: String
    let name: String
    func matches(_ query: String) -> Bool { rawKey.contains(query) || name.contains(query) }
}

struct Beta: Named {
    let rawKey: String
    let name: String
    func matches(_ query: String) -> Bool { rawKey.contains(query) || name.contains(query) }
}

struct Gamma: Named {
    let rawKey: String
    let name: String
    func matches(_ query: String) -> Bool { rawKey.contains(query) || name.contains(query) }
}
```

**Suggestion:** Move `matches(_:)` into `extension Named` as a default implementation and delete
the three per-type copies.

---
