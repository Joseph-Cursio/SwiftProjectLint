# Architectural Fitness Functions for Swift Apps

*Draft 1, 2026-09-22. Outline:
[`architectural-fitness-functions-essay-outline.md`](architectural-fitness-functions-essay-outline.md).
Sample code: [Joseph-Cursio/Checkout](https://github.com/Joseph-Cursio/Checkout).
All [verify] items were checked on 2026-09-22; see the drafting notes.*

---

## 1. The diagram and the code

Here is a line of code that compiles, passes review, and ships:

```swift
// Just for now: read history straight from Core Data until the
// order-history API lands.
func reorderLast() async {
    let history = CoreDataOrderStore()
    if let last = try? await history.recentOrders().first {
        order.items = last.items
    }
}
```

It lives in `CheckoutViewModel`, in the `Presentation/` folder of a small
SwiftUI shop app. Somewhere there's a diagram of that app showing three boxes:
`Presentation` depends on `Domain`, `Persistence` depends on `Domain`, and
nothing in `Presentation` knows that Core Data exists. The line above breaks
that diagram. Nothing complains. The folder is called `Presentation/`, but to
the compiler it's just a folder, and the whole app is one module in which every
type can see every other.

One line like this costs nothing. The trouble is that it's a *precedent*. The
next "just for now" cites it, and the one after that doesn't need to. By the
time you want to replace Core Data with SwiftData, the persistence framework is
named in the view layer in a dozen places. You find them by grepping, not by
reading the diagram, because the diagram stopped being true a long time ago and
nobody noticed when.

The fix isn't more discipline. It's giving the diagram a way to fail.

*Building Evolutionary Architectures* by Neal Ford, Rebecca Parsons, Patrick
Kua and Pramod Sadalage has a name for that: an **architectural fitness
function**, meaning any mechanism that gives an objective assessment of whether
the system still has some architectural characteristic you care about.
The term comes from evolutionary computing, where a fitness function decides
which variants survive. In an architecture, it decides which changes get
merged.

The book sorts fitness functions along several axes. This essay needs one
sentence of that: the ones we'll build are *atomic* (they check one
characteristic), *triggered* (they run when code changes, not continuously),
and *static* (they read code rather than watching a running system).

You already rely on fitness functions; you just haven't had to write any. The
type checker is one. Access control is one. Swift 6's data-race checking is a
remarkably strong one. What those have in common is that the *language* decided
what to check. This essay is about the characteristics the language can't see
in a typical app, and how to make them fail a build anyway.

The examples all come from one small app, **Checkout**. Its repository has a
`main` branch where everything is clean and one branch per section where a
single fitness function is broken, so you can check out a branch, run the
tools, and see exactly the output quoted here.

---

## 2. What the compiler already enforces, and where it stops

Before writing any check of your own, it's worth being precise about what you
get for free, because the first rule of fitness functions is **use the
strongest mechanism that can express the constraint.** A lint rule that
duplicates a compiler guarantee is noise. A lint rule that covers a compiler
blind spot is architecture.

For a single-target app, which is most iOS and macOS apps, the map looks like
this:

| Mechanism | What it protects | In a single-target app |
|---|---|---|
| Types (`Money`, not `Double`) | Domain meaning | Yes, if you use them |
| Access control | Encapsulation | Only `private` and `fileprivate` help; `internal` is the whole app |
| Module boundaries (SPM targets) | Which layer may depend on which | **No.** There's one module |
| Swift 6 strict concurrency | Isolation between concurrency domains | Yes, with escape hatches (§4) |
| Static analysis | Whatever you tell it to | Yes, and it's what this essay is about |

The third row is the important one. In a modular codebase, `Domain` is its own
target, and if it tries to `import Persistence` without declaring the
dependency, the build fails. The compiler *is* the layering fitness function,
and you should not write a lint rule to repeat it. SwiftProjectLint's own
documentation for its boundary rule says so: if you've split your app into
targets, skip this rule, because the compiler does it better.

