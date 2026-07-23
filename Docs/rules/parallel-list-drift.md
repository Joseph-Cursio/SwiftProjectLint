[← Back to Rules](RULES.md)

## Parallel List Drift

**Identifier:** `Parallel List Drift`
**Category:** Architecture
**Severity:** Info

### Rationale
Two lists of names that *almost* agree are usually one enumeration maintained in two places,
where one copy has fallen behind. Adding a case to an enum and forgetting the array that
mirrors it — or registering a new factory without adding its category — is not a compile
error, so the omission survives review and ships. The near-match is the evidence: lists that
share nine of eleven entries did not arrive at that overlap by chance.

This rule completes a trio:

| Rule | Fires when | Scope |
|---|---|---|
| [Manual Registration List](manual-registration-list.md) | a list is built by hand, entry by entry | single file |
| [Parallel Enum Shape](parallel-enum-shape.md) | two enums agree **exactly** | cross-file |
| **Parallel List Drift** | two lists agree **almost** | cross-file |

Manual Registration List flags the hazardous *shape* before it costs anything. Parallel Enum
Shape flags a concept modeled twice while the copies still agree. This rule flags the case
where the hazard has already been realised — and is therefore the one that reports an actual
present-tense defect rather than a refactoring opportunity.

### Discussion
`ParallelListDriftVisitor` runs cross-file, because the two copies of a list are almost never
in the same file.

**Phase 1 (walk).** It catalogs every *name list*, read from three carriers:

1. **`enum` case names.** Unlike Parallel Enum Shape, associated values are not
   disqualifying — this rule compares the roster of names, and `case failure(Error)` still
   contributes the name `failure` that a parallel list is expected to carry.
2. **Array literals** whose elements are uniformly name-like: single-segment string literals
   (`"state-management"`), leading-dot members (`.stateManagement`), or type references
   (`StateManagement`). A mixed-kind array is a data structure, not an enumeration, and is
   skipped. The list is named after the binding it belongs to (`let packs = [...]` → `packs`).
3. **Runs of consecutive registration calls** — the shape
   [Manual Registration List](manual-registration-list.md) detects, read for its contents.
   The distinguishing name is taken from the call's trailing closure when it has one
   (`registerFactory { _, _ in StateManagement(…) }` → `StateManagement`), otherwise from the
   first name-like argument (`register("fetch")` → `fetch`). Both rules share the verb
   vocabulary in `RegistrationVerb`, so a verb added for one is honoured by the other.

Names are **normalized** before comparison — lowercased with separators stripped — so
`UIPatterns`, `uiPatterns` and `"ui-patterns"` all compare equal. Messages quote the original
spelling.

**Phase 2 (`finalizeAnalysis`).** An inverted index yields candidate pairs sharing at least
**3** entries; all-pairs comparison is never performed. A pair fires when:

- the **longer** list has at least **4** entries, and
- Jaccard similarity (`|A ∩ B| / |A ∪ B|`) is at least **0.6** but strictly below **1.0**.

The floor is deliberately applied only to the longer list. A list that has drifted *down* to
two or three entries is the deficient one, and gating on its own length would silence exactly
the finding worth reporting.

Similarity of exactly 1.0 means the lists agree — no drift. For enum/enum pairs that is
[Parallel Enum Shape](parallel-enum-shape.md)'s finding, not this rule's.

One issue is emitted **per list that is missing entries**, so a strict subset reports only at
the deficient side, while two lists each holding something the other lacks report twice — both
genuinely need fixing. When a list drifts against several counterparts (a stdlib type-name
list copied into four visitors pairs with all three siblings), only the **closest** counterpart
is named: the same fix resolves all of them, and any remainder re-surfaces on the next run.

#### Known limitations / false-positive posture
- **A deliberate subset is indistinguishable from drift.** A curated "the five we support" list
  next to a twelve-case enum reads as an eight-entry omission. This is the rule's dominant
  false positive and the reason it is `Info`. Suppress with
  `// swiftprojectlint:disable Parallel List Drift`.
