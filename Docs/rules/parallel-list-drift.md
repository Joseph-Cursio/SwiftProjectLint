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
| [Parallel Enum Shape](parallel-enum-shape.md) | two lists agree **exactly** | cross-file |
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
3. **Runs of consecutive calls**, in two shapes.

   The first is a run of **registration calls** — the shape
   [Manual Registration List](manual-registration-list.md) detects, read for its contents.
   The distinguishing name is taken from the call's trailing closure when it has one
   (`registerFactory { _, _ in StateManagement(…) }` → `StateManagement`), otherwise from the
   first name-like argument (`register("fetch")` → `fetch`). Both rules share the verb
   vocabulary in `RegistrationVerb`, so a verb added for one is honoured by the other.

   The second is a run of **sibling calls whose actions each name a distinct case**:

   ```swift
   Button("Rules")   { selection = .rules }
   Button("Reports") { selection = .reports }
   ```

   A menu built this way is an enumeration transcribed by hand. There is no verb to gate on and
   none is needed, because the leading-dot member is its own signal — this is not "any run of
   calls with the same callee", which would read every repeated view builder as a roster.

   **Only the action closure is searched, never the arguments.** A roster entry is what the item
   *does*, not how it is *styled*. Reading arguments too collected `.red`, `.green` and
   `.primary` out of lists of summary tiles, so two unrelated views drawing four tiles apiece
   paired on three shared colour names and reported drift against each other — two false
   positives, both gone once arguments were excluded. An action naming two members contributes
   nothing, since it cannot supply one entry without choosing arbitrarily between them.

   This carrier exists because of a defect the rule could not see. A title menu was eleven
   `Button`s against a twelve-case enum and silently omitted one destination, reachable from the
   sidebar and nowhere else. Written as `[.rules, .reports, …]` this rule reported it and named
   the missing case; written as eleven calls it saw nothing. Measured across the corpus, the
   carrier adds **no findings to code that does not have the defect** — 17 before, 17 after.

Names are **normalized** before comparison — lowercased with separators stripped — so
`UIPatterns`, `uiPatterns` and `"ui-patterns"` all compare equal. Messages quote the original
spelling.

**Phase 2 (`finalizeAnalysis`).** An inverted index yields candidate pairs sharing at least
**3** entries; all-pairs comparison is never performed. A pair fires when:

- the **longer** list has at least **4** entries,
- Jaccard similarity (`|A ∩ B| / |A ∪ B|`) is at least **0.6** but strictly below **1.0**, and
- if the deficient list is a **strict subset** of the other, similarity is at least **0.8**.

The length floor is deliberately applied only to the longer list. A list that has drifted
*down* to two or three entries is the deficient one, and gating on its own length would silence
exactly the finding worth reporting.

**Mutual divergence vs. strict subset.** The stricter subset floor is the rule's main precision
lever. When each list holds an entry the other lacks — *mutual divergence* — the two genuinely
diverged from a common state, which is strong evidence and needs only the base **0.6**. When one
list is wholly contained in the other — a *strict subset* — the evidence is weak: a curated "the
few we support" list is a subset of a canonical one by design, not by mistake. Requiring **0.8**
there means a subset fires only when it is missing about one entry of a substantial list (the
genuine "forgot to add the new entry" case), while a curated subset that omits a larger fraction
is suppressed. This was added after dogfooding surfaced 11 three-entry `.enumeration([...])`
value lists in a sibling project, each flagged at 0.75 against one four-entry canonical list —
all false positives.

Similarity of exactly 1.0 means the lists agree — no drift, and therefore
[Parallel Enum Shape](parallel-enum-shape.md)'s finding rather than this rule's. That rule
covers both carriers this one does: identical enums *and* identical literal lists. (It did not
always — the array half was added after dogfooding this rule surfaced two byte-identical copies
of `primitiveCarriers` that no rule in the suite could report.)

One issue is emitted **per list that is missing entries**, so a strict subset reports only at
the deficient side, while two lists each holding something the other lacks report twice — both
genuinely need fixing. When a list drifts against several counterparts (a stdlib type-name
list copied into four visitors pairs with all three siblings), only the **closest** counterpart
is named: the same fix resolves all of them, and any remainder re-surfaces on the next run.

#### Known limitations / false-positive posture
- **A deliberate subset can still read as drift when its coverage is high.** The 0.8 subset
  floor suppresses low-coverage curated subsets, but a curated "the ten we support" list that
  happens to cover most of a twelve-entry canonical one still fires. This is the rule's residual
  false positive and part of why it is `Info`. Suppress with
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

```swift
// A low-coverage strict subset (3 of 4 = 0.75) — a curated value list, not drift. Below the
// 0.8 subset floor, so it is suppressed.
let supported = ["YES", "YES_ERROR", "NO"]
let canonical = ["DEFAULT", "YES", "YES_ERROR", "NO"]
```

### Violating Examples
```swift
// TemplateKind.swift
enum TemplateKind { case header, body, footer, sidebar, hero, banner }

// Emitter.swift — a strict subset missing one of six (0.83, above the 0.8 floor). One issue,
// here: `banner` is missing.
let emitted = ["header", "body", "footer", "sidebar", "hero"]
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

#### Measured precision on that run

All 14 findings were read individually. They are roughly **10 distinct pairs** (four are the same
pair reported from both sides), of which **three are actionable**:

1. **`animationFactories`** — a real defect. `AnimationPerformanceVisitor` knew five SwiftUI
   animation factories and `HardcodedAnimationValuesVisitor` seven, so the duration check was
   silently blind to `.interactiveSpring(…)` and `.interpolatingSpring(…)`. Fixed by giving both
   rules one `AnimationFactory` list. This is the first real bug the rule found.
2. **`nonStableGeneratorTypes` vs `clockLikeTypeNames`** — a genuine disagreement: each holds
   something the other lacks (`Clock` vs `DispatchTime`) while describing the same concept.
3. **`osLogMethods` / `loggerLevelMethods`** — surfaced sideways. The real finding is that the
   two are byte-identical, which is [Parallel Enum Shape](parallel-enum-shape.md)'s job.

The remaining findings were all one false-positive class — a **deliberate subset**, several of
which the code named directly: `systemViews` excludes container views on purpose,
`conflictingModifiers` is "modifiers that conflict with `.accessibilityHidden`" (so cannot
contain it), and `primitiveCarriers` is naturally a subset of the Equatable stdlib types.

#### The subset tightening

That deliberate-subset class was the rule's dominant false positive, and it drove the **0.8
strict-subset floor** (see Phase 2 above). A three-repo sweep before and after the change:

| Repo | Drift before | after | note |
|---|---|---|---|
| SwiftCompilerFlagStudio | 11 | **0** | 11 three-entry `.enumeration([...])` value lists, all 0.75 subset FPs |
| SwiftProjectLint | 13 | **8** | dropped `systemViews`, `conflictingModifiers`, the `primitiveCarriers`/Equatable pair |
| SwiftLintRuleStudio | 2 | **2** | one genuine *mutual-divergence* pair (`modeledReservedKeys` vs `defaultTopLevelKeyOrder`) — unaffected |

The eight that survive on SwiftProjectLint are mutual divergences and near-complete subsets
(`registerAll` at 0.86, the logging lists at 0.82). The one real finding in RuleStudio is
mutual and never depended on the subset path. So the floor removed a whole noise class without
touching the signal — precision rose on all three codebases at once.

Read each surviving finding before acting; it remains `Info`. Its exact-match sibling still
scores better — five for five on this codebase — because "these lists agree exactly" has far
fewer innocent explanations than "these lists nearly agree."

---