Even the module system has one gap worth knowing about if you do split later.
SwiftPM doesn't compare a target's `import` statements with its declared
`dependencies:`. A target can import a sibling module it never declared, as
long as something else happened to build that module first. It compiles today,
fails the day the other dependency is removed, and on a parallel build can
fail intermittently. `undeclared-target-dependency` exists for exactly that
case: a fitness function guarding the fitness function.

The first row deserves a moment too. Types are the strongest check there is,
but only when you use them. Checkout has a small wrapper:

```swift
/// A promotional code, normalised to upper case on creation.
struct DiscountCode: Hashable, Sendable {
    let value: String
    init(_ raw: String) { value = raw.uppercased() }
}
```

and on the `essay/s2-primitive-domain-type` branch, someone adds this to the
view model:

```swift
func apply(discountCode: String) {
    order.discount = DiscountCode(discountCode)
}
```

The parameter's *name* is the domain type, and its *type* is the raw string the
domain type exists to replace. Every caller now gets to skip the
normalisation. It's a small thing, and the linter reports it as information,
not an error:

```
Sources/Checkout/Presentation/CheckoutViewModel.swift:32: info:
  [Primitive Named For Its Domain Type] 'discountCode' is typed 'String' but
  names the domain type 'DiscountCode', a newtype over 'String'.
```

Note what this rule does *not* try to do. It doesn't try to detect "primitive
obsession" in general, which is a judgement no tool can make from syntax. It
enforces a wrapper you have **already declared**, in the places where a name
gives the concept away. That's a recurring theme: the good fitness functions
check a decision someone already made, not a principle.

With the compiler's share mapped, the gap is clear. In a single-target app,
nothing checks the layers. That's where we start.

---

## 3. Guarding the layers

### Write the diagram down

The first step is to turn the diagram into something a tool can read. For
Checkout, that's a few lines in `.swiftprojectlint.yml`:

```yaml
architectural_layers:
  domain:
    paths: ["Sources/Checkout/Domain/"]
    may_depend_on: []
  persistence:
    paths: ["Sources/Checkout/Persistence/"]
    may_depend_on: ["domain"]
  presentation:
    paths: ["Sources/Checkout/Presentation/"]
    may_depend_on: ["domain"]
```

That *is* the diagram. `Domain` depends on nothing. `Persistence` and
`Presentation` may each depend on `Domain`, and on nothing else. Files outside
every layer, such as `App/CheckoutApp.swift`, where the concrete store gets
created and handed to the view model, aren't judged at all. That's deliberate:
the composition root is the one place that's *supposed* to know everything.

Run the linter on the "just for now" branch:

```
Sources/Checkout/Presentation/CheckoutViewModel.swift:35: warning:
  [Layer Dependency] The 'presentation' layer references 'CoreDataOrderStore'
  from the 'persistence' layer, which it may not depend on
```

It's a warning, and the process exits non-zero, which is all a CI step needs.

### Allow lists beat deny lists

There's another way to write the same intent, and Checkout's config has that
too:

```yaml
  presentation:
    forbidden_imports: ["CoreData", "SwiftData"]
    forbidden_types: ["URLSession", "NSManagedObjectContext"]
```

This is a *deny list*: things `Presentation` must never touch. It's easy to
write and easy to read, and on the "just for now" branch **it says nothing.**
The offending line doesn't import Core Data, because it doesn't need to:
`CoreDataOrderStore` is in the same module. And `CoreDataOrderStore` isn't on
the forbidden list, because nobody predicted someone would construct it from a
view model.

That's the general weakness of deny lists. They list the violations someone
has already thought of, so they go out of date every time someone adds a type.
An allow list (`may_depend_on`) works the other way: it names what's
permitted, and everything else is a violation, including types that don't exist
yet. Firewall administrators learned this long ago. Keep the deny list for the
things you really do want to name, like frameworks that must never appear in
`Domain/`, and let the allow list do the structural work.

### A clean run must not look like a clean architecture

Every fitness function has a failure mode that's worse than a false positive:
passing because it isn't checking anything. Misspell a folder and the
layer-dependency check gives the app a clean bill of health, because no files
are in the layer. Here's the same config with two typos:

