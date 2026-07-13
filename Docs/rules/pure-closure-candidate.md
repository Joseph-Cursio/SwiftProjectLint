[← Back to Rules](RULES.md)

## Pure Closure Property-Test Candidate

**Identifier:** `Pure Closure Property-Test Candidate`
**Category:** Testability
**Severity:** Info

### Rationale

[Pure Function Property-Test Candidate](pure-function-candidate.md) can only point at a
*declaration*. A great deal of the pure logic in real Swift has none.

A `filter` predicate or a `sorted(by:)` comparator written inline is a pure function in everything
but syntax. Being anonymous is the only thing standing between it and a property test — and because
the linter had nothing to point at, it said nothing, so neither did you.

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
*every* match, not just the leading one, so for `currentPath = "/a/"` the path `/a/b/a/c` collapses
to `bc` — one component — and a *grandchild* is listed as an immediate child of the folder. It sat
there because there was nothing to write a test against.

Name it and the property writes itself:

```swift
func isImmediateChild(_ path: String, of parent: String) -> Bool { … }

// and now this is sayable, and checkable over generated paths:
//   a grandchild is never an immediate child, however its names repeat
```

### Captures are not impurities

That predicate captures `currentPath`, which is a `var` on the enclosing type. **That does not
disqualify it.** Lift the body into `isImmediateChild(_ path: String, of parent: String)` and the
capture simply *becomes a parameter*. What the caller does with its own state is the caller's
business.

Refusing captured state would refuse this rule's most valuable finding — which is exactly the bug
site above.

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
- one-statement `map { $0.name }` projections. A projection is not a property, naming it buys
  nothing, and a rule that fires on every `map` in a codebase teaches people to switch the category
  off.
- test files.

### What to do about it

Lift it into a named function. Anything it captures becomes a parameter, and what is left is a pure
function you can generate inputs for — at which point
[Pure Function Property-Test Candidate](pure-function-candidate.md) will seed it, and
`swift-infer discover --seeds` will propose its laws.

This is the loop: the closure rule tells you what to *name*, and naming it is what lets every other
tool in the chain see it.

---
