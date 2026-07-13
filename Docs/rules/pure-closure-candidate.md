[← Back to Rules](RULES.md)

## Pure Closure Property-Test Candidate

**Identifier:** `Pure Closure Property-Test Candidate`
**Category:** Testability
**Severity:** Info

### Rationale

**An inline closure cannot be tested.** Not *is hard to test* — cannot. There is no name to call, no
signature to satisfy, no seam to reach it through. It is the only kind of Swift code that a test
literally cannot address.

Everything else in a file has a door. A method has a name. A computed property has a getter. Even a
`private` helper can be reached by widening it or by testing the type that owns it. A closure written
inline at a call site has none of that: the only way to run it is to run *the entire method that
contains it*, with whatever state that method needs standing up around it, and then to infer what the
closure did from what the method returned.

That inference is where the testing actually breaks down. Suppose you do the work — construct the
type, populate a store, set the state the method reads, call it, and assert on the result. You have
now written a test whose failure message tells you *the output list was wrong*. It does not tell you
which of the two closures was wrong, or which input broke it, and you cannot enumerate the closure's
inputs directly because you never had a handle on the closure. You are testing a predicate through a
keyhole.

And it gets worse the more the closure is worth testing. A closure with a branch, an edge case, an
ordering, an arithmetic step — the closures that actually *earn* a test — are exactly the ones buried
deepest, because they tend to live inside the methods with the most state around them. **The code
most in need of a test is the code least reachable by one.** That is not a property-testing problem.
It is true of any test you might want to write, and it would be true if this linter did not exist.

What makes it worth a rule is that this is **self-inflicted and reversible**. The closure is *pure*:
a function in everything but syntax. Nothing about it needs to be unreachable. The only thing standing
between it and a test is that nobody gave it a name.

### The case this rule was built for

```swift
let immediateChildren = allFiles.filter { file in
    let relativePath = file.path.replacingOccurrences(of: currentPath, with: "")
    return relativePath.split(separator: "/").count <= 1
}
files = immediateChildren.sorted { file1, file2 in
    if file1.isFolder != file2.isFolder { return file1.isFolder }
    return file1.name.localizedCaseInsensitiveCompare(file2.name) == .orderedAscending
}
```

Two pure functions, neither with a name. The first has a **real bug**: `replacingOccurrences` strips
*every* match, not just the leading one, so for `currentPath = "/a/"` the path `/a/b/a/c` collapses to
`bc` — one component — and a *grandchild* is listed as an immediate child of the folder.

It is worth being precise about why that bug survived, because "nobody tested it" is not the answer.
It survived because testing it meant standing up a view model, a model context, a populated store and
a current path, calling the method, and then asserting on a **file list** — at which point you are no
longer looking at the predicate. To catch this you would have had to *already suspect* that a path
component might repeat, and then hand-build a store containing `/a/b/a/c` to prove it. The bug is
invisible to every test you would think to write, and reachable only by a test you would only write if
you already knew the answer.

Give it a name and the whole shape changes:

```swift
func isImmediateChild(_ path: String, of parent: String) -> Bool { … }
```

Now it takes two `String`s and returns a `Bool`. You can call it. You can generate inputs for it — and
a generator does not need to suspect anything, which is the entire point:

```swift
// a grandchild is never an immediate child, however its names repeat
```

The bug falls out on the first run, and it falls out as a *minimal* failing pair, not as a wrong list
of files.

### Captures are not impurities

That predicate captures `currentPath`, which is a `var` on the enclosing type. **That does not
disqualify it.** Lift the body into `isImmediateChild(_ path: String, of parent: String)` and the
capture simply *becomes a parameter*. What the caller does with its own state is the caller's
business.

Refusing captured state would refuse this rule's most valuable finding — which is exactly the bug site
above.

What no extraction rescues is a closure that **writes** to what it captured:

```swift
items.forEach { item in
    runningTotal += item.amount    // not a candidate: its job IS the side effect
}
```

### Scope

Fires on a **pure** closure passed to a fixed list of higher-order collection operations, whose
closure arguments are *supposed* to be functions:

| operation | law worth stating once it has a name |
|---|---|
| `sorted`, `sort`, `min`, `max`, `partition` | a comparator must be a **strict weak ordering** — irreflexive, antisymmetric, transitive. One that is not can *crash* `sorted(by:)`, and no example test tells you which triple broke it |
| `filter`, `first`, `contains`, `allSatisfy`, `drop`, `prefix`, `removeAll` | a predicate is a total function of its inputs — state what it must accept and reject |
| `map`, `compactMap`, `flatMap` | a transform is a function of its input |
| `reduce` | the combine step is usually associative, often with an identity — both checkable, neither by example |

Does **not** fire on:

- closures passed to anything else. `Task { }`, `withAnimation { }`, `DispatchQueue.main.async { }`
  take closures too, and a closure run for its *effects* is not a property waiting to be named. The
  operation list is deliberately fixed.
- **impure** closures — I/O, logging, the clock, randomness, or anything that can trap. Purity is
  decided by the same oracle as the function rule (`SwiftEffectInference.PurityInferrer`).
- closures that **write** to a capture.
- one-statement `map { $0.name }` projections. A projection is not a property, naming it buys nothing,
  and a rule that fires on every `map` in a codebase teaches people to switch the category off.
- comparators whose ordering is **free** — see below.
- test files.

The exclusions all serve one end: **a finding must be worth the refactor it asks for.** Unreachable is
only a problem when there is something in there worth reaching.

### A comparator only counts when the ordering can be got wrong

The other operations are floored on body size. Comparators cannot be, because **the shortest
comparators are the wrong ones**:

```swift
files.sorted { $0.name <= $1.name }                              // reflexive: not a strict weak ordering
tasks.sorted { $0.priority > $1.priority || $0.name < $1.name }  // transitivity broken, on one line
```

Both fit inside any size floor, and both can crash `sorted(by:)`. So the discriminator is not size, it
is whether the ordering is **free**:

```swift
files.sorted { $0.date > $1.date }    // no finding
```

One strict comparison (`<` or `>`), the same member path on both sides, the two closure parameters as
the two bases. That ordering is inherited from the key's `Comparable` conformance and cannot be got
wrong — there is no law left to state. Everything else earns the finding: a branch, a `||`, a second
key, a `compare(_:)` call.

Two residuals worth knowing:

- A key reached through a **call** — `{ $0.name.lowercased() < $1.name.lowercased() }` — still fires.
  The rule cannot see that the call is total and deterministic, and the case it was built for
  (`localizedCaseInsensitiveCompare`, locale-dependent) is one where it is not obviously either.
- A **floating-point** key is a false negative: `{ $0.score < $1.score }` on a `Double` is *not* a
  strict weak ordering once a `NaN` is in the collection, and nothing in the syntax says whether
  `score` is a `Double`. Naming it is what would surface that — which is this rule's advice anyway.

### What to do about it

Lift it into a named function. Anything it captures becomes a parameter, and what is left is a pure
function you can generate inputs for.

That is the whole fix, and the payoff is immediate and local: the logic becomes **addressable**. You
can call it, you can enumerate its inputs, and a failure points at the function rather than at the
list of files three layers up.

<details><summary>It also unblocks the rest of the toolchain</summary>

Once the closure has a name, [Pure Function Property-Test Candidate](pure-function-candidate.md) can
seed it, and `swift-infer discover --seeds` will propose its laws — a nameless closure cannot be
indexed by anything.

This is a consequence of naming it, not a reason to. If the only argument for a refactor were that it
suits a tool, the right response would be to fix the tool.

</details>

---
