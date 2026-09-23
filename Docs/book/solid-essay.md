# SOLID, Checked

## What a linter can and can't tell you about Swift design

*Draft 1, 2026-09-22. Outline: [`solid-essay-outline.md`](solid-essay-outline.md).
Sample code: [Joseph-Cursio/Checkout](https://github.com/Joseph-Cursio/Checkout),
`solid/` branches. Items marked **[verify]** must be checked before
publication.*

---

## 1. Five principles, five different kinds of claim

Sooner or later, every Swift developer gets this review comment:

> This violates SRP.

It's usually right, or at least not wrong. But try asking the obvious
questions. How would you know? What would you measure? If a second reviewer
says the type is fine, what settles it? For most SOLID arguments the honest
answer is that nothing settles it except who has more authority in the room.

SOLID is normally taught as five principles of equal standing, applied by
judgement: single responsibility, open/closed, Liskov substitution, interface
segregation, dependency inversion. This essay treats each one differently: as
a *claim about code*. Then it asks what evidence would confirm or refute each
claim, and specifically whether a tool could collect that evidence.

The five turn out to be nothing alike. Some are claims about **names**: which
types are mentioned in which places. Those can be checked mechanically,
because a syntax tree is made of names. Some are claims about **meaning**:
what a piece of code is *for*. Those can only be approximated, because meaning
isn't written down anywhere a tool can read. And one is a claim about
**behaviour**, which can be checked, just not by reading the code.

I didn't start out to make that argument. I got there by tagging the rules in
SwiftProjectLint, a static analyser for Swift projects, with the SOLID
principle each one serves. The result came out lopsided: fourteen rules for
dependency inversion, one for Liskov substitution. That lopsidedness isn't a
gap in the tool. It's a map of which principles are checkable at all.

So this essay goes through the principles in order from **most checkable to
least**, which reverses the acronym:

| Principle | How much a linter can check | Because the claim is about |
|---|---|---|
| Dependency inversion | Strong | Which names appear where |
| Interface segregation | Moderate | Size (visible) and use (harder) |
| Open/closed | Partial, once rethought for Swift | What the compiler can point to |
| Single responsibility | Proxies only | Meaning |
| Liskov substitution | Only its outline | Behaviour |

The examples all come from **Checkout**, a deliberately small SwiftUI shop app
with `Domain/`, `Persistence/` and `Presentation/` folders and an `App/`
composition root. Its repository has one branch per principle, each adding a
single violation, and every piece of tool output below comes from running the
tools on those branches.

---

## 2. Dependency inversion: checkable, and it pushes both ways

**The claim:** high-level policy shouldn't depend on low-level detail; both
should depend on abstractions.

Checkout's persistence is the textbook case. The domain declares what it
needs:

```swift
/// What the rest of the app needs from storage. `Domain/` owns the protocol;
/// `Persistence/` supplies an implementation; `App/` wires the two together.
protocol OrderStore: Sendable {
    func save(_ order: Order) async throws
    func recentOrders() async throws -> [Order]
}
```

`CoreDataOrderStore` implements it, in `Persistence/`. The view model takes
`any OrderStore`. The app's entry point is the one place that names the
concrete type and hands it over. The *inversion* is that `Domain` owns the
protocol: the storage layer depends on the domain's definition, not the other
way round.

This principle is the easiest to check, because it's a claim about **which
names appear where**, and names are exactly what a syntax tree holds. Does
`Presentation/` mention `CoreDataOrderStore`? Does a view model construct its
own dependencies? Is a parameter typed as a concrete service class? A tool can
answer each of those without understanding anything about what the code does.
SwiftProjectLint has a good dozen rules along these lines: `Layer
Dependency`, `Direct Instantiation`, `Concrete Type Usage`, `Missing
Dependency Injection`, `Singleton Usage`, `Unabstracted File IO`, and more.

### The rules that push back

Just as important are three rules that push the *other* way: `Single
Implementation Protocol`, `Mirror Protocol` and `Unused Protocol Abstraction`.
They flag protocols that nothing ever substitutes: the `FooServiceProtocol`
standing in front of every `FooService`, with one conformer and no caller that
cares. Over-applied dependency inversion produces this "protocol soup", and a
rule set that only pushed toward abstraction would reward it. Inversion is
worth its cost where something actually varies (a test double, a second
backend, a platform difference), and not elsewhere.

### What happened on the dependency-inversion branch

On `solid/d-concrete-dependency`, the view model stops using the protocol:

```swift
@MainActor @Observable
final class CheckoutViewModel {
    private let store: CoreDataOrderStore     // was: any OrderStore
    …
    init(store: CoreDataOrderStore) {         // was: any OrderStore
```

I expected `Concrete Type Usage` to report this. It didn't. Here's what the
linter said instead:

```
Sources/Checkout/Domain/OrderStore.swift:3: info: [Single Implementation Protocol]
  Protocol 'OrderStore' has only one conformer ('CoreDataOrderStore') —
  consider removing the abstraction.
Sources/Checkout/Domain/OrderStore.swift:3: info: [Unused Protocol Abstraction]
  Protocol 'OrderStore' is conformed to by 1 type but never used as a type —
  no parameter, property, constraint, or existential references it.
```

Faced with a dependency-inversion violation, the linter's advice is to
**delete the abstraction.**

Both findings are correct. Once nothing depends on `OrderStore`, it *is* an
unused protocol with one conformer. What neither rule can know is which way
the fix should go: should the view model go back to depending on the
protocol, or should the protocol go? That depends on whether anything will
ever need to stand in for Core Data, which is a design question about the
future, not a fact about the code. The rules can detect that the code and its
abstractions **disagree**. They can't say which one is right.

That's the most useful thing to understand about checking design principles.
Even the most checkable principle only gets you as far as "these two things
are inconsistent". The tool narrows the question; a person still answers it.

### Why the expected rule stayed silent

`Concrete Type Usage` didn't fire because `CoreDataOrderStore` is an `actor`,
and the rule deliberately exempts actors. Its reasoning is Swift-specific and
worth taking seriously: in Swift 6, an actor's isolation is part of its
contract. Calls to it must be `await`ed and are serialised, and a caller who
sees only a protocol sees only what the protocol promises.

For `OrderStore`, though, the protocol promises the same thing. Every
requirement is `async`, so calls through `any OrderStore` still need `await`.
And where a protocol *does* have a synchronous requirement, an actor can only
satisfy it with a `nonisolated` member, so the compiler makes that trade-off
visible in the conformance rather than letting it slip by. **[verify this
against Swift 6.2's isolated-conformance rules (SE-0470) before publishing.]**
Either way, the exemption is broader than its reason. A better version would
exempt actors only when abstracting them would cost something the protocol
can't express. The point generalises: in a language where isolation is part of
the type system, "depend on an abstraction" has to ask what the abstraction
preserves, not only what it decouples.

### The composition root

One more finding, and it's on Checkout's clean `main` branch:

```
Sources/Checkout/App/CheckoutApp.swift:7: warning: [Direct Instantiation]
  Direct instantiation of 'CoreDataOrderStore' detected — prefer dependency injection
```

This is the composition root: the one place where constructing the concrete
store is *correct*, because something has to. The rule knows that, and
exempts composition roots, but it recognises one by its shape: an `@main`
type's `init()`, or a type wiring three or more services. Checkout creates one
service in a stored property, which is how many small apps look. It's a false
positive, and it's here because checkable doesn't mean perfectly checked.
Precision is work that never finishes.

---

## 3. Interface segregation: size is visible, use is harder

**The claim:** clients shouldn't be forced to depend on methods they don't use.

The checkable part is size. On `solid/i-fat-store`, `OrderStore` has grown the
way protocols do: every feature that touched orders added a requirement.

```swift
protocol OrderStore: Sendable {
    func save(_ order: Order) async throws
    func recentOrders() async throws -> [Order]
    func order(withIdentifier identifier: UUID) async throws -> Order?
    func cancel(_ identifier: UUID) async throws
    func refund(_ identifier: UUID, amount: Money) async throws
    func receiptText(for identifier: UUID) async throws -> String
    func exportCSV() async throws -> String
    func orderCount() async throws -> Int
    func deleteAll() async throws
    func recordAnalyticsEvent(_ name: String) async
}
```

```
Sources/Checkout/Domain/OrderStore.swift:7: info: [Fat Protocol]
  Protocol 'OrderStore' has 10 requirements — consider splitting into smaller protocols.
```

The SwiftUI equivalent is a view that depends on everything. `Too Many
Environment Objects` reports a view with four or more `@EnvironmentObject`
properties, which almost certainly uses only part of each.

### What size can't tell you

But the principle isn't really about size. It's about **use**. A protocol with
twelve requirements whose every client calls all twelve is fine. A protocol
with four, where each client calls a different one, is not. The fat
`OrderStore` above is a problem because the checkout screen needs `save`, the
order history screen needs `recentOrders`, the admin tools need `refund` and
`exportCSV`, and analytics needs one method, yet each of them depends on all
ten, and every test double has to implement all ten.

Checking *that* needs a different analysis: for each client of the protocol,
which requirements does it actually call? That's a cross-file question, but
it's still a question about names, so it's within reach of a static tool.
SwiftProjectLint doesn't do it yet. It's the principled version of `Fat
Protocol`, and until it exists, a requirement count is the proxy.

Swift makes the fix unusually cheap. Protocol composition lets you split
`OrderStore` into `OrderSaving`, `OrderHistory` and `OrderAdministration`,
and write `any OrderSaving & OrderHistory` wherever a client really needs
both. In a language where segregation costs one `&`, a fat protocol is harder
to excuse.

---

## 4. Open/closed, rethought for Swift

**The claim:** software entities should be open for extension and closed for
modification. You should be able to add behaviour without editing code that
already works.

Taken literally, Swift breaks this all the time, on purpose. Checkout's
`PaymentMethod` is an enum:

```swift
enum PaymentMethod: String, Sendable {
    case card
    case paypal
    case bankTransfer
    case giftCard
    case storeCredit
}
```

Add `case applePay` and every exhaustive `switch` over `PaymentMethod` stops
compiling until someone handles the new case. By the textbook definition,
that's a violation: adding a feature forced modifications to existing code.
In practice it's one of Swift's best features. The compiler hands you a
complete list of every place that needs a decision.

This is the old *expression problem*. Enums make it cheap to add operations
(write a new `switch`) and make new cases *visible*. Protocols make it cheap
to add cases (write a new conformer) but hard to add operations. Swift offers
both, and choosing an enum is choosing to be closed to new cases, deliberately.

So in Swift, the open/closed violation worth catching isn't "a change requires
modification". It's **"a change requires modification the compiler can't point
to."**

### Rules for invisible modification

That reframing is checkable, and it's what several rules are really about. On
`solid/o-string-switch`, someone labels receipts:

```swift
enum ReceiptFormatter {
    static func paymentLabel(for method: PaymentMethod) -> String {
        switch method.rawValue {
        case "card": "Card"
        case "paypal": "PayPal"
        case "bankTransfer": "Bank transfer"
        case "giftCard": "Gift card"
        case "storeCredit": "Store credit"
        default: "Other"
        }
    }
}
```

It compiles, it works, and it has quietly opted out of the compiler's help.
Add `.applePay` and nothing fails to compile. Receipts start printing "Other".

```
Sources/Checkout/Presentation/ReceiptFormatter.swift:4: info: [String Switch Over Enum]
  Switch on '.rawValue' loses exhaustiveness checking — switch on the enum directly
```

The fix is to switch on the enum itself and delete the `default:`, so the
compiler can point to this function when the next case arrives.

The same idea covers other rules:

- **`Parallel List Drift`** and **`Manual Registration List`** catch a
  hand-kept list that needs editing whenever the enum changes. Checkout's
  settings screen once listed payment methods as an array of strings, and when
  Apple Pay was added to the enum, the settings screen never offered it.
  (That story is the centre of this essay's companion, *Architectural Fitness
  Functions for Swift Apps*.)
- **`Scattered Enum Mapping`** catches the same mapping written out in several
  `switch`es in different files. The compiler does list them all, but one
  change now has to be made, identically, in N places.

All three catch a change that has to happen somewhere the compiler won't flag.
That's the version of open/closed that fits Swift, and it's quite checkable.

---

## 5. Single responsibility: proxies only

**The claim:** a module should have one reason to change.

Here the checking gets hard, and it's worth being precise about why. "Reason
to change" is a claim about the future and about meaning. Two methods belong
to the same responsibility if they'd change for the same *business* reason:
the same stakeholder, the same kind of request. Nothing in a syntax tree
records business reasons. `calculateTax` and `formatReceipt` might change
together or for completely different reasons, and the code looks the same
either way.

So linters measure something else and hope it correlates: **size**. `God View
Model` flags a view model with ten or more `@Published` properties, or
fifteen stored properties on an `@Observable` type. `Fat View`, `Large View
Body` and `ViewBuilder Complexity` do the same for views.

These are proxies, and they should be presented as proxies. A large type often
*does* hold several responsibilities, because code accumulates. But size is
evidence, not proof, and a team that treats a threshold as if it were the
principle will do real damage: splitting a cohesive type in two to get under
fifteen properties, and scattering one responsibility across two files that
now always change together. That's the opposite of what the principle asks
for.

### The one rule that checks the principle itself

One rule gets closer. On `solid/s-flag-parameter`, placing an order gains a
mode:

```swift
func placeOrder(isGift: Bool) async {
    if isGift {
        giftMessage = "A gift for you"
        shippingLabel = "Ship to recipient, no prices"
        order.discount = nil
    } else {
        giftMessage = nil
        shippingLabel = "Ship to buyer"
    }
    …
}
```

```
Sources/Checkout/Presentation/CheckoutViewModel.swift:36: warning: [Boolean Control Coupling]
  Boolean parameter 'isGift' selects between two code paths — this is control
  coupling (the caller decides which behavior runs).
```

This isn't a proxy. A `Bool` parameter that picks between two substantial code
paths is, quite literally, one function doing two jobs, with the caller
choosing which. The rule only fires when both branches do real work, so a flag
that tweaks one value doesn't count. Its documentation cites Adam Tornhill's
*Hidden Design Decisions: Refactoring Control Coupling*, and the remedy is the
same: replace the flag with two named functions, or pass in the behaviour.
**[verify the essay's summary of Tornhill against the original.]**

### A better signal, outside the code

If you want evidence about "reasons to change", look where changes are
recorded. Files that are always modified in the same commits share a reason
to change, whatever their size, and two halves of a large type that are
*never* modified together probably don't. `git log` records exactly what
syntax can't. Change coupling of this kind is well studied, and it's the most
honest signal for single responsibility there is. It isn't a lint rule today,
and it would need history rather than a snapshot to become one.

---

## 6. Liskov substitution: where static analysis hands over

**The claim:** anything that works with a type must work with any subtype. In
Swift, where protocols do most of the work, that means: anything that accepts
a protocol must work with *every conformer*.

This is a claim about behaviour. Two types can have identical signatures and
completely different behaviour, and the compiler, which checks signatures, is
satisfied either way. So static analysis can see only the outline of this
principle.

### The outline

Some violations do show up in the code. On `solid/l-downcast`, the view model
takes an abstraction and then looks behind it:

```swift
init(store: any OrderStore) {
    self.store = store
    // Only Core Data keeps enough history to export.
    canExportHistory = (store as? CoreDataOrderStore) != nil
    …
}
```

```
Sources/Checkout/Presentation/CheckoutViewModel.swift:16: info: [Swallowed Injection Downcast]
  Initializer downcasts injected 'store' to concrete 'CoreDataOrderStore' — the
  protocol parameter accepts any conformer, but this honors only one type and
  silently drops the rest (e.g. test doubles)
```

The downcast is the code admitting that not every conformer can really stand
in. `Unconditional Trap` catches the other classic outline: a conformance that
implements a requirement with `fatalError("not supported")`. (That rule
reports traps anywhere, not only in conformances, so it's a partial fit.)

Notice that the rule's message mentions test doubles. That's where this
section is going.

### A bug nobody planted

Here's what Checkout's Core Data store did on `main` when asked for recent
orders:

```swift
return Order(identifier: identifier, items: [], paymentMethod: method, discount: nil)
```

Every order came back with **no line items and no discount**. Only the
identifier and the payment method survived the round trip. It compiles. It
satisfies every signature in `OrderStore`. No rule reports it. I checked: even
`Lossy Struct Rebuild`, whose job is catching a struct rebuilt with a field
left out, stays quiet, because the order is built from a Core Data record,
not copied from another `Order`.

I didn't plant this bug. I wrote the sample app for the companion essay, kept
the persistence code minimal, and didn't notice. And one of that essay's
branches adds a "reorder last" feature that reads exactly this method, so
reordering would silently produce an empty cart.

### Why it's a Liskov bug

Now imagine testing the view model the usual way, with an in-memory store:

```swift
actor InMemoryOrderStore: OrderStore {
    private var orders: [Order] = []

    func save(_ order: Order) async throws {
        orders.append(order)
    }

    func recentOrders() async throws -> [Order] {
        orders
    }
}
```

This store keeps whole `Order` values, so it round-trips everything. Every
view-model test passes against it. The app, running against Core Data, loses
data. The fake and the real store both conform to `OrderStore`, and they are
**not substitutable**. That is exactly what Liskov substitution forbids, and
it's the form the violation most often takes in app code. **Test doubles are
where most app codebases break Liskov, and almost nobody checks them.**

### The check that works: a contract test

The fix for the *checking* problem is to write the protocol's contract down
once, as laws, and run the same laws against every conformer. For
`OrderStore`, two laws:

1. **Round-trip:** whatever you save, you get back unchanged.
2. **No inventions:** a store returns only orders that were saved into it.

Written as property-based tests, they generate hundreds of random orders
instead of relying on a few hand-picked examples. On `solid/l-contract-test`:

```swift
enum StoreKind: String, CaseIterable, Sendable {
    case inMemory
    case coreData

    func makeStore() -> any OrderStore {
        switch self {
        case .inMemory: InMemoryOrderStore()
        case .coreData: CoreDataOrderStore(inMemory: true)
        }
    }
}

@Test("save then fetch round-trips the order", arguments: StoreKind.allCases)
func saveThenFetchRoundTrips(kind: StoreKind) async throws {
    await propertyCheck(input: OrderGen.order) { order in
        let store = kind.makeStore()
        try await store.save(order)
        let fetched = try await store.recentOrders()
            .first { $0.identifier == order.identifier }

        #expect(fetched?.items == order.items)
        #expect(fetched?.paymentMethod == order.paymentMethod)
        #expect(fetched?.discount == order.discount)
    }
}
```

`OrderGen.order` builds random orders with zero to three line items, any
payment method, and an optional discount code. Run it:

```
✘ Test "save then fetch round-trips the order" recorded an issue with 1 argument
  kind → coreData: Expectation failed: (fetched?.discount → nil) ==
  (order.discount → DiscountCode(value: "7"))
↳ Failure occured with input Order(identifier: 00000000-0000-0000-0000-000000000000,
  items: [], paymentMethod: paypal, discount: Optional(DiscountCode(value: "7"))).
  (shrunk down from Order(identifier: 00000000-0000-0000-0000-000216027933,
  items: [], paymentMethod: paypal, discount: Optional(DiscountCode(value: "AYF8IXE7")))
  after 8 iterations)
  Add `.fixedSeed("hYpx8JScV61o+JJvj8pXxX94c2ZjT9TPDPfv26dUyXw=")` to the Test
  to reproduce this issue.
✔ Test "fetch returns only saved orders" with 2 test cases passed
```

(The misspelling "occured" is in the test library's output; it's quoted as
printed.)

The in-memory store passes both laws. Core Data passes "no inventions" and
fails round-tripping. The framework then **shrinks** the failure: it tries
simpler versions of the failing order until it finds the smallest one that
still fails. Here, that's an order with no items and a one-character discount
code that comes back as `nil`. That's the whole bug report: *discount codes
don't survive*. Line items don't either, which is a second instance of the
same defect. The shrinker picked the simplest failing case, not every failing
case.

The fix, on `solid/l-contract-test-fixed`, was small: two attributes the
store never saved.

```diff
+        let encodedItems = try JSONEncoder().encode(order.items)
         …
+            record.setValue(encodedItems, forKey: "lineItems")
+            record.setValue(order.discount?.value, forKey: "discountCode")
         …
-                return Order(identifier: identifier, items: [], paymentMethod: method, discount: nil)
+                let discount = (record.value(forKey: "discountCode") as? String).map(DiscountCode.init)
+                return Order(identifier: identifier, items: items, paymentMethod: method, discount: discount)
```

With that, both laws pass for both stores. Now the in-memory store is a
trustworthy stand-in, and the contract test keeps it that way: add a third
store (CloudKit, a server), and it has to pass the same laws before any test
can rely on it.

Writing laws also forces questions the protocol never answered. Should saving
the same order twice produce one order or two? `OrderStore` doesn't say. The
in-memory store appends; a database with a unique key would upsert. Neither is
wrong until someone decides. A contract test can't be written until someone
does, and that's a feature.

### Standard protocols have laws too

The same idea applies to Swift's own protocols, which have documented laws
the compiler never checks. `Equatable` must be symmetric and transitive.
`Hashable` values that are equal must hash equally. `Comparable` must be a
total order. Checkout's `Money` is `Hashable` and `Comparable`. A `hash(into:)`
that ignores a field, or a `<` that isn't consistent with `==`, breaks `Set`,
`Dictionary` and `sort` in ways that surface as baffling UI bugs.
[SwiftPropertyLaws](https://github.com/Joseph-Cursio/SwiftPropertyLaws) checks
those laws with generated inputs:

```swift
@Test func moneyLaws() async throws {
    try await checkComparablePropertyLaws(for: Money.self, using: MoneyGen.money)
}
```

**[verify: compile this against Checkout. The signature is confirmed from
source (`checkComparablePropertyLaws(for:using:)`, `async throws`, returns
`[CheckResult]`); `MoneyGen.money` doesn't exist yet.]**

But the standard protocols are the easy case, because their laws are written
down. The harder, more valuable point is that **your protocols have laws too**,
and nobody writes them down. `OrderStore` had a contract from the day it was
declared. It just lived in everyone's head, and the Core Data store didn't
share it.

---

## 7. What the lopsidedness teaches

Here's the table again, with what we found:

| Principle | Coverage | What the checks were really about |
|---|---|---|
| Dependency inversion | Strong | Names, which a syntax tree holds |
| Interface segregation | Moderate | Names too, but use needs a cross-file analysis |
| Open/closed | Partial, once rethought | What the compiler can and can't point to |
| Single responsibility | Proxies | Meaning, which nothing records |
| Liskov substitution | Outline only | Behaviour, which needs running code |

The pattern is simple once you see it. **Principles about names are
checkable. Principles about meaning can only be approximated. Principles about
behaviour need tests, not linters.** SOLID looks like five rules of the same
kind, but it's a structural rule, a sizing heuristic, a language-dependent
guideline, a judgement, and a behavioural contract.

That suggests how to treat each one:

1. **Automate dependency inversion and interface segregation.** They're about
   names, and tools check names well. Expect the tool to report
   inconsistencies, not to choose the direction of the fix.
2. **Adopt the Swift version of open/closed.** Don't fight the compiler's
   exhaustiveness; protect it. Turn on the rules that catch switches on raw
   values, hand-kept lists and scattered mappings.
3. **Treat single-responsibility findings as a prompt for a conversation,
   never a verdict.** Don't split a type to get under a threshold. If you want
   evidence, look at which files change together.
4. **Write a contract test for every protocol with more than one conformer,**
   and remember that a test double counts as a conformer. If your tests use an
   in-memory store, a mock network client or a fake clock, each of those is a
   claim that it behaves like the real thing. Check the claim.

The next time someone writes "this violates SRP" on your pull request, you'll
know what kind of claim it is. It's a judgement, and it can be a good one. But
it's a different kind of statement from "this view model constructs a Core
Data store", which a tool can verify, and from "this store loses discount
codes", which a test can prove. Knowing which kind of claim you're making is
what lets you enforce the ones that can be enforced, and argue honestly about
the rest.

---

## Drafting notes (remove before publishing)

- **Word count:** about 4,100 of prose, under the 5–6k target. §3 and §5 are the thinnest; §5 could show one real change-coupling query against Checkout's history.
- **[verify] items:** actor conformances to synchronous requirements under
  Swift 6.2 (§2); the Tornhill summary (§5); compiling the
  SwiftPropertyLaws snippet for `Money` (§6), which needs a `MoneyGen`
  generator.
- **§1 claims "fourteen rules for dependency inversion, one for Liskov":**
  that matches the `RULES.md` index (including the one rule tagged with both).
  Recount if the tags change.
- **Voice:** this draft uses first person ("I didn't plant this bug"), because
  that story is stronger told by the person it happened to. The
  fitness-functions draft uses third person for its dogfooding stories; make
  the two consistent.
- **Seed:** the §6 output is from one run, and its seed is quoted so readers
  can reproduce it. If the generator or the laws change, re-capture.
- **Follow-ups referred to in the text** (composition-root false positive,
  actor exemption, interface segregation by use) are described as current
  behaviour. If any ships before publication, update the section.
- **§2's naming-suffix tension** (`Protocol Naming Suffix` vs. `Mirror
  Protocol`) was left out of this draft to keep §2 focused. Add it back only
  if it's been resolved one way or the other.
