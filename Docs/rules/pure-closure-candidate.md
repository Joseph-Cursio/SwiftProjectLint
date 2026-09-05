[← Back to Rules](RULES.md)

## Pure Closure Property-Test Candidate

**Identifier:** `Pure Closure Property-Test Candidate`
**Category:** Testability
**Severity:** Info

### Rationale

**An inline closure cannot be tested.** Not *is hard to test* — cannot. There is no name to call, no
signature to satisfy, no seam to reach it through. It is the only kind of Swift code a test cannot
address at all.

Everything else in a file has a door. A method has a name. A computed property has a getter. Even a
`private` helper can be reached by widening it, or by testing the type that owns it. A closure written
inline at a call site has none of that: the only way to run it is to run *the entire method that
contains it*, with whatever state that method needs stood up around it, and then to infer what the
closure did from what the method returned.

That inference is where testing actually breaks down. Do the work — construct the type, populate a
store, set the state the method reads, call it, assert on the result — and you have written a test
whose failure message says *the output list was wrong*. It does not say which of the two closures was
wrong, or which input broke it, and you cannot enumerate the closure's inputs directly because you
never had a handle on the closure. You are testing a predicate through a keyhole.

And it gets worse the more the closure is worth testing. A closure with a branch, an ordering, an edge
case — the closures that actually *earn* a test — are the ones buried deepest, because they tend to
live inside the methods with the most state around them. **The code most in need of a test is the code
least reachable by one.** That is not a property-testing problem; it is true of any test you might
want to write.

What makes it worth a rule is that this is **self-inflicted and reversible**. The closure is *pure*: a
function in everything but syntax. Nothing about it needs to be unreachable. The only thing standing
between it and a test is that nobody gave it a name.

### Discussion

The case this rule was built for:

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
longer looking at the predicate. To catch it you would have had to *already suspect* that a path
component might repeat, and then hand-build a store containing `/a/b/a/c` to prove it. The bug is
invisible to every test you would think to write, and reachable only by a test you would write only if
you already knew the answer.

Give it a name and the shape changes completely:

```swift
func isImmediateChild(_ path: String, of parent: String) -> Bool { … }
```

Now it takes two `String`s and returns a `Bool`. You can call it, and you can generate inputs for it —
and a generator does not need to suspect anything, which is the whole point. The law *"a grandchild is
never an immediate child, however its names repeat"* fails on the first run, and it fails as a minimal
pair of strings rather than as a wrong list of files.

**Captures are not impurities.** That predicate captures `currentPath`, a `var` on the enclosing type,
and that does not disqualify it: lift the body out and the capture simply *becomes a parameter*.
Refusing captured state would refuse this rule's most valuable finding — which is the bug site above.
What no extraction rescues is a closure that **writes** to what it captured; its job *is* the side
effect, and that one is refuted by the purity oracle
(`SwiftEffectInference.PurityInferrer`, the same one the function rule uses).

The rule fires on a pure closure passed to a **fixed list** of higher-order operations — the ones whose
closure arguments are *supposed* to be functions — and each one names the law worth stating once the
closure has a name:

| operation | law worth stating once it has a name |
|---|---|
| `sorted`, `sort`, `min`, `max`, `partition` | a comparator must be a **strict weak ordering** — irreflexive, antisymmetric, transitive. One that is not can *crash* `sorted(by:)`, and no example test tells you which triple broke it |
| `filter`, `first`, `contains`, `allSatisfy`, `drop`, `prefix`, `removeAll` | a predicate is a total function of its inputs — state what it must accept and reject |
| `map`, `compactMap`, `flatMap` | a transform is a function of its input |
| `reduce` | the combine step is usually associative, often with an identity — both checkable, neither by example |

The list is deliberately closed. `Task { }`, `withAnimation { }` and `DispatchQueue.main.async { }`
take closures too, and a closure run for its *effects* is not a property waiting to be named.

**Body size is the wrong axis wherever a closure can be wrong on one line.** The temptation is to
floor every operation on statement count, and for comparators and predicates that is a mistake,
because **the shortest ones are the wrong ones**:

```swift
files.sorted { $0.name <= $1.name }                            // reflexive — not a strict weak ordering
tasks.sorted { $0.a > $1.a || $0.b < $1.b }                    // intransitive
files.filter { $0.path.hasPrefix(parent) && $0.path != parent }  // one off-by-one from wrong
```

Each fits inside any floor, and the first two can crash `sorted(by:)`. So both kinds ask a sharper
question instead — **can this be got wrong at all?** — in their own terms:

| kind | free when… | example that is free | example that earns the finding |
|---|---|---|---|
| **comparator** | the ordering is inherited whole from `Comparable`: one strict comparison (`<`/`>`), same member path both sides, the two parameters as the two bases | `{ $0.date > $1.date }` | a branch, a `\|\|`, a second key, a `compare(_:)` call |
| **predicate** | it makes no decision — it surfaces a stored `Bool`, or states an identity | `{ $0.isEnabled }`, `{ $0 == fileURL }` | a `&&`, a *relational* comparison, a call, a branch |

