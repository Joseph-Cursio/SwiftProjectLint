# Essay outline: Architectural Fitness Functions for Swift Apps

**Status:** Draft outline (2026-09-22). Not yet prose.
**Form:** standalone long-form essay. Could become a book chapter later.
**Audience:** iOS/macOS app developers: SwiftUI, usually a single app target,
small teams, often no dedicated architect. They know MVVM and `@MainActor`;
they probably haven't heard the term "fitness function".
**Target length:** 6–7k words, about a 25–30 minute read.

---

## The argument, in one paragraph

Most Swift apps have an architecture diagram and no way of knowing whether the
code still matches it. *Building Evolutionary Architectures* (Ford, Parsons,
Kua, Sadalage) calls the missing piece a **fitness function**: an automated
check that fails when the architecture drifts. In a single-target app the
compiler enforces almost none of your layering. `Domain/` and `Persistence/`
are just folders, so static analysis is the realistic way to protect them.
This essay shows how to do that. Then it covers three things app developers
especially need that the Java-centric literature barely mentions: **isolation**
(Swift 6 as a fitness function, and guarding its escape hatches), **coupling by
shape** (the enum and the array that should agree), and **fitness over time**
(using `git` to tell a copy-paste from a coincidence). It ends on the practical
limit: a check nobody reads protects nothing.

## Running example

**Checkout**, a single-target SwiftUI shop app:

```
Checkout/
├── App/            composition root (CheckoutApp, dependency wiring)
├── Domain/         Order, Money, PaymentMethod, OrderStore protocol
├── Persistence/    CoreDataOrderStore
└── Presentation/   CheckoutView, CheckoutViewModel, SettingsView
```

The rule docs already use these names, so the examples can be taken from them
almost unchanged. Build it as a real, small repo. It doubles as a fixture, and
readers can clone it and see every finding for themselves.

---

## 1. Opening: the diagram and the code (~600 words)

- **Hook:** a concrete drift story in Checkout. `CheckoutViewModel` starts
  calling `CoreDataOrderStore()` directly "just for now". It compiles, passes
  review, ships. Six months later, replacing Core Data with SwiftData touches 40
  files instead of 1.
- Nothing failed. The folders said "layers"; the build had no idea.
- **Introduce the term:** a fitness function is any objective, automated check
  on an architectural characteristic. Cite the book, paraphrase the definition,
  and keep the taxonomy to one sentence (atomic, triggered, static). App
  developers don't need the full grid.
- **Swift framing:** you already use fitness functions. The type checker and
  Swift 6's data-race checking are fitness functions; you just never had to
  write one yourself. The essay is about the characteristics the compiler
  *can't* see in a single-target app.

## 2. What the compiler already enforces, and where it stops (~700 words)

Kept short for this audience. It's a map, not a treatise.

| Mechanism | Protects | In a single-target app? |
|---|---|---|
| Types (`Money`, not `Double`) | Domain meaning | Yes |
| Access control | Encapsulation | Only `private`/`fileprivate`. `internal` is the whole app |
| SPM targets | Layer direction | **No**, there's one target |
| Swift 6 strict concurrency | Isolation | Yes, but with escape hatches (§4) |
| Static analysis | Whatever you configure | Yes, and it's what this essay is about |

