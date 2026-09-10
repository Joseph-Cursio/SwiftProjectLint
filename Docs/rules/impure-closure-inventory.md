[← Back to Rules](RULES.md)

## Impure Closure Inventory

**Identifier:** `Impure Closure Inventory`
**Category:** Testability
**Severity:** Info

### Rationale

**The tool has always computed this list and always thrown it away.**

`Pure Closure Property-Test Candidate` walks every closure passed to `filter`, `sorted(by:)`, `map`,
`reduce` and the rest; asks the shared purity oracle; and reports the ones that pass. The ones that
fail are dropped without a word. The same is true of the function-level census. So the two largest
numbers this tool publishes are an inventory of **what is already testable in principle**, and the
complement — the list of things standing in the way — is recomputed on every run and discarded.

For a reader whose goal is *"start property-testing this codebase"*, the complement is the half they
act on. A pure closure needs a name; that is a five-minute refactor and the census already points at
it. An **impure** closure is the actual obstacle, and nothing counted them.

The sweep that produced this rule had reached the same conclusion from the other direction two runs
earlier:

> Only two of the seven shapes carry a law worth a property test. A predicate's obligation is
> totality and a transform's is being a function of its input; both are nearly always true and
> rarely interesting, and they are 806 of the 887.

The interesting inventory is the one nobody printed.

### This is a census, not a defect report

An impure closure is ordinary, correct Swift. `forEach { save($0) }` is fine. `sorted { $0.date <
$1.date }` reading a stored date is fine. The finding does not say *this is wrong*. It says **here is
where the effects are, and here is what to separate if you want a kernel** — which is the argument
`Extractable Total Kernel` makes one case at a time, made as a census instead.

Consequences of that, all deliberate:

- **`info`, opt-in**, like the two censuses it sits beside.
- **Not a seed.** It carries no `role`, and it is absent from `CandidateInventory` and
  `PBTSeedsFormatter`. A downstream tool must not point analysis at these findings.
- **Not ranked with the refactor prompts.** A run reporting these has not found that many problems.

### Measured, and it is smaller than the issue assumed

Over 26 repositories: **31 impure closures against 875 pure ones — 3% of the qualifying
population.**

| Cause | n | Commonest witnesses |
|---|---:|---|
| Side effect | 17 | `FileManager` (7), `resourceValues` (5), `contentsOfFile` (3) |
| Captured write | 8 | `changed`, `resolvedCount`, `applied` |
| Partiality | 4 | `!` (3), `preconditionFailure` (1) |
| Nondeterminism | 2 | `random`, `UUID` |

The issue that asked for this rule guessed at *"you have 400 untestable closures"*. The real number
is 31, and the reason is worth stating because it is a fact about the design rather than about the
corpus: **the shared gate already excludes the call sites where effects live.**
`CollectionOperation` is a fixed list — `sorted`, `filter`, `map`, `reduce` and their relatives —
chosen because *"a closure run for its effects is not a property waiting to be named"*. `forEach`,
`Task { }`, `withAnimation { }` and `DispatchQueue.main.async { }` are not on it. Nor are
single-expression transforms, which the size floor drops.

So this counts the impure closures **among the ones that were supposed to be functions**, and that
is the population where an impurity is surprising. Read as "every impure closure in the codebase" the
number is wrong by a wide margin; read as "law-bearing call sites doing something they should not",
31 is the whole list, and the 17 side-effect rows are the ones worth opening.

That partly *answers* the issue instead of fulfilling it. The complement the tool was discarding
turned out to be small, which was not knowable before the oracle could name a reason — the estimate
available beforehand was a grep, and the grep was off by 3.5× in one direction on one repository and
3× the other way on another.

### The same population as the census, exactly

This rule runs the *identical* gate as `Pure Closure Property-Test Candidate` — the same fixed list
of higher-order operations, the same "does this hide a law worth stating" filter, the same forwarding
check, the same test-file exclusion — and differs in **one clause**: where the census requires the
purity oracle to return no refutation, this requires it to return one.

That is what makes the two numbers complements rather than two unrelated counts. It is also why the
vocabulary those gates are written in now lives in its own file (`CollectionOperation`) instead
of privately inside the census: two rules that must agree on which call sites count cannot each hold
their own copy of the answer. A test pins the partition directly — over the same source, no closure
is reported by both rules, and their sum is the population the shared gate admits.

### Why the reason is in the message

*"You have 400 untestable closures"* is a number. *"This one reads the clock, that one writes a
file"* is a work list. The difference is whether the refutation names the construct it found.

Until recently it could not. `SwiftEffectInference` answered `pure` / `pureButPartial` / `refuted`
and kept the reason private, so a rule written then could have said *this closure is impure* and not
what makes it so. `PurityRefutation` publishes the reason, and this rule is the first consumer of it.

### The five causes, and what each one is worth

The oracle has eleven refuters. They are grouped into five on one test: **does a reader do something
different about this than about the others?** Where the answer was no, the cases were merged — which
is why the two nondeterminism refuters collapse to one row, and the two side-effect refuters to
another.

| Cause | Example witness | What to do |
|---|---|---|
| Side effect | `print`, `FileManager`, `String(contentsOf:)` | There is usually a decision buried here that the effect is carrying. Lift the decision out; leave the effect at the call site. |
| Nondeterminism | `Date()`, `.shuffled()`, `Locale.current` | Inject the source. `Non-Injected Nondeterminism` reports the same line from the other direction. |
| Partiality | `!`, `try!`, `as!`, `fatalError` | Make it total. **The cause most likely to be a latent bug** — a property test over generated inputs would crash rather than falsify. |
| Captured write | `total`, `self` | **Nothing.** The write is what the closure is for, and no signature change rescues it. Listed as a boundary of the pure region. |
| Declared effect | `async`, `throws` | A different kind of thing from a predicate. If the effect is incidental, the pure part usually splits out. |

The captured-write row is the one worth reading twice. It is the only cause whose honest advice is
*take no action*, and a census that could not say that would be pushing readers to "fix" closures
that are already correct.

### What this rule does not do

It does not count impure **named functions**. `Pure Function Property-Test Candidate` has the same
asymmetry and the same complement waiting behind it, and extending this to declarations is a separate
decision — the population is an order of magnitude larger and the shape gate is different.

It does not attempt a denominator from outside the oracle. A grep for closure-taking collection
operations is not one: it returns 201 sites for one repository against 56 reported candidates, and 62
for another against 200, because it misses trailing closures on the following line and the
`sorted(by:)` and `first(where:)` spellings. Any figure has to come from the oracle itself, which is
what this rule is.

### See also

- [Pure Closure Property-Test Candidate](pure-closure-candidate.md) — the other half of the partition
- [Extractable Total Kernel](extractable-total-kernel.md) — the same argument, one case at a time
- [Non-Injected Nondeterminism](non-injected-nondeterminism.md) — the `nondeterminism` cause, reported as a defect
- [Unreachable Effect Closure](unreachable-effect-closure.md) — a captured write in a *callback*, where it is a defect