An equality is **identity, not a decision**: `removeAll { $0 == fileURL }` means "remove this element"
and nothing more, `Equatable` already guarantees everything there is to guarantee about it, and there
is no boundary for a generator to find. A *relational* comparison is a different matter and does fire
— `{ $0.count > 0 }` and `{ $0.updated < $0.created }` are thresholds and orderings, and those are
exactly the decisions that come out one boundary wrong.

Transforms and reducers keep the size floor, and legitimately: a one-statement `map { $0.name }` is a
**projection**, and unlike a predicate or a comparator it carries no law that a single expression
could violate — there is nothing for it to be inconsistent with.

Every exclusion serves one end: **a finding must be worth the refactor it asks for.** Unreachable is
only a problem when there is something in there worth reaching, and a rule that fires on every `map`
in a codebase teaches people to switch the category off.

### Non-Violating Examples

```swift
// The ordering is free — inherited from Comparable, cannot be got wrong.
// One strict comparison, same key both sides, the two parameters as the two bases.
files.sorted { $0.date > $1.date }
names.sorted { $0 < $1 }
items.min { $0.count < $1.count }

// A projection, not a property. Naming it buys nothing.
let names = items.map { $0.name }

// A predicate that decides nothing: a stored Bool, surfaced. It cannot disagree with
// itself, so there is no law to state and nothing to generate inputs against.
let active = items.filter { $0.isEnabled }
let shown = items.filter { !$0.isHidden }
let folders = items.filter { $0.file.isFolder }

// Identity, not a decision. `removeAll { $0 == fileURL }` means "remove this element"
// and nothing more — Equatable already guarantees all there is to guarantee.
selectedFiles.removeAll { $0 == fileURL }
let busy = uploadStatus.values.contains { $0 == .uploading }

// Not a collection operation. A closure run for its effects is not a property
// waiting to be named — the operation list is deliberately closed.
Task { await refresh() }
withAnimation { isExpanded.toggle() }
DispatchQueue.main.async { self.spinner.stopAnimating() }

// Impure: I/O, the clock, randomness, or anything that can trap.
// Generating inputs proves nothing if the output does not depend only on them.
let valid = items.filter { item in
    print(item)
    return item.isValid
}

// Writes to a capture. No extraction rescues this one — its job IS the side effect,
// and lifting the body out would not turn `runningTotal` into a parameter.
let flags = items.map { item in
    runningTotal += item.amount
    return item.isValid
}

// Test files are skipped entirely.
```

### Violating Examples

```swift
// A predicate with real logic in it, and no name. THE motivating case: this one
// contains a bug (`replacingOccurrences` strips every match, not the leading one),
// and no test could reach it, because there was nothing to call.
let immediateChildren = allFiles.filter { file in
    let relativePath = file.path.replacingOccurrences(of: currentPath, with: "")
    return relativePath.split(separator: "/").count <= 1
}

// A comparator with a branch, and a key reached through a call. The ordering is not
// free: localizedCaseInsensitiveCompare is locale-dependent, and the folders-first
// branch is exactly the kind of thing that breaks transitivity.
files.sorted { file1, file2 in
    if file1.isFolder != file2.isFolder { return file1.isFolder }
    return file1.name.localizedCaseInsensitiveCompare(file2.name) == .orderedAscending
}

// Not even irreflexive. `<=` is reflexive, so it is not a strict weak ordering, and
// `sorted(by:)` is within its rights to crash on it. The size floor could never have
// caught this — it is the shortest a comparator gets, and it is wrong.
files.sorted { $0.name <= $1.name }

// Two keys, one line: the classic way to break transitivity.
tasks.sorted { $0.priority > $1.priority || $0.name < $1.name }

// A predicate with a rule in it, on one line. A size floor drops this, and it is one
// off-by-one from wrong — is the parent itself an immediate child of itself or not?
files.filter { $0.path.hasPrefix(parent) && $0.path != parent }

// A relational comparison is a threshold, and thresholds come out one boundary wrong.
items.filter { $0.count > 0 }
items.filter { $0.updated < $0.created }

// A predicate reached through a call. Locale-dependent matching has real laws: an empty
// query matches everything, a match implies a substring, matching ignores case.
files.filter { $0.name.localizedCaseInsensitiveContains(query) }

// A transform with logic in it — a function of its input, waiting for a name.
let labels = files.map { file in
    let size = Double(file.byteCount) / 1_000_000
    return "\(file.name) (\(size) MB)"
}

// A reducer. The combine step is usually associative and often has an identity —
// both are laws a property test can check and an example cannot.
let total = items.reduce(Money.zero) { running, item in
    let taxed = item.price * (1 + item.taxRate)
    return running + taxed
}
```

### What the seed manifest carries

