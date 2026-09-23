# Essay outline: SOLID, Checked

**Working title:** *SOLID, Checked: What a Linter Can and Can't Tell You About
Swift Design*
**Status:** Draft outline (2026-09-22). Not yet prose.
**Form:** standalone essay, a companion to *Architectural Fitness Functions for
Swift Apps*. It should be readable without having read that one.
**Audience:** the same: iOS/macOS app developers who know SOLID as a checklist,
have probably had it cited at them in review, and have never asked which parts
of it a tool can check.
**Target length:** 5–6k words.
**Sample code:** [Joseph-Cursio/Checkout](https://github.com/Joseph-Cursio/Checkout),
with new `solid/` branches (see *Sample repo plan*).

---

## The argument, in one paragraph

SOLID is usually taught as five equal principles. Try to *check* them and they
stop looking equal. Dependency inversion is almost fully checkable from syntax.
Interface segregation mostly is. Open/closed needs rethinking before it applies
to Swift at all. Single responsibility can only be approximated, because a
"responsibility" is a judgement about meaning. Liskov substitution can barely be
seen statically, because it's about behaviour, and it's where static analysis
has to hand over to property-based testing. Going through the principles in that
order, from most checkable to least, shows what each principle actually
*claims*. It also gives a practical rule: automate the checkable parts, and
stop pretending a line count measures responsibility.

## Structure

The sections run from **most checkable to least**, the reverse of the acronym,
and the essay says so up front. That ordering is the essay's thesis, so the
reader should notice it.

A coverage scale used throughout, one per section header:

| Principle | Static coverage | Why |
|---|---|---|
| Dependency inversion | Strong | It's about *which names appear where*, and syntax shows names |
| Interface segregation | Moderate | Size is visible; *who uses which part* needs cross-file analysis |
| Open/closed | Partial, and reframed | Swift's closed enums change what a violation is |
| Single responsibility | Proxy only | A responsibility is a meaning, not a shape |
| Liskov substitution | Outline only | It's a behavioural contract; the full check is dynamic |

---

## 1. Opening: five principles, five different kinds of claim (~500 words)

- **Hook:** a code review comment everyone has received: "this violates SRP."
  Ask: how would you know? What would you measure? If two reviewers disagree,
  what settles it?
- SOLID as usually taught: five principles, equal weight, applied by judgement.
- **The move:** treat each principle as a *claim about code*, and ask what
  evidence would confirm or refute it. Some claims are about names (checkable).
  Some are about meaning (not checkable). One is about behaviour (checkable,
  but not by reading code).
- Say where the rule list comes from: SwiftProjectLint's rule reference now
  groups its rules by SOLID principle, and the grouping came out lopsided. The
  essay is about why.
- State the order and what it means.

## 2. Dependency inversion: strong, and it pushes both ways (~1,000 words)

**Claim:** high-level policy shouldn't depend on low-level detail; both should
depend on abstractions. It's checkable because it's about *which names appear
where*.

- **Checkout's shape:** `OrderStore` (protocol) lives in `Domain/`;
  `CoreDataOrderStore` implements it in `Persistence/`; `App/` wires them
  together. The inversion is the fact that `Domain` *owns* the protocol.
- **Rules that push toward abstraction:** `Layer Dependency`, `Direct
  Instantiation`, `Concrete Type Usage`, `Missing Dependency Injection`,
  `Singleton Usage`, `Unabstracted File IO`, `Non-Injected Nondeterminism`.
- **Rules that push back:** `Single Implementation Protocol`, `Mirror
  Protocol`, `Unused Protocol Abstraction`. Over-applied DIP produces
  "protocol soup": a `FooServiceProtocol` in front of every `FooService`, with
  nothing that ever substitutes. A rule set that only pushed one way would
  reward that.
- **Real finding from the sample:** a default run on Checkout reports `Direct
  Instantiation` at `CheckoutApp.swift:7`, the composition root, which is
  exactly where DIP says construction *belongs*. The rule does exempt
  composition roots, but it recognises them by shape (three or more services,
  or an `@main` type's `init()`/`main()`). Checkout's root is one service in a
  stored-property initializer, which is how most small apps look. Use it as a
  live example of the precision problem, and as a possible rule refinement
  (see *Follow-ups*).
- **Real tension in the sample:** the same default run reports `Protocol
  Naming Suffix` on `OrderStore` ("not suffixed with 'Protocol'"), which
  pushes *toward* the `FooProtocol` naming that `Mirror Protocol`'s doc
  names as the smell's signature. Either reconcile the two rules before
  publishing, or use the contradiction honestly: naming conventions are team
  choices, not principles, and belong in `enabled_only` decisions. **Decide
  which.**
- **Branch result, better than planned:** `solid/d-concrete-dependency`. The
  view model stores and takes `CoreDataOrderStore` instead of `any OrderStore`.
  The expected rule, `Concrete Type Usage`, **stays silent**: it deliberately
  exempts actors, on the grounds that hiding an actor behind a protocol loses
  the compile-time `await`. Instead, the two rules that push *back* fire:

  ```
  Sources/Checkout/Domain/OrderStore.swift:3: info: [Single Implementation Protocol]
    Protocol 'OrderStore' has only one conformer ('CoreDataOrderStore') —
    consider removing the abstraction.
  Sources/Checkout/Domain/OrderStore.swift:3: info: [Unused Protocol Abstraction]
    Protocol 'OrderStore' is conformed to by 1 type but never used as a type —
    no parameter, property, constraint, or existential references it.
  ```

  So on a dependency-inversion violation, the linter's advice is to **delete
  the abstraction**. Both findings are correct: once nothing depends on
  `OrderStore`, it *is* unused. What they can't know is which direction the
  fix should go, whether the view model should return to the protocol or the
  protocol should go. That's a design decision, and the rules only report the
  inconsistency. Use this as the section's central example: a linter can tell
  you the code and its abstractions disagree, not which one is right.
- **The actor exemption is a Swift-specific DIP tension worth a paragraph.**
  In Swift 6, isolation is part of a type's contract, and a protocol can drop
  it. But `OrderStore`'s requirements are all `async`, so calls through
  `any OrderStore` still need `await`, and the exemption's reason doesn't hold
  for this protocol. Present both sides, and note it as a possible rule
  refinement (see *Follow-ups*).

## 3. Interface segregation: moderate (~700 words)

**Claim:** clients shouldn't be forced to depend on methods they don't use.

- **What's checkable:** size. `Fat Protocol` reports 10+ requirements, and its
  doc cites ISP by name. `Too Many Environment Objects` is the SwiftUI form:
  a view that depends on four or more environment objects depends on far more
  than it uses.
- **What isn't, yet:** the principle is really about *use*. A 12-requirement
  protocol whose every client uses all 12 is fine; a 4-requirement one where
  each client uses a different one is not. That needs a cross-file "which
  requirements does each client call?" analysis. Name it as the principled
  version of the check, and say plainly it isn't implemented.
- **Swift-specific angle:** protocol composition (`Readable & Writable`) makes
  segregation cheap in Swift, so the cost of a fat protocol is harder to
  excuse than in languages without it.
- **Branch:** `solid/i-fat-store`. `OrderStore` grows to 10 requirements
  (lookup, cancel, refund, receipt text, CSV export, count, delete-all,
  analytics), which `CoreDataOrderStore` implements in an extension. Actual:
  `Fat Protocol`: "Protocol 'OrderStore' has 10 requirements — consider
  splitting into smaller protocols."

## 4. Open/closed, rethought for Swift (~900 words)

**Claim:** modules should be open for extension and closed for modification.

- **The complication:** Swift enums are *closed on purpose*. Add a case and the
  compiler lists every `switch` that needs updating. By the textbook
  definition, that's a violation: adding a feature modifies existing code. In
  practice it's the language's best feature for this problem.
  (This is the expression problem: enums make new operations cheap and new
  cases visible; protocols make new cases cheap and new operations hard.
  One paragraph, no more.)
- **The reframe:** in Swift, the violation isn't "a change requires
  modification". It's **"a change requires modification the compiler can't
  point to."**
- **Rules for exactly that:**
  - `String Switch Over Enum`: switching on `rawValue` loses exhaustiveness, so
    a new case falls silently into `default`;
  - `Parallel List Drift` and `Manual Registration List`: a hand-kept list
    doesn't learn about the new case (the `.applePay` story, told briefly with
    a pointer to the fitness-functions essay);
  - `Scattered Enum Mapping`: the same mapping copied into several `switch`es,
    so one change has to be made in N places.
- **Branch:** `solid/o-string-switch`. A receipt formatter switches on
  `paymentMethod.rawValue` with a `default:` arm. Adding `.applePay` then
  prints "Other" on the receipt. Actual: `String Switch Over Enum`: "Switch
  on '.rawValue' loses exhaustiveness checking — switch on the enum
  directly".

## 5. Single responsibility: proxies only (~900 words)

**Claim:** a module should have one reason to change.

- **Why it can't be checked:** "reason to change" is a statement about the
  future and about meaning. Two methods in a class share a responsibility if
  they'd change for the same business reason, and nothing in the syntax
  records business reasons.
- **What the rules measure instead:** size, as a proxy. `God View Model`
  (10 `@Published` properties, or 15 stored properties on an `@Observable`
  type), `Fat View`, `Large View Body`, `ViewBuilder Complexity`. Be honest:
  a large type often *does* have several responsibilities, but size is
  evidence, not proof, and a team that treats the threshold as the principle
  will split types in the wrong places to get under it.
- **The one rule that checks the principle directly:** `Boolean Control
  Coupling`. A `Bool` parameter whose body picks between two substantial code
  paths is, literally, one function doing two jobs, with the choice made by
  the caller. The rule doc cites Adam Tornhill's *Hidden Design Decisions —
  Refactoring Control Coupling*, whose fix is to replace the flag with a
  strategy: two named functions, or a protocol or closure passed in.
- **A better signal, outside the linter:** *change coupling*. Files or
  functions that always change in the same commits share a reason to change,
  whatever their size. `git log` records exactly the thing syntax can't. That
  links back to the fitness-functions essay's "fitness over time" section, and
  is a candidate for a future history-aware rule. Say so, without promising it.
- **Branch:** `solid/s-flag-parameter`. `placeOrder(isGift: Bool)` where
  the flag chooses between two substantial paths (wrap and ship to a
  recipient vs. ship to the buyer). Actual: `Boolean Control Coupling`
  (warning): "Boolean parameter 'isGift' selects between two code paths — this
  is control coupling (the caller decides which behavior runs)."

## 6. Liskov substitution: where static analysis hands over (~1,300 words)

The centrepiece.

**Claim:** anything that accepts a type must work with every subtype, or in
Swift, every *conformer*. It's a behavioural claim. Two types can have
identical signatures and different behaviour.

- **What static analysis can see:** its outline.
  - `Swallowed Injection Downcast`: a function accepts `any OrderStore`, then
    does `as? CoreDataOrderStore`. It's admitting that not every conformer can
    really stand in.
  - `Unconditional Trap` in a conformance: `fatalError("not supported")` is the
    textbook LSP violation. (The rule flags traps generally, not only in
    conformances. Say so.)
  - **Branch:** `solid/l-downcast`. The view model sets
    `canExportHistory = (store as? CoreDataOrderStore) != nil`. Actual:
    `Swallowed Injection Downcast`: "…this honors only one type and silently
    drops the rest (e.g. test doubles)". The message names test doubles
    itself, which sets up the next point.
- **What it can't see, from a real bug in the sample.** Checkout's
  `CoreDataOrderStore.recentOrders()` rebuilds each `Order` with `items: []`
  and `discount: nil`. Only the identifier and the payment method survive the
  round trip. It compiles, satisfies `OrderStore`'s signatures, and **no rule
  in a default run reports it** (checked: `Lossy Struct Rebuild` doesn't fire,
  because the order is built from an `NSManagedObject`, not rebuilt from
  another `Order`). And on the `essay/s3-layer-violation` branch, "reorder
  last" uses exactly that method, so reordering would silently produce an
  empty cart. **That bug was in the sample code all along, and it wasn't
  planted.** Lead with it.
- **Why it's an LSP bug:** an in-memory `OrderStore`, the kind every test
  suite has, *does* round-trip orders. So the tests pass against the fake and
  the app fails against the real one. The fake and the real store aren't
  substitutable. **Test doubles are where most app codebases break Liskov,
  and nobody checks them.**
- **The check that does work: a contract test, run against every conformer.**
  Write the protocol's laws once, as properties, and run them against each
  implementation:
  - *save-then-fetch round-trips:* for any generated order `o`,
    `save(o)` then `recentOrders()` contains an order equal to `o`;
  - *fetch doesn't invent:* everything returned was saved;
  - *idempotent save*, if that's the intended contract (a design decision the
    test forces you to make explicitly).
  One Swift Testing suite, parameterised over a `StoreKind` enum
  (`.inMemory`, `.coreData`), runs the first two laws with
  `propertyCheck`. (Idempotent save isn't written: the contract doesn't
  decide it yet, and the essay can say that writing laws forces the question.)
  **Actual result:** the in-memory store passes both laws; Core Data fails
  round-tripping, with the failing input shrunk automatically:

  ```
  ✘ Expectation failed: (fetched?.discount → nil) == (order.discount → DiscountCode(value: "B"))
  ↳ Failure occured with input Order(identifier: 00000000-0000-0000-0000-000000000000,
      items: [], paymentMethod: bankTransfer, discount: Optional(DiscountCode(value: "B"))).
    (shrunk down from Order(… items: [LineItem(name: "Pk", …), LineItem(name: "I8sYnTwACa", …)],
      … discount: Optional(DiscountCode(value: "B"))) after 3 iterations)
  ```

  The shrinker removed both line items and kept the discount, which shows the
  smallest input that still fails. The line-item loss is a second instance of
  the same bug, so describe the shrunk case as *one* minimal failure, not the
  whole defect. The random inputs differ per run, so re-capture with a
  `.fixedSeed(…)` before quoting.
