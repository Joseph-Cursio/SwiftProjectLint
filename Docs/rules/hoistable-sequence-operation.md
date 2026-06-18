[← Back to Rules](RULES.md)

## Hoistable Sequence Operation

**Identifier:** `Hoistable Sequence Operation`
**Category:** Architecture
**Severity:** Info *(opt-in)*

### Rationale
The same `collection.sorted { … }` or `collection.filter { … }` closure copy-pasted across
call sites is duplicated behavior keyed on a type's shape. When the closure reads only members
that a protocol `P` guarantees, and the collections hold conformers of `P`, that closure can
become a single `extension Sequence where Element: P` helper — `things.sortedByCategory()` —
written once and reused. This rule surfaces those candidates.

It is the call-site complement of [Hoistable Conformer Member](hoistable-conformer-member.md):
that rule hoists a duplicated *member* onto `extension P`; this one hoists a duplicated
*operation over a collection* onto `extension Sequence where Element: P`. Together they cover
the two shapes of "behavior that a protocol could own."

### Discussion
`HoistableSequenceOperationVisitor` is cross-file: the duplicated closures live in different
files, and the protocol they relate to in another.

The visitor proceeds in two phases:

1. **Collect.** Record each protocol's property requirement names. For every closure passed to
   an element-wise `Sequence` higher-order method (`sorted`, `sort`, `filter`, `min`, `max`,
   `first`, `last`, `contains`, `firstIndex`, `lastIndex`, `partition`, `allSatisfy`, `drop`,
   `prefix`) or to `Dictionary(grouping:by:)`, record the set of members accessed off the
   closure's parameter (`$0.category`, `a.name`) and a normalized body.
2. **Group and report.** Group sites by closure body. A group of at least `minimumSites`
   (default **2**) whose member set has at least `minimumMembers` (default **2**) members, and
   is a subset of some project protocol's requirements, fires once per site. The most specific
   protocol (fewest requirements) is named.

#### Why the two-member floor — and why it is a heuristic
A syntactic linter cannot resolve the *element type* of `things` in `things.sorted { … }`, so
it cannot prove `Element: P`. It can only observe which members the closure reads. A
[measurement](../could-hoist-to-protocol-extension-rule-design.md) over real codebases made the
trade-off concrete:

| Filter | Precision |
|---|---|
| any closure whose members subset a protocol (`\|S\| >= 1`) | ~33% |
| …restricted to repeated closures | ~47% |
| **two-or-more-member access (`\|S\| >= 2`)** | **100% (on the sample)** |

The failure mode at one member is coincidence: `name` and `rawKey` are members of many
unrelated types and subset most protocols, so `targets.first { $0.name == … }` matches a
protocol whose conformers it has nothing to do with. A two-member set like `{ category, name }`
is distinctive enough that, in practice, only genuine conformers access it together. This is
still a **heuristic**, not a proof — hence `Info`, opt-in, and a conditionally-phrased
suggestion ("*if* these collections hold `Element: P`").

#### Known limitations
- **Single-key operations are out of scope.** `Dictionary(grouping:) { $0.category }` is a real
  hoist candidate but only reads one member, so it is indistinguishable from a coincidental
  single-member match and is not reported.
- **No type resolution.** A two-member match over a collection whose element does *not* conform
  to the matched protocol is a false positive. The conditional suggestion makes that case a
  no-op for the reader rather than a wrong instruction. Suppress with
  `// swiftprojectlint:disable Hoistable Sequence Operation`.
- **Exact closure text.** Sites cluster by normalized body; a reordered comparison or renamed
  parameter splits the group.

### Non-Violating Examples
```swift
// Single-member closure: `name` subsets many protocols by coincidence, so this is not
// reported even when repeated.
func newest(_ targets: [BuildTarget]) -> BuildTarget? {
    targets.max { $0.name < $1.name }
}
```

```swift
// Only one occurrence — there is no duplication to factor out.
func ordered(_ flags: [Flag]) -> [Flag] {
    flags.sorted { ($0.category, $0.name) < ($1.category, $1.name) }
}
```

### Violating Examples
```swift
protocol BuildSettingIdentity {
    var rawKey: String { get }
    var name: String { get }
    var category: String { get }
}

// The same two-key sort closure at several sites, each over a collection of conformers.
func sortedFlags(_ flags: [CompilerFlag]) -> [CompilerFlag] {
    flags.sorted { ($0.category, $0.name) < ($1.category, $1.name) }
}

func sortedOverrides(_ overrides: [SettingOverride]) -> [SettingOverride] {
    overrides.sorted { ($0.category, $0.name) < ($1.category, $1.name) }
}

func sortedDiffs(_ diffs: [SettingDiff]) -> [SettingDiff] {
    diffs.sorted { ($0.category, $0.name) < ($1.category, $1.name) }
}
```

**Suggestion:** Add `extension Sequence where Element: BuildSettingIdentity { func
sortedByCategoryThenName() -> [Element] { sorted { ($0.category, $0.name) < ($1.category,
$1.name) } } }` and replace the call sites with `flags.sortedByCategoryThenName()`.

---