```
Warning: architectural_layers has 3 problems that make the layer rules check less than configured.
  layer 'persistence': path 'Sources/Checkout/Persistance/' matches no analysed file, so nothing in it is checked.
  layer 'persistence': may_depend_on names 'domian', but no layer has that name.
  layer 'presentation': may_depend_on names 'domian', but no layer has that name.
```

The tool warns about three kinds of configuration mistake: a layer path that
matches nothing, a dependency on a layer that doesn't exist, and layers that
depend on each other in a cycle (so they aren't really layers). Whatever
fitness functions you build, with this tool or any other, give them the same
property. **A check you can misconfigure into silence needs a check of its
own.**

### SwiftUI-shaped warning signs

Beyond the layers, a handful of rules catch the ways SwiftUI apps typically
drift. They work better as early warnings than as laws:

- **`View Model Direct DB Access`** flags a view model that imports a
  persistence framework. It's *off by default*, and the reason is instructive:
  Apple's own SwiftData tutorials put `@Query` straight in the view, and many
  small apps rightly do the same. A fitness function has to encode the
  architecture *you chose*, not an idealised one. If your app deliberately
  keeps storage out of the view layer, turn it on; if it doesn't, leave it off.
- **`God View Model`** and **`Too Many Environment Objects`** flag the view
  model that knows everything and the view that depends on everything. Both
  are what it looks like when the layers exist on paper and everything funnels
  through one type.
- **`Singleton Usage`** and **`Circular Dependency`** catch the two classic
  ways to route around an architecture: reach for a global, or make two types
  hold each other.

### Running it in CI

A fitness function that runs only when someone remembers to run it isn't one.
Checkout's workflow builds the linter and runs it on every pull request:

```yaml
- name: Lint the architecture
  run: '"$SWIFTPROJECTLINT" . --threshold warning'
```

`--threshold` sets the lowest severity that fails the run. At `warning`, a
layer violation stops the merge; `info` findings are reported but don't. The
choice of which rules sit at which severity is a governance decision, and §7
comes back to it.

### The same rule, written as a test

There's a second way to write structural fitness functions in Swift, and it's
worth seeing next to the first. [Harmonize](https://github.com/perrystreetsoftware/Harmonize)
takes the approach of Java's ArchUnit and Kotlin's Konsist: architecture rules
are ordinary unit tests over a queryable model of your source.

```swift
import Harmonize
import Testing

@Test func presentationDoesNotImportPersistenceFrameworks() {
    Harmonize.on("Sources/Checkout/Presentation")
        .sources()
        .assertTrue(
            message: "Presentation must not import a persistence framework",
            strict: true
        ) {
            $0.imports().withName(["CoreData", "SwiftData"]).isEmpty
        }
}
```

Add `import CoreData` to a file in `Presentation/` and this test fails, naming
the file. Notice `strict: true`, though. Without it, a misspelled folder
(`"Presentaton"`) matches no files, and the assertion passes, because there's
nothing to fail on. It's the same trap as the misconfigured layer earlier in
this section, found independently in a different tool. `strict: true` makes an
empty match a failure. Whatever tool you use, check how it handles a rule that
matches nothing.

The two styles suit different teams. Rules as tests are as expressive as
Swift, live next to the code they protect, and are owned by the team that
writes them. Harmonize also has a feature this essay's linter lacks: a
`baseline:` parameter that lists known violations and reports when one of
them is fixed. Rules as configuration need no code, come with precision that
has already been tuned on other codebases, and can do analysis a per-file
query can't: cross-file shape comparison (§5) and history (§6). Note, too,
that the test above is a deny list on imports, so it has the same blind spot
as `forbidden_imports`: the "just for now" line imports nothing. The two
approaches complement each other. Use whichever makes the rule easiest to
state correctly.

---

## 4. Isolation is architecture

Layers answer *who may name whom*. An app has a second structure that matters
just as much, which answers *who may touch which state*. In Swift, that
structure is made of **isolation domains**. All `@MainActor` code shares one
domain, the UI's. Each `actor` is its own. Crossing from one domain to another
works much like crossing a layer boundary through an interface: the call has
to be `await`ed, and only `Sendable` values can travel across.

Checkout already has this shape:

```swift
@MainActor @Observable
final class CheckoutViewModel {         // main-actor domain: UI state
    private let store: any OrderStore
    func placeOrder() async {
        try await store.save(order)      // ← the crossing
        …
    }
}

actor CoreDataOrderStore: OrderStore { … }   // its own domain: storage state
struct Order: Sendable { … }                 // the only thing that crosses
```

The `await` is the seam, and `Order` being `Sendable` is the contract across
it. That's why isolation deserves a place in an essay about architecture and
not only in one about thread safety. It decides which parts of the app own
which state, and what shape data must take to move between them.

### The strongest fitness function you have

In Swift 6 language mode, violating that structure is a **compile error**. You
can't pass a non-`Sendable` value across a domain boundary, or touch an actor's
state without `await`. Compared with anything a linter can do, that check runs
on every build instead of in CI, needs no configuration and so can't be
misconfigured, blocks the build instead of printing a report someone might not
read, and works from full type information instead of syntax.

Building Checkout showed it working. The clean app's first build failed:

```
CoreDataOrderStore.swift:47:24: error: static property 'model' is not
  concurrency-safe because non-'Sendable' type 'NSManagedObjectModel' may
  have shared mutable state
```

A `static let` holding a Core Data model is shared mutable state that any
domain can reach. Nobody wrote a rule for it. The language caught it.

### What the compiler doesn't check

It's easy to overstate this, so let's be precise. Swift 6 prevents *data
races*. It does not keep slow work off the main thread. This compiles cleanly
in a `@MainActor` view model:

```swift
func loadReceipt() {
    let data = try? Data(contentsOf: receiptURL)   // blocking I/O on the main thread
}
```

That's a hang, not a race, and a hang isn't a type error. "UI state lives on
the main actor; I/O doesn't" is a design intention the compiler doesn't
enforce. Swift 6.2 makes the gap more pressing: new app targets in Xcode 26
default to main-actor isolation, so unannotated code runs on the main actor
unless someone marks it `@concurrent` or moves it into an actor. (The build
setting is `SWIFT_DEFAULT_ACTOR_ISOLATION`, from SE-0466.) This is where lint is the right
tool: `Synchronous Network Call`, `Thread Sleep`, `Dispatch Semaphore in
Async` and `Expensive Operation in View Body` all patrol the same boundary from
the side the compiler doesn't cover.

### Escape hatches turn a proof into a promise

The compiler's check is sound, but every part of it has an off switch:

| Escape hatch | What it tells the compiler |
|---|---|
| `@unchecked Sendable` | Trust me, this type is safe to share |
| `nonisolated(unsafe)` | Trust me about this one variable |
| `@preconcurrency import` | Relax your checking of this module's types |
| `@preconcurrency` conformance | Accept this conformance; check isolation at runtime |
| `MainActor.assumeIsolated` | I know I'm on the main actor (traps if wrong) |
| Swift 5 language mode | Treat most of this as warnings |

Each one turns something the compiler *proves* into something a developer
*promises*. Two things make that an architectural concern and not a style
issue.

First, **escape hatches are the path of least resistance.** Look again at
Checkout's first build error. Right beneath it, the compiler offered this:

```
CoreDataOrderStore.swift:1:1: warning: add '@preconcurrency' to treat
  'Sendable'-related errors from module 'CoreData' as warnings
```

The escape hatch was offered as *the fix*. Under deadline, a developer takes
it, the error goes away, and the shared state remains. (The real fix was two
lines: build the model in a factory function instead of sharing one static
instance.)

Second, **escape hatches are invisible afterwards.** On the
`essay/s4-escape-hatch` branch, Checkout gains a receipt cache:

```swift
/// Rendered receipts, kept so reopening one doesn't re-render it.
final class ReceiptCache: @unchecked Sendable {
    private var receipts: [UUID: String] = [:]
    …
}
```

Nothing guards `receipts`. The app builds cleanly and will keep building
cleanly forever, because the compiler has been told not to look. Only an
outside check can still see it:

```
Sources/Checkout/Persistence/ReceiptCache.swift:5: warning:
  [Unchecked Sendable] @unchecked Sendable on 'ReceiptCache' bypasses the
  compiler's data-race safety checks
```

It's worth noting what the rule *doesn't* flag. A type marked `@unchecked
Sendable` that holds a `Mutex`, an `OSAllocatedUnfairLock` or an `NSLock`
passes quietly. There, the developer replaced the compiler's proof with a real
safety mechanism, and the rule only objects to promises with nothing behind
them.

### The ratchet

So the isolation fitness function isn't "are there data races?", because the
compiler already answers that wherever it's allowed to. It's **"how many places
have we told the compiler not to check, and is that number going up?"**

That framing matters for existing apps. You can't remove every escape hatch
this week. You can refuse to add new ones. Checkout does it with a short
script that counts escape-hatch findings and compares the count with a number
committed to the repository:

```bash
hatches='["Unchecked Sendable","Nonisolated Unsafe","Preconcurrency Import","Preconcurrency Conformance"]'

count=$("$linter" "$root" --format json --threshold error \
    | jq --argjson hatches "$hatches" \
         '[.issues[] | select(.ruleName as $rule | $hatches | index($rule))] | length')
baseline=$(cat "$baseline_file")

if (( count > baseline )); then
    echo "Escape hatches rose from $baseline to $count." >&2
    exit 1
fi
```

On the escape-hatch branch:

```
Escape hatches rose from 0 to 1. Remove the new one, or justify it in review.
```

When someone removes one, `scripts/ratchet.sh --update` lowers the number,
and it refuses to raise it. The count can only go down. That's the whole
pattern, and it applies to any characteristic you can count: force unwraps in
`Domain/`, suppression comments, files over a size limit.

---

## 5. The enum and the array that should agree

Everything so far has been about dependencies you can see in the code: who
names whom, who touches what. The most expensive coupling in an app usually
isn't like that.

Checkout's domain has an enum:

```swift
/// Every way a customer can pay.
enum PaymentMethod: String, Sendable {
    case card
    case paypal
    case bankTransfer
    case giftCard
    case storeCredit
}
```

and its settings screen, in a different folder, has a list:

```swift
// The methods the settings screen offers. Kept in step with
// `PaymentMethod` by hand.
private let supportedMethods = ["card", "paypal", "bankTransfer", "giftCard", "storeCredit"]
```

These two are coupled. Add a payment method to one and the other has to
change. But `SettingsView` doesn't reference `PaymentMethod`, so no dependency
check can see the connection. The coupling isn't in the import graph or the
type graph; it's in the *meaning*. Two places enumerate the same things.

On the `essay/s5-drift` branch, the business adds Apple Pay:

```swift
    case storeCredit
    case applePay
```

The enum changes; the array doesn't. It compiles. The tests pass, because
nothing tested the settings screen against the enum. The settings screen
doesn't offer Apple Pay, and the first anyone hears of it is a support ticket.

### One hazard, three stages

SwiftProjectLint approaches this as one hazard that passes through three
stages, with a rule for each:

| Stage | Rule | What it tells you |
|---|---|---|
| Fragile shape | `Manual Registration List` | This hand-built list will lose an entry one day |
| Duplicated concept | `Parallel Enum Shape` | These lists agree now, so consolidate while it's cheap |
| Realised drift | `Parallel List Drift` | These lists *almost* agree, which is a bug today |

On Checkout's clean `main` branch, the middle rule is already speaking:

```
Sources/Checkout/Presentation/SettingsView.swift:7: info:
  [Parallel Enum Shape] `supportedMethods` declares the same 5 entries
  (bankTransfer, card, giftCard, paypal, storeCredit) as `PaymentMethod`
  (PaymentMethod.swift:2) — the same list maintained in more than one place.
```

Nothing is broken yet. This is the cheap moment. On the drift branch, the
finding changes:

```
Sources/Checkout/Presentation/SettingsView.swift:7: info:
  [Parallel List Drift] `supportedMethods` (array, 5 entries) agrees with
  `PaymentMethod` (enum, PaymentMethod.swift:2) on 5 entries but is missing
  1: applePay.
```

Now it's not a refactoring suggestion. It names the missing member.

### Thresholds are part of the design

A detail from building the sample is worth passing on. With *four* payment
methods, neither rule said anything. Literal arrays have to hold at least five
names before they're compared, because short lists coincide far too often:
`["small", "medium", "large"]` isn't a concept worth consolidating. Likewise, a
list that's a strict *subset* of another only counts as drift when it's
missing about one entry of a substantial list, because a curated "the few we
support" list is a subset by design. Those thresholds were set by running the
rules across real codebases and reading every finding, and they're why the
rules can stay on without flooding a report. Precision is the subject of §7.

### The fix removes the whole class of bug

The right fix here isn't adding `"applePay"` to the array. It's deleting the
array:

```swift
enum PaymentMethod: String, CaseIterable, Sendable { … }

// SettingsView
private let supportedMethods = PaymentMethod.allCases
```

Now there's one list, and it can't drift. That's the pattern the three rules
point toward: **derive one list from the other**, so the coupling is enforced
by the type system instead of by memory. (The rule's current suggestion text
says "consolidate into one enum", which is right for two enums but not the
best advice for an enum and an array. That's worth improving.)

---

## 6. Fitness over time: what `git` knows that the code doesn't

Section 5 made the fix sound obvious. It isn't always. When the author ran
these duplication rules across about thirty of their own Swift projects, every
single finding had to be read by hand before anything could be done about it,
because the same signal, "these two lists match", turned out to call for five
different responses:

| What the pair actually is | Right response |
|---|---|
| The same concept declared twice, with no reason for two | **Unify** into one type |
| Two types on either side of a deliberate layer boundary, with a converter between them | **Keep both**, and annotate the seam |
| Two lists that merely share names (one is test input) | **Suppress** |
| An enum and a hand-maintained list of its members | **Derive** the list from the enum |
| Two lists that agreed once and don't now | **Fix the drift**, which is a real bug |

A snapshot of the code can't tell these apart. Did the two lists start as a
copy-paste, or did they converge by coincidence? When one is missing a member,
was it removed on purpose, or never added? The code today holds no record of
how it got here. **`git` does.**

### The empty pickaxe

`git log -S` (the "pickaxe") lists the commits that changed how many times a
given string appears in a file. On Checkout's drift branch:

```bash
git log --oneline -S'applePay' -- Sources/Checkout/Domain/PaymentMethod.swift
```

```
8b33c9a Accept Apple Pay
```

```bash
git log --oneline -S'applePay' -- Sources/Checkout/Presentation/SettingsView.swift
```

```
```

The second command prints nothing, and that empty output is the most useful
result in this section. It proves `applePay` has *never* appeared in the
settings screen, in any commit. That rules out the one explanation that would
make adding it risky: that someone added it, hit a problem, and took it out on
purpose. What's left is an omission, and fixing it is safe.

This isn't a contrived example. The technique was first used on a real
codebase, the author's SwiftInferProperties, where two hand-kept type lists
each turned out to be missing a member their sibling had (`UInt32` in one,
`Swift.Float80` in the other). In both cases the pickaxe came back empty. One
was added. The other was deliberately left out, for a reason the history
couldn't know (`Float80` doesn't exist on Apple silicon). The empty result
didn't make the decision; it removed the scary hypothesis, so the decision
could be made on its merits.

**An empty pickaxe isn't a null result. It's the answer.**

### A habit, and an idea

The habit costs nothing and needs no tooling: **before you "fix" an asymmetry,
ask the history whether it was deliberate.** One command. If the pickaxe comes
back empty, add the missing entry. If it doesn't, read the commit that removed
it before you undo someone's decision.

The idea goes further, and it's worth stating plainly that it's an idea and
not a feature. Once someone has classified a pair (these two are a deliberate
bridge; these two should be derived), that decision could be *recorded* next
to the code, and checked on every later change: edit one side of a recorded
pair and the check asks about the other. That turns a one-off investigation
into a standing fitness function, one that uses the system's *history* as
evidence rather than only its current state. (*Building Evolutionary
Architectures* has a "temporal" category, but it means something narrower: a
check with a time element, such as a test that deliberately breaks when a
dependency is upgraded, so someone has to look. Using history as evidence
isn't one of the book's categories.)

---

## 7. A check nobody reads protects nothing

The book asks for fitness functions to be *objective*. There's a stricter
test in practice: whether anyone reads the output. A check that reports
twenty things, three of which matter, trains its readers to skim. After a few
weeks, they skim past the three as well.

### An unread finding

SwiftProjectLint once ran a structured test against its own code. It turned up
a real bug: a function that rebuilt an issue record without copying one of its
fields, which quietly dropped data further down the pipeline. There were
nearly three thousand passing tests at the time, and none of them caught it.

What *should* have caught it was the linter itself. Its `Lossy Struct Rebuild`
rule, whose whole job is "you rebuilt a struct and left out a field", flagged
that exact line on a default run. The finding was there. It was one line among
many, and nobody read it.

That's not a detection failure. It's a signal-to-noise failure, and it's the
more common one. The lesson for anyone building fitness functions: **measure
your checks' precision the way you'd measure the system's.**

### Precision is a feature

Here's what that looks like in practice. `Manual Registration List` flags five
or more consecutive calls like `registry.register(…)`, since a hand-maintained
list loses entries silently. Run across the author's projects, it produced 23
findings, of which **5** were worth acting on. Reading the other 18 showed they
had one cause: code that builds text line by line (`lines.append("…")`) looks
exactly like a registration list, but each line is unique output, not a
component that could be forgotten. After excluding that one shape, the rule
reported **5 findings, all 5 actionable.** Nothing it should catch was lost.

Moving from 5-in-23 to 5-in-5 did more for the rule than any new detection
would have. A rule at 22% precision gets ignored, and then turned off. At 100%,
people read every finding.

### Governance, for a small team

A few practical rules follow:

- **Start with three to five rules that encode your diagram**, not every rule
  the tool ships. Checkout's config uses `enabled_only` for exactly this
  reason: fourteen rules, each tied to a decision in its architecture.
- **Use severity to mean something.** `info` for early warnings, like "these
  lists agree; consolidate while it's cheap". `warning` for policy you'll
  enforce in CI, like the layers or the escape hatches. `error` only for things
  you'd hold a release for.
- **Promote rules on evidence.** Checkout's drift finding is a real bug, yet
  it's `info` by default, so CI passes with it present. If the rule has been
  quiet and accurate on your codebase, raise it to `warning` with a one-line
  override in the config. That's the right time: after it has earned trust,
  not before.
- **Treat every suppression as a recorded exception.** On the
  `essay/s7-suppression` branch, someone silences the drift finding with a
  comment instead of fixing it:

  ```swift
  // swiftprojectlint:disable:next parallel-list-drift
  private let supportedMethods = ["card", "paypal", "bankTransfer", "giftCard", "storeCredit"]
  ```

  The drift finding disappears, and a new one takes its place:

  ```
  Sources/Checkout/Presentation/SettingsView.swift:8: warning:
    [SwiftProjectLint Suppression] SwiftProjectLint suppression:
    swiftprojectlint:disable:next parallel-list-drift
  ```

  Notice the severity. The drift was `info`; the suppression is a `warning`,
  and it fails CI. *Silencing a finding is stricter than ignoring it.* That's
  the right way round: an exception to your architecture should be a decision
  someone signs off on in review, not a comment that slips through.

---

> ### Sidebar: what about SOLID?
>
> SOLID is the checklist most Swift developers already have for "good
> design", so it's fair to ask which of its five principles a linter can
> check. The answer is uneven, and the unevenness is instructive.
>
> **Dependency inversion** is well covered, and you've already seen it:
> `OrderStore` is a protocol owned by `Domain`, implemented in `Persistence`
> and wired up in `App/`, and `may_depend_on` is its fitness function. Rules
> like `Direct Instantiation` and `Concrete Type Usage` push toward
> abstraction. Less obviously, `Single Implementation Protocol`, `Mirror
> Protocol` and `Unused Protocol Abstraction` push *back*, against protocols
> that nothing ever substitutes. The goal is inversion where it pays, not a
> protocol in front of every class.
>
> **Interface segregation** has direct checks: `Fat Protocol`, and `Too Many
> Environment Objects` for views that depend on everything.
>
> **Open/closed** needs rethinking for Swift. Enums are closed on purpose:
> adding a case and letting the compiler list every `switch` to update is the
> language working as intended, even though it "modifies" existing code. The
> Swift form of the violation is a change that's *required but invisible*:
> a `switch` on a raw string that falls through to `default`, or a hand-kept
> list that doesn't learn about `.applePay`. That's §5, seen through a
> different lens.
>
> **Single responsibility** can only be approximated. A responsibility is a
> judgement about meaning, and syntax doesn't show meaning. Size rules (`God
> View Model`, `Large View Body`) are proxies. `Boolean Control Coupling`
> comes closest to checking it directly: a flag parameter that chooses
> between two code paths is one function doing two jobs.
>
> **Liskov substitution** is the weakest statically, because it's about
> behaviour. `Swallowed Injection Downcast` catches its outline: a function
> that accepts any `OrderStore` and then does `as? CoreDataOrderStore` is
> admitting that not every conformer can really stand in. But the full check
> is dynamic: generate inputs and verify that every conformer obeys the
> protocol's laws. That's a property-based test, and it's where static
> analysis hands over to testing.
>
> SwiftProjectLint's rule reference lists the rules for each principle, and
> each rule's page names its principle in its header.

---

## 8. Monday morning

If you take one thing from this essay into your own app, make it this list:

1. **Draw your layers, then write them down as `may_depend_on`.** An allow
   list, not a deny list. Make sure the tool warns you when a path matches
   nothing.
2. **Turn on the escape-hatch rules and commit today's count.** Don't try to
   get to zero. Just stop the number going up.
3. **Find your enum-and-array pairs, and derive one from the other.**
   `CaseIterable` removes the whole class of bug.
4. **Before you "fix" an asymmetry, run `git log -S`.** An empty result means
   it was never there, so adding it is safe.

Then look at the characteristics that are specific to your app, the ones no
tool ships a rule for. Most linters, SwiftProjectLint included, let you write
your own rule; its documentation walks through the parts. The most valuable
fitness function you'll ever have is probably one nobody else needs.

Everything here has been about *structure*: which code may depend on which,
which state lives where, which lists must agree. The *behaviour* of the app
needs fitness functions too, and tests are those. Property-based tests
especially, which check a law across thousands of generated inputs rather than
a handful of examples, are the dynamic counterpart to everything in this
essay. The static checks keep the shape of the system honest; the dynamic ones
keep what it does honest. You want both.

---

## Drafting notes (remove before publishing)

- **SOLID sidebar** (after §7) sets up the closing's hand-off to property
  tests via Liskov substitution. Consider tightening the closing paragraph so
  the two don't repeat each other.
- **Word count:** about 5,100 of prose before the SOLID sidebar (~420 words). Under the 6–7k target; §3 and §6 have the most room to grow.
- **Verified 2026-09-22:** the book's definition and category terms (§1, via
  secondary sources, since the O'Reilly text was unreachable; the categories
  are scope, cadence, result, invocation and proactivity); the Harmonize snippet,
  compiled and run against Checkout (§3), including the empty-match behaviour;
  the SE-0466 Xcode 26 default (§4). **Corrected:** §6 had used the book's
  "temporal" category to mean history-based evidence, which it doesn't.
- **§1 hook:** the "dozen places" outcome is illustrative, not measured. Either
  keep it clearly hypothetical or replace it with a real migration story.
- **§6 and §7 use third person** ("the author") for the dogfooding stories.
  Switch to first person if it's published under your name.
- **§5 mentions a possible rule-message improvement** (`Parallel Enum Shape`'s
  suggestion for enum + array pairs). If that ships before publication, update
  the sentence.
- **Not yet included:** `Dispatch Semaphore In Async` and the other
  main-thread rules are named, not demonstrated. Consider a sixth `essay/`
  branch with `Data(contentsOf:)` in the view model, if a rule catches it.
  Check which one does before claiming it.