- **Standard-library protocols have laws too.** `Money: Comparable, Hashable`:
  a wrong `<` or a `hash(into:)` that ignores a field breaks `sort`, `Set` and
  `Dictionary` in ways that look like UI bugs. SwiftPropertyLaws checks the
  standard protocols' laws (`checkHashablePropertyLaws(for:using:)`, the
  `@PropertyLawSuite` macro). One short example, then back to the domain
  protocol, which is the essay's point: *your* protocols have laws too,
  and nobody writes them down.
- **Branches:** `solid/l-contract-test` adds the test target,
  `InMemoryOrderStore`, the `Order` generator and the contract suite, which
  fails. `solid/l-contract-test-fixed` stores line items (JSON) and the
  discount code, and both laws pass for both stores (checked over five runs).
  The fix is small, so show its diff: the whole bug was two missing
  attributes. **Decided:** Checkout's `main` keeps the lossy store as the
  standing example.

## 7. Closing: what the lopsidedness teaches (~500 words)

- Put the coverage table back up. The pattern: principles about **names** are
  checkable; principles about **meaning** can only be approximated; principles
  about **behaviour** need tests, not linters.
- **Practical guidance:**
  1. Automate D and I, and review suppressions.
  2. Adopt the Swift reframing of O, and turn on the rules that catch
     invisible modification.
  3. Treat S findings as prompts for a conversation, never as verdicts, and
     don't split types to satisfy a threshold.
  4. Write contract tests for every protocol with more than one conformer,
     *especially* when one of them is a test double.