- The honest aside: *if you modularise into SPM targets, the compiler takes
  over layer direction, and you should drop the equivalent lint rules.* The
  `architectural-boundary` doc says exactly this. One paragraph on
  `undeclared-target-dependency`, the one hole left even after
  modularising (SwiftPM doesn't check imports against `dependencies:`), as a
  teaser for readers who do split later.
- Rung-1 tie-in, one paragraph: `primitive-named-for-its-domain-type`. You have
  a `Money` type, but `func applyDiscount(amount: Double)` bypasses it.

## 3. Guarding the layers (~1,400 words)

The practical core for this audience.

- **Step 1: write the diagram down as config.** Checkout's three layers in
  `.swiftprojectlint.yml`.
- **Deny list:** `architectural-boundary`. `Domain/` may not import `CoreData`,
  `SwiftUI`, or use `URLSession`. Easy to write, goes stale.
- **Allow list:** `layer-dependency` with `may_depend_on`. `Presentation` may
  depend on `Domain`, and nothing else. It catches the opening hook's
  `CoreDataOrderStore()` without anyone predicting it. Like firewall rules,
  allow lists age better than deny lists.
- **Sidebar: a clean run must not look like a clean architecture.** A layer
  path that matches no files, a typo in `may_depend_on`, or layers that
  depend on each other in a cycle: the CLI warns about each one, because
  otherwise misconfiguration silently turns the check into a no-op. A lesson
  for any fitness function the reader writes.
- **The SwiftUI-specific smells**, one short paragraph each, framed as early
  warnings rather than architecture laws: `view-model-direct-db-access`
  (opt-in, because Apple's own SwiftData samples put `@Query` in views. Your
  fitness functions should match the architecture *you chose*),
  `god-view-model`, `too-many-environment-objects`, `singleton-usage`,
  `circular-dependency`.
- **Wiring it into CI:** one Xcode Cloud / GitHub Actions snippet, the CLI with
  `--threshold error`, and what a failed run looks like.
- **Alternative, briefly:** Harmonize writes the same rules as unit tests
  (`Harmonize.productionCode().classes().withNameEndingWith("ViewModel")…`).
  Show the Checkout layering rule in both forms, side by side. Code-as-rules
  vs. config-as-rules; the two work well together.

## 4. Isolation is architecture (~1,200 words)

- For an app, the main actor is an architectural boundary: UI state lives
  there, and anything crossing it must be `await`ed and `Sendable`. Swift 6
  enforces that contract at compile time, which makes it the strongest fitness
  function most app developers have. But it enforces less than it seems. It
  prevents data races, not slow work on the main thread (that's lint's job).
  And it only checks code that hasn't opted out through `@unchecked Sendable`,
  `nonisolated(unsafe)` or `@preconcurrency`.
- **Show the boundary in Checkout:** `CheckoutViewModel` (`@MainActor`) calls
  `await store.save(order)` on `CoreDataOrderStore` (an `actor`). The `await`
  is the seam, and `Order: Sendable` is the contract across it. Isolation
  decides which part of the app owns which state and what form data takes when
  it moves. That's architecture, not just thread safety.
- **Why it's the strongest rung:** it runs on every build, needs no config,
  blocks rather than reports, and uses real type information. Evidence from the
  sample: the clean app's first build failed on a `static let` holding an
  `NSManagedObjectModel`, a hazard nobody wrote a rule for.
- **What the compiler doesn't check: where slow work runs.** `Data(contentsOf:)`
  in a `@MainActor` view model compiles cleanly. It's a hang, not a race, and a
  hang isn't a type error. Swift 6.2 makes this more pressing: new Xcode 26 app
  targets default to main-actor isolation (SE-0466), so unannotated code
  lands on the main actor unless marked `@concurrent` or moved into an actor.
  This is the lint side of the same boundary: `synchronous-network-call`,
  `thread-sleep`, `dispatch-semaphore-in-async`,
  `expensive-operation-in-view-body`.
- **Escape hatches turn a proof into a promise.** Each one tells the compiler
  to stop checking, and afterwards it says nothing, ever again:
  `unchecked-sendable` (and why a lock-guarded type *isn't* flagged: a real
  safety mechanism is present), `nonisolated-unsafe`, `preconcurrency-import`,
  `preconcurrency-conformance`. Also mention `MainActor.assumeIsolated` (a
  runtime trap instead of a compile-time proof) and per-target Swift 5 mode.
- **They're the path of least resistance.** In the sample, the compiler's own
  diagnostic for the `static let` suggested `@preconcurrency import CoreData`.
  The escape hatch was offered as *the fix*. Take it under deadline and the
  error goes away; the race doesn't. `essay/s4-escape-hatch` shows the end
  state: an unguarded dictionary in `ReceiptCache: @unchecked Sendable` that
  builds cleanly.
- **So the fitness function isn't "are there data races?"** The compiler
  answers that wherever it's allowed to. It's "how many places have we told
  the compiler not to check, and is that number going up?" That's the question
  the ratchet below answers.
- **App-specific isolation rules:** `main-actor-missing-on-ui-code`,
  `observable-main-actor-missing`, `task-in-on-appear`,
  `fire-and-forget-task`, `swallowed-task-error`.
- **For readers still in Swift 5 mode:** `global-actor-mismatch` finds the
  crossings strict mode will reject, *before* you turn it on.
- **The ratchet.** You can't remove every escape hatch today; you can refuse to
  add new ones. The CLI has **no baseline feature**, so show it as a ~10-line CI
  script: `--format json`, count the escape-hatch findings, compare with a
  committed number, fail if it went up. (Leave it as a script; the essay
  doesn't need a new feature. Optionally mention a baseline flag as future work.)

## 5. The enum and the array that should agree (~1,100 words)

- **Hook in Checkout:** `enum PaymentMethod { case card, paypal }` in `Domain/`,
  and `let supportedMethods = ["card", "paypal"]` in `SettingsView`. Add
  `.applePay` to the enum. The settings screen doesn't offer it. No compile
  error, no test failure, and a support ticket three weeks later.
- This is coupling that no import graph shows: two places that *enumerate the
  same things*.
- One hazard, three stages, three rules:

  | Stage | Rule | Message to the reader |
  |---|---|---|
  | Fragile shape | `manual-registration-list` | This list will lose an entry one day |
  | Duplicate concept | `parallel-enum-shape` | They agree now, so consolidate while it's cheap |
  | Realised drift | `parallel-list-drift` | They *almost* agree, and that's a bug today |

- The fix menu, shown on Checkout: derive the array from the enum
  (`CaseIterable`), and the whole class of bug disappears.

## 6. Fitness over time: what `git` knows that the code doesn't (~1,100 words)

The essay's most original section. Keep the story concrete.

- A snapshot can't tell *copy-paste* from *coincidence*, or *deliberate
  divergence* from *forgot the other copy*. Show the five-verdict table:
  unify, bridge + annotate, suppress, derive, fix drift. Same signal, five
  correct answers.
- **The empty pickaxe.** One entry missing from one list and present in its
  sibling. `git log -S'"UInt32"' -- PartitionPairing.swift` returns nothing, so
  the entry was never added and later removed. It was simply never added, and
  adding it is safe. "An empty pickaxe is not a null result; it is the answer."
  Recast the example on Checkout (`.applePay` missing from the array) so the
  reader can run the same command on the sample repo; mention that the
  technique was first used on a real codebase.
- A generalisable habit for app teams: **before "fixing" an asymmetry, ask
  history whether it was deliberate.** One command, zero tooling.
- The design's later ideas (recorded sync contracts enforced at edit time), in
  one paragraph, clearly labelled as an idea, not a feature.

## 7. A check nobody reads protects nothing (~900 words)

- The book asks for *objective* assessment. In practice the stricter test is
  whether anyone reads the output.
- **Precision is a feature:** `manual-registration-list` went from 5 of 23
  findings actionable to 5 of 5 after one exclusion (renderers building output
  line by line). Show the before/after.
- **The unread finding:** the linter's own `lossy-struct-rebuild` rule flagged
  a real bug in the linter itself on a default run, and nobody read it. That's
  a signal-to-noise failure, not a detection failure. Self-deprecating, and
  more persuasive for it.
- **Practical guidance for an app team:**
  - Start with 3–5 rules that encode *your* diagram, not every rule available.
  - Info for early warnings, warning for policy, error only for rules you'd
    stop a release for.
  - Treat each suppression as a recorded architectural exception:
    `swiftprojectlint-suppression` reports them, so they get reviewed.

## 8. Closing: a short starter kit (~500 words)

- **The Monday-morning list:**
  1. Draw your layers; write them as `may_depend_on`.
  2. Turn on the escape-hatch rules and commit today's count as the ratchet.
  3. Find your enum/array pairs (`parallel-enum-shape`, `parallel-list-drift`)
     and derive one from the other.
  4. Before you "fix" an asymmetry, run `git log -S`.
- **Pointer, not a section:** writing your own rule (visitor, registrar, doc,
  tests) links to the project's docs. The how-to would double the essay's
  length and lose this audience.
- **Last paragraph:** the bridge to behaviour. Lint rules protect structure;
  tests, and especially property-based tests, protect behaviour. Both are
  fitness functions. One sentence pointing to `pbt-book`.

---

## Cut from the chapter version, and why

| Cut | Reason |
|---|---|
| Full strength-ladder table and the full taxonomy | Too theoretical for app developers. §2 keeps a compact map |
| Multi-target / server depth (`unused-target-dependency`, local packages) | Wrong audience. One teaser paragraph remains |
| "Writing your own rule" section | Becomes a link. It's a separate tutorial |
| `non-injected-nondeterminism` four-fault story | Good, but a testability story. Save it for `pbt-book` |
| Coupling-smell tour (`law-of-demeter`, `fat-protocol`…) | Only the SwiftUI-relevant subset stays |

## To do before drafting

| Item | Status |
|---|---|
| Build the Checkout sample repo with one deliberate violation per section | **Done** (2026-09-22): [Joseph-Cursio/Checkout](https://github.com/Joseph-Cursio/Checkout), `main` plus five `essay/` branches |
| Run the CLI on it and capture real output for every snippet | **Done.** Each branch gives exactly its intended finding. See the notes below |
| Ratchet script (`--format json` + count + compare) | **Done**: `scripts/ratchet.sh`. No baseline feature exists in the CLI |

### Found while building the sample (use in the essay)

- **§4 opener, for free:** the first build of the clean app failed under Swift 6.
  A `static let` holding an `NSManagedObjectModel` isn't concurrency-safe, and
  the compiler suggested `@preconcurrency import CoreData`. That's an escape
  hatch offered as the fix. The right fix was a factory function.
- **§3 deny vs. allow, shown by real output:** on `essay/s3-layer-violation`,
  `Layer Dependency` reports `CoreDataOrderStore()` in the view model;
  `Architectural Boundary`, with its deny list, stays silent.
- **§5 thresholds matter:** with four payment methods nothing fired. The array
  carrier needs ≥ 5 entries (short lists coincide too often). The sample uses five.
- **§7 governance point:** the drift on `essay/s5-drift` is a real bug, but it's
  `info`, so CI passes. Suppressing it (`essay/s7-suppression`) produces a
  *warning*, which fails CI. So silencing a finding is stricter than ignoring
  it. Decide whether the essay promotes `Parallel List Drift` to `warning` via
  `rules:` severity overrides, and say why.
- **Possible rule polish:** for an enum + array pair, `Parallel Enum Shape`
  suggests "consolidate into one enum". The better fix is deriving the array
  from `PaymentMethod.allCases`.
| Harmonize version of the §3 rule, compiled and run | To do |
| Check the book's definition and terms against the 2nd edition | To do |
| Decide where it's published (blog, Swift forums, Medium, project site) | Open |
