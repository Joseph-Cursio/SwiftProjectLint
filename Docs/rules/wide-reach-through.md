[← Back to Rules](RULES.md)

## Wide Reach-Through

**Identifier:** `Wide Reach-Through`
**Category:** Architecture
**Severity:** Info

### Rationale
The Law of Demeter is usually enforced by counting dots. That measures the wrong thing.

A chain's *depth* says how many hops one expression takes. What actually makes a change to a
collaborator ripple outward is *width* — how much of that collaborator's shape a file has
learned. A file that reads seven different members of a `candidate` depends on `candidate`'s
internal structure however short each individual chain is, and in practice those chains are
short: the widest reach-through found while building this rule consisted entirely of two-dot
accesses, which [Law of Demeter](law-of-demeter.md)'s three-dot threshold cannot see at all.

The two rules are complements, not alternatives:

| Rule | Measures | Fires on |
|---|---|---|
| [Law of Demeter](law-of-demeter.md) | depth of one chain | `a.b.c.d` — four levels in one expression |
| **Wide Reach-Through** | width across one file | `x.cand.one`, `x.cand.two`, `x.cand.three` — three members of one target |

### Discussion
`WideReachThroughVisitor` runs cross-file. The *trigger* is per-file, but the idiom filter in
Phase 2 needs to see every file before it can tell an idiom from a fault.

Both rules share [`DemeterChainFilter`](../../Packages/SwiftProjectLintRules/Sources/SwiftProjectLintRules/Architecture/Visitors/DemeterChainFilter.swift)
for the question "is this chain reaching into a collaborator's internals?" — the `self`/`super`
exemptions, type-prefixed namespace traversals, keypath literals, binding projections, leading
underscores, SwiftSyntax and geometry members, and the well-known Foundation prefixes. Those
lists are the accumulated result of running the depth rule over real repositories, and keeping
one copy is deliberate: two copies would drift into a chain being exempt from one rule and
flagged by the other for no reason a reader could discover.

**Phase 1 (walk).** Every member-access chain of at least **2** dots that survives the shared
filter contributes one `(file, target, member)` fact. The *target* is the penultimate
component — the thing being reached into — and the *member* is what was asked of it. In
`inputs.candidate.carrierKind` the target is `candidate` and the member is `carrierKind`.
Chains that are the callee of a call are skipped, since those are method invocations rather
than reaches for data, and only the outermost access of a chain is read so `a.b.c` counts once
rather than once per hop.

**Phase 2 (`finalizeAnalysis`).** Facts are grouped by `(file, target)`. A pair reports when it
has at least **3 distinct members** and is not an idiom.