- **Last line direction:** SOLID was never five rules. It's one structural
  rule, one sizing heuristic, one language-dependent guideline, one judgement,
  and one behavioural contract. Knowing which is which is what lets you
  enforce the right ones.

---

## Sample repo plan

New branches in [Joseph-Cursio/Checkout](https://github.com/Joseph-Cursio/Checkout),
named `solid/…` so they don't mix with the `essay/…` branches:

**Built 2026-09-22** and pushed to
[Joseph-Cursio/Checkout](https://github.com/Joseph-Cursio/Checkout). The rules
live in `.swiftprojectlint-solid.yml`, added through Checkout PR #1, so the
fitness-functions essay's quoted output is unchanged. On `main`, that config
reports one finding: the `Direct Instantiation` false positive at the
composition root (Follow-up 1).

| Branch | Section | Change | Actual result |
|---|---|---|---|
| `solid/d-concrete-dependency` | §2 | View model takes `CoreDataOrderStore` | `Single Implementation Protocol` + `Unused Protocol Abstraction`; `Concrete Type Usage` silent (actor exemption) |
| `solid/i-fat-store` | §3 | `OrderStore` grows to 10 requirements | `Fat Protocol` |
| `solid/o-string-switch` | §4 | Receipt formatter switches on `rawValue` with `default:` | `String Switch Over Enum` |
| `solid/s-flag-parameter` | §5 | `placeOrder(isGift: Bool)` with two substantial arms | `Boolean Control Coupling` (warning) |
| `solid/l-downcast` | §6 | Injected `any OrderStore` downcast to `CoreDataOrderStore` | `Swallowed Injection Downcast` |
| `solid/l-contract-test` | §6 | Test target, in-memory store, `Order` generator, contract suite | `swift test` fails for Core Data only, with a shrunk counterexample |
| `solid/l-contract-test-fixed` | §6 | Core Data stores line items and discount codes | `swift test` passes for both stores |

Every branch builds. The contract-test branches add a test target and
`swift-property-based` 1.2.0 (the version SwiftProjectLint uses), with
`Package.resolved` committed.

## Follow-ups this outline surfaced (outside the essay)

1. **`Direct Instantiation` at a small composition root.** A single service
   created in a stored-property initializer of an `@main` type isn't
   recognised as the composition root. Consider exempting stored-property
   initializers on the `@main` type.
2. **`Protocol Naming Suffix` vs. `Mirror Protocol`.** One asks for
   `OrderStoreProtocol`, the other treats `FooServiceProtocol` as the smell's
   signature. Decide whether that's a real conflict or a documented team
   choice, and say so in both docs.
3. **Checkout's lossy `recentOrders()`.** Kept on Checkout's `main` as the
   §6 exhibit; fixed on `solid/l-contract-test-fixed`. Merging that branch
   fixes `main` whenever the essay no longer needs the bug.
4. **Interface segregation by use.** A cross-file rule that reports protocol
   requirements no client of a given conformer calls. This is the principled
   version of `Fat Protocol`. Idea only.
5. **`Concrete Type Usage`'s actor exemption.** Its reason is that a
   protocol would hide the actor's isolation contract. That doesn't hold when
   every requirement is `async` (callers still `await`), and where a
   requirement is synchronous, Swift 6 makes the actor satisfy it with a
   `nonisolated` member, so the trade-off is visible in the conformance anyway.
   Consider narrowing the exemption. Check against Swift 6.2's
   isolated-conformance rules (SE-0470) first.

## To do before drafting

| Item | Status |
|---|---|
| Build the `solid/` branches and capture real output | **Done** (seven branches, including the fix) |
| Add a test target and `swift-property-based` to Checkout for §6 | **Done**, on the contract-test branches only |
| Decide on a separate config file for the `solid/` branches | **Done**: `.swiftprojectlint-solid.yml` |
| Decide whether `main` keeps the lossy store | **Decided**: yes, as the standing example |
| Re-capture the §6 test output with a fixed seed, for a stable quote | To do |
| Decide the §2 naming-suffix question | Open |