- **Test and fixture files are excluded entirely** — a test enumerating a deliberate subset is
  the most common instance of the above.
- **Very common names are ignored when generating candidate pairs.** A name appearing in more
  than **40** lists is treated as a generic word (`name`, `value`) rather than a distinguishing
  entry. This bounds pair generation, but means two lists whose *entire* overlap consists of
  such names are never paired.
- **Normalization is spelling-only.** It collapses case and separators; it does not strip
  affixes, so a list of `StateManagementRegistrar`-style names will not match `stateManagement`.
- **No type resolution.** Lists are matched on name overlap alone, so two genuinely unrelated
  enumerations that happen to share vocabulary (`{read, write, execute}` as both file
  permissions and database operations) can pair.
- Nested enums are named by their simple name (`Severity`, not `Outer.Severity`).

### Non-Violating Examples
```swift
// Exact agreement — no drift. (Parallel Enum Shape's territory, not this rule's.)
enum Pack { case alpha, bravo, charlie, delta }
let names = ["alpha", "bravo", "charlie", "delta"]
```

```swift
// Incidental overlap: shares 3 of 11 union entries (Jaccard 0.27), below the 0.6 floor.
enum Pack { case alpha, bravo, charlie, delta, echo, foxtrot, golf }
let unrelated = ["alpha", "bravo", "charlie", "xray", "yankee", "zulu", "whiskey"]
```

```swift
// A mixed-kind array is data, not an enumeration of names.
let mixed = ["alpha", .bravo, "charlie", 42, "delta"]
```

### Violating Examples
```swift
// TemplateKind.swift
enum TemplateKind { case header, body, footer, sidebar }

// Emitter.swift — one issue, here: `sidebar` is missing.
let emitted = ["header", "body", "footer"]
```

```swift
// PatternCategory.swift
enum PatternCategory { case stateManagement, performance, security, accessibility, idempotency }

// BuiltInRules.swift — one issue, here: `idempotency` is missing.
SourcePatternRegistry.registerFactory { registry, visitorRegistry in
    StateManagement(registry: registry, visitorRegistry: visitorRegistry)
}
SourcePatternRegistry.registerFactory { registry, visitorRegistry in
    Performance(registry: registry, visitorRegistry: visitorRegistry)
}
SourcePatternRegistry.registerFactory { registry, visitorRegistry in
    Security(registry: registry, visitorRegistry: visitorRegistry)
}
SourcePatternRegistry.registerFactory { registry, visitorRegistry in
    Accessibility(registry: registry, visitorRegistry: visitorRegistry)
}
```

**Suggestion:** Add the missing entries, or — better — derive one list from the other so they
cannot drift again. When the counterpart is an enum, iterating `CaseIterable` replaces the
hand-maintained copy outright and makes the next omission a compile error.

#### Real-world discovery
Run against SwiftProjectLint itself (`--include-nested-packages`), the rule reports **14**
findings, led by the case that motivated it:

> `SourcePatternRegistry.registerFactory(…)` (registration run, 12 entries) agrees with
> `PatternCategory` (enum, PatternCategory.swift:23) on 12 entries but is missing 2:
> `idempotency`, `other`.

Both omissions turn out to be intentional — `idempotency` factories are registered by a
separate package, and `other` is a catch-all with no factory — which is the rule working as
designed: it cannot know intent, so it surfaces the discrepancy for a human to confirm or fix.
`Tests/CoreTests/CrossFileAnalysis/ParallelListDriftDogfoodTests.swift` pins this finding
against the checked-in sources, so if the two lists are ever reconciled the test records it.

Other findings on the same run were less benign, including three separately-maintained copies
of a logging-method-name list (`loggingMethodNames`, `osLogMethods`, `loggerLevelMethods`), two
of them missing `verbose` and `warn`, and a `systemViews` array 11 entries behind the
`SwiftUIViewType` enum it mirrors.

---