**Why three and not two.** Two is the noise floor, and the reason is specific: a two-field value
type read in full is not structural knowledge, because there is no structure to know. The
measurement is in [Measured yield](#measured-yield) below.

**The idiom filter.** A `(target, member-set)` signature occurring *identically* in at least
**3** files is suppressed everywhere it occurs. A genuine violation is idiosyncratic — one site
that happens to have internalised a shape. The same members read the same way across several
files is a type being used as designed. `identity.(display, normalized)` appeared in seven
separate files of SwiftInferProperties: seven uses of a two-field type, and zero problems.

**A single member reached repeatedly is deliberately not reported.** `site.location.filePath`
eight times across five files is a missing forwarding accessor — `var filePath: String {
location.filePath }` — which is a five-minute cleanup with no design consequence. It is a true
Demeter violation and this rule stays silent about it on purpose, because a rule that reports
it buys one trivial fix at the cost of every value-navigation false positive in the codebase.

#### Known limitations / false-positive posture
- **Targets are matched by name, not by type.** There is no type resolution, so two unrelated
  things both called `manifest` are the same target to this rule. The per-file grouping contains
  most of the damage — the members have to co-occur in one file — but a file juggling two
  different `config` values will merge them.
- **The idiom filter can mask a genuinely repeated mistake.** If the same reach-through is
  copy-pasted into three files, it looks exactly like an idiom and is suppressed. The filter
  trades this away knowingly: the measured alternative was seven findings for one correctly-used
  value type.
- **A wide but legitimate aggregate still fires.** A type whose whole job is to be read
  field-by-field — a parsed manifest, a decoded response — will report, and the answer may
  legitimately be "yes, and that is fine." This is part of why the rule is `Info` and opt-in.
- **Members reached through a call are invisible.** `inputs.candidate().carrierKind` does not
  contribute, since function-call roots are exempt.
- **Test and fixture files are excluded entirely.**

### Non-Violating Examples
```swift
// Two members of a small value type — below the threshold, and not structural knowledge.
func show(s: Suggestion) -> String {
    "\(s.identity.display) (\(s.identity.normalized))"
}
```

```swift
// One member, reached many times. A missing forwarding accessor, not a design problem.
func a(site: Site) -> String { site.location.filePath }
func b(site: Site) -> String { site.location.filePath }
func c(site: Site) -> String { site.location.filePath }
```

```swift
// Reaching through your own storage is not coupling to a collaborator.
func run() -> String {
    "\(self.candidate.one)\(self.candidate.two)\(self.candidate.three)"
}
```

```swift
// Framework traversal, not object-graph navigation.
node.signature.parameterClause
node.signature.returnClause
node.memberBlock.members
```

### Violating Examples
```swift
// ActionSequenceStubEmitter.swift — every chain is two dots, so no depth threshold sees this.
// The emitter knows seven of `candidate`'s members; a change to the candidate lands here.
let isTCA       = inputs.candidate.carrierKind == .tca
let isMobius    = inputs.candidate.carrierKind == .mobius
let actionFirst = inputs.candidate.carrierKind == .reSwift
let stateInit   = "\(inputs.candidate.stateTypeName)()"
let qualified   = inputs.candidate.qualifiedName
let enclosing   = inputs.candidate.enclosingTypeName
let shape       = inputs.candidate.signatureShape
let isAsync     = inputs.candidate.isAsync
```

```swift
// PackageGraph.swift — four members of `manifest` in one file.
node.manifest.targets
node.manifest.directory
package.manifest.libraryProducts
package.manifest.packageName
```

**Suggestion:** Move the logic that needs these members onto the target, or pass the specific
values the file needs. When the target is a value type the caller genuinely must inspect, a
method that answers the caller's actual question — `candidate.reducerCall()` rather than four
reads of its parts — removes the finding and the coupling together.

#### Measured yield

Three repositories, first-party sources only, the rule as it ships:

| Repo | Source files | Findings |
|---|---|---|
| SwiftProjectLint | 518 | **2** — both `manifest`, in `PackageGraph` and `UndeclaredTargetDependencyVisitor` |
| SwiftPropertyLaws | 366 | **0** |
| SwiftInferProperties | ~690 | **24** |

SwiftPropertyLaws returning zero is the expected shape rather than a failure: it is a library of
property-law definitions over stdlib value types, which is not code that accumulates knowledge of
an object graph.

**The threshold measurement.** Dropping `minDistinctMembers` to 2 and re-running
SwiftInferProperties gives **59** findings against the shipped **24**. All 35 additions are
exactly-two-member pairs, and they are dominated by the class the threshold exists to exclude:

```
typeShapesByName.(keys, values)      — a dictionary, read as a dictionary
generator.(sampling, source)         — a two-field value type, read in full
location.(file, isResolvable)
summary.(declaringFile, name)
surface.(includesAlgebraic, includesInteraction)
```

`typeShapesByName.(keys, values)` is the clearest: there is no structure being leaked, only a
`Dictionary` being used. Reading both halves of a pair is not knowledge of a shape when the shape
*is* the pair. Hence three.

**On the depth rule's numbers.** An earlier estimate of this rule's yield was produced by running
[Law of Demeter](law-of-demeter.md) at a two-dot threshold and grouping its output. That
undercounts: that rule emits one finding per `(declaration, target)`, so it samples a single
member per declaration rather than every member a file reads. It put SwiftInferProperties at 13
where the real rule reports 24. The figures above are all from the rule as it ships.

---