Each finding contributes a seed to `--format pbt-seeds` with a `role` naming what the closure **is**
— `comparator`, `predicate`, `transform` or `reducer` — taken from the same classification that
picks the law sentence above. Before that field existed the manifest carried `{file, line, symbol,
rule, kind}`, so all 208 findings reached `swift-infer` as an undifferentiated
`extractable-kernel`, and the classification this rule had already made was thrown away at the
boundary.

The role matters most here precisely because a closure seed can never be *analysed*: it has no name
to call, so the downstream tool can only report it as work for a human. The role is what makes that
report say something — "a comparator, which owes a strict weak ordering" rather than "a kernel at
line 42". `comparator` and `predicate` are role-*entailed*: a correct implementation cannot fail
their law. `transform` and `reducer` are conjectures, and the manifest says so rather than
overclaiming.

For the same reason the seed carries **no test-reachability claim**. Analysable kinds are demoted to
`restricted-function` when their symbol is out of `@testable import`'s reach; `extractable-kernel` is
not analysable, so the export layer returns before consulting reachability. A closure has no
declaration to widen, and lifting it into a named function — which is the whole ask — creates one
whose access level the reader picks. Read the absence of a reachability signal as *"not asked"*,
never as *"reachable"*.

### Not listed in the default report

This rule is a **census**, and on a real codebase it is a large one: 208 findings here, alongside
464 from [Pure Function Property-Test Candidate](pure-function-candidate.md) — together **76% of
everything the linter prints**. A pure function is not a defect and there is nothing to fix per
line, so enumerating them buries the findings that *are* defects. During this project's own road
test the linter found a real bug in its configuration code, reported it correctly, and the finding
went unread in exactly that pile. Volume that large does not inform; it functions as silence.

So `--format text` counts these findings in its summary and names them in a footer, but does not
print one line each:

```
Found 884 issues (82 warnings, 802 info)

672 of these are property-test candidates, not listed above (464 Pure Function …, 208 Pure Closure …).
  See them:  --categories testability
  Use them:  --format pbt-seeds > .pbt/seeds.json
```

**Nothing is filtered out of detection.** The rule still runs, still counts toward the summary and
the exit code, and still populates the seed manifest — `--format pbt-seeds` is the pipeline's input
and would be emptied by any change that suppressed the rule itself. `--format json`, `csv` and
`html` also stay complete: a machine consumer filters for itself. Only the human listing is
shortened, and naming `testability` in `--categories` restores it in full.

This is [`../archive/PBT_TESTABILITY_RULES_SCOPE.md`](../archive/PBT_TESTABILITY_RULES_SCOPE.md) decision 5 —
*"Rule 5 opt-in (info, advisory)"* — arriving late, in the only place it can arrive without
breaking the handoff.

### Known Limitations

- **A closure reached through a call always fires**, in both kinds:
  `{ $0.name.lowercased() < $1.name.lowercased() }` and `{ $0.name.hasPrefix("_") }` are both
  reported, because the rule cannot see that the call is total and deterministic. This errs towards
  reporting on purpose — the *interesting* closures in real code are call-shaped, and every locale
  bug lives in one — but it will occasionally name something that did not need naming.
- **A floating-point key is a false negative.** `{ $0.score < $1.score }` on a `Double` is *not* a
  strict weak ordering once a `NaN` is in the collection — but nothing in the syntax says whether
  `score` is a `Double`, so it is treated as a free ordering and skipped. Naming it is what would
  surface this, which is the rule's advice anyway.
- **An equality against a computed value is skipped.** `{ $0.normalized == target }` reads as identity
  and is treated as free, even though `normalized` may be doing real work. The decision is in the
  property, not in the closure — and the property rule will see it.

### Remediation

Lift it into a named function. Anything it captures becomes a parameter, and what is left is a pure
function you can generate inputs for.

That is the whole fix, and the payoff is immediate and local: the logic becomes **addressable**. You
can call it, you can enumerate its inputs, and a failure points at the function rather than at a list
of files three layers up.

The same refactor has an argument behind it that has nothing to do with testing. Adam Tornhill's
[*Beyond Lambdas: Raising the Abstraction Level*](https://adamtornhill.substack.com/p/beyond-lambdas-raising-the-abstraction)
makes the case on readability: a lambda optimises for writing at the cost of reading, so intent stays
opaque where a named function would carry the domain, and an abstraction does not have to be reused to
earn its place. Worth reading beside this rule, with two differences noted. It argues from worked
examples rather than from measurement, which is not what his code-analysis work leads you to expect.
And his criterion is wider than this rule's — he would name every step of a pipeline for the
narrative, including the `{ $0.date > $1.date }` listed above as free. The agreement is on the fix,
not on when to ask for it.

<details><summary>It also unblocks the rest of the toolchain</summary>

Once the closure has a name, [Pure Function Property-Test Candidate](pure-function-candidate.md) can
seed it, and `swift-infer discover --seeds` will propose its laws — nothing can index a nameless
closure.

This is a consequence of naming it, not a reason to. If the only argument for a refactor were that it
suits a tool, the right response would be to fix the tool.

</details>

---
