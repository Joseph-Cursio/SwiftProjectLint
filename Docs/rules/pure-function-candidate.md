[← Back to Rules](RULES.md)

## Pure Function Property-Test Candidate

**Identifier:** `Pure Function Property-Test Candidate`
**Category:** Testability
**Severity:** Info

### Rationale
Most testability rules flag what makes code *hard* to test. This one is the positive signal: it surfaces functions that are already an ideal fit for property-based testing. A free or `static` function that takes inputs, returns a value, isn't `async`, and shows no obvious side effects is — to a first approximation — pure and total. Those are exactly the functions where properties (round-trips, invariants, idempotence, commutativity) pay off, and they're the seeds the `lint → infer → verify` pipeline hands to `swift-infer` to propose properties automatically.

### Discussion
`PureFunctionCandidateVisitor` flags a `FunctionDeclSyntax` that:
- is free (top-level) or `static` — instance methods can read mutable `self`, so they're excluded,
- takes at least one parameter,
- returns a value a test can compare with `==` (see [What a test can assert on](#what-a-test-can-assert-on)),
- is not `async`,
- has a body with no obvious impurity markers — `print`, `NSLog`, `FileManager`, `URLSession`, `UserDefaults`, `NotificationCenter`, `DispatchQueue`, the `arc4random` family, `.random` / `.randomElement` / `.shuffled`, and
- if it `throws`, raises only its **own** errors — see [Throwing candidates](#throwing-candidates-pure-but-partial).

The rule is deliberately conservative: it would rather stay silent than label an impure function pure. It is `info` severity (a suggestion, not a problem) and skips test files.

```swift
// Flagged — a clean property-test candidate
func clamp(_ x: Int, to range: ClosedRange<Int>) -> Int {
    min(max(x, range.lowerBound), range.upperBound)
}
// e.g. property: range.contains(clamp(x, to: range)) for all x
```

### Non-Violating Examples
```swift
// No return value — nothing to assert on
func log(_ message: String) { print(message) }

// No parameters — no input domain to quantify over
func makeDefault() -> Config { Config() }

// Impure body
func save(_ data: Data) -> Bool {
    UserDefaults.standard.set(data, forKey: "k"); return true
}

// Instance method reading MUTABLE state — two calls with the same argument can differ,
// so it is a function of nothing a test can pin down
struct Counter { var n = 0; func next() -> Int { n + 1 } }

// Instance method reading state this file cannot resolve — doubt refutes
extension Widget { func scaled(_ n: Int) -> Int { hidden * n } }

// THROWS by propagation — the error comes from a callee this rule cannot see, and so does
// whatever else that callee does. Doubt refutes.
func read(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }

// An OPTIONAL tuple — a tuple is never Equatable, so an Optional of one has no `==`
func split(_ line: String) -> (String, String)? { nil }

// A tuple NESTED in a tuple — the outer `==` needs Equatable elements, and the inner tuple is not one
func tagged(_ x: Int) -> ((Int, Int), String) { ((x, x), "pair") }

// THROWS and returns a TUPLE — the law narrows with `try?`, so it would compare two Optionals of a
// tuple, which have no `==`
func parsePair(_ text: String) throws -> (Int, Int) {
    guard let value = Int(text) else { throw ParseError.bad }
    return (value, value)
}
```

### Violating Examples
```swift
// Pure, total, free function with inputs and an output — "a function of its inputs"
func add(_ a: Int, _ b: Int) -> Int { a + b }

// Static, pure
enum Geometry {
    static func area(width: Double, height: Double) -> Double { width * height }
}

// INSTANCE METHOD reading nothing from `self` — a free function that happens to live in a type
struct Calc { var total = 0; func add(_ a: Int, _ b: Int) -> Int { a + b } }

// INSTANCE METHOD reading only immutable stored state — "a function of `self` and its inputs".
// The test builds a `Pricing` first; that is a chore, not an obstacle.
struct Pricing { let rate: Double; func discounted(_ amount: Double) -> Double { amount * rate } }

// Nullary, over immutable stored state — `self` IS the input. Vary the value, not the arguments.
struct Receipt { let amount: Double; func formatted() -> String { String(amount) } }

// THROWS its own error — "pure but partial". The law narrows to the success set.
func parse(_ text: String) throws -> Int {
    guard let value = Int(text) else { throw ParseError.bad }
    return value
}

// A TUPLE of Equatable values — `==` compares it element by element.
// e.g. property: minMax(a, b) == minMax(b, a)
func minMax(_ a: Int, _ b: Int) -> (min: Int, max: Int) { a < b ? (a, b) : (b, a) }
```

### What a test can assert on

A candidate is only worth seeding if a test can compare two of its results with `==` — that is
what every law `swift-infer` writes ends in. Whether it can is read off the return type (or a
computed property's annotation; both go through one check):

| the result type | assertable |
|---|---|
| a stdlib `Equatable` type — `Int`, `String`, `Bool`, `Double`, `Date`, `URL`, `Data`, … | yes |
| a project type declaring `Equatable` / `Hashable` / `Comparable`, or an enum with no associated values | yes |
| `T?`, `T!` or `[T]` of one of those | yes |
| `Self` | when the enclosing type is one of those |
| a tuple of **two to six** of those, labelled or not — `(text: String, didTruncate: Bool)` | yes, if the declaration does not throw |
| `(T)` | as `T` — parentheses are not a tuple |
| `Void` / `()` | no — nothing to assert on |
| an Optional or Array *of* a tuple — `(A, B)?`, `[(A, B)]` | no (but `Array<(A, B)>`, spelled generically, is admitted — see below) |
| a tuple returned by a function that `throws`, or by a `get throws` property | no — its law compares `try? f(x)`, an Optional of the tuple |
| a tuple nested in a tuple, or with a `Void` or variadic element | no |
| a tuple element whose generic argument has no `==` — `(Array<Widget>, Int)`, `([String: Widget], Int)` | no, as `([Widget], Int)` is not |
| a tuple of seven or more | no — Swift's tuple `==` stops at six |
| a closure, an existential (`any P`), a typealias, `Outer.Inner`, a type the project index does not know | no |

The tuple rows are Swift's own: the standard library overloads `==` for tuples of two to six
`Equatable` elements, but a tuple never conforms to `Equatable` itself. So a tuple is assertable only
as the **whole** result — wrap it in an Optional or an Array, or nest it in another tuple, and there
is no `==` left to call. A throwing function wraps it in an Optional without saying so: the law it is
handed narrows to the inputs that return by comparing `try? f(x)` on both sides (see [Throwing
candidates](#throwing-candidates-pure-but-partial)), and that is an Optional of the tuple.

Tuples were refused from the gate's first day (a4427b8c), grouped with closures as having *"no
nominal base"*. That is true of the lookup, and not of `==`. Admitting them added **46 seeds of
6,111, none lost**, across 14 repositories — every one a pair from a function that does not throw,
such as `(hash: UInt64, mass: Int)` or `(text: String, spans: [MathSpan])`, and 27 of them
`private`. Two of the 46 are not pure: `checkOne` runs a build and `merging` scans the disk, each
through a project function the purity check does not follow. The tuple refusal was hiding them, as
the `throws` exclusion once hid I/O (see [Throwing candidates](#throwing-candidates-pure-but-partial));
it is the purity check's limit, and the same limit admits such a function returning a `String`.
SwiftAssist's `String.prefix(utf8Bytes:) -> (text: String, didTruncate: Bool)` motivated the change —
and is still not a candidate, for a different reason: it reads `isEmpty` and `utf8` without `self.`,
a member of a carrier the project does not declare (see [Instance methods](#instance-methods)).

For a whole result, generic arguments are not checked. `Array<Widget>` and a dictionary's value type
pass on the container's name, so `[String: (Int, Int)]` and `Array<(A, B)>` are admitted although
neither has `==`. That predates tuples, and checking it would withdraw seeds, so it is left for a
change measured on its own. Inside a tuple they are checked: an element that is a generically spelled
`Array`, or a dictionary, must hold values a test can compare, so `(Array<Widget>, Int)` is refused
just as `([Widget], Int)` is. A dictionary's key and a `Set`'s element are not looked into — both
must be `Hashable`, so both are `Equatable` whatever the project index knows.

### Instance methods

Instance methods are candidates. What decides candidacy is **what a method reads from `self`**, not
whether it is free-standing:

| the body reads | verdict |
|---|---|
| nothing from `self` | **a function of its inputs** — same as a free function |
| only *immutable* stored properties | **a function of `self` and its inputs** — build a `self`, then generate the arguments |
| *mutable* or *computed* state | not a candidate — two calls with the same argument can differ |
| an identifier this file cannot resolve | not a candidate — doubt refutes |

Refusing instance methods outright (the old behaviour) left this rule nearly blind on application
code, where almost all logic is instance methods. Doubt still refutes, though: purity is the bottom
of the effect lattice and the most dangerous place to land wrongly, so an identifier that cannot be
tied to a parameter, a local, or a type is assumed to be instance state — even when it is a global.
Under-suggesting costs a missed test; over-suggesting costs a generated test that runs impure code
and lies about the result.

**A stdlib carrier is a value type, and the analyzer says so.** `extension String { … }` extends a
`struct`, so reading the string it extends is a read of a value and the table above applies. This
used to be decided from the set of *project* declarations alone, so every stdlib carrier answered
"not a value type" and the reference-type path refused any member touching `self`. Measured before
the fix: **0 of 88** parameterless members of extensions on foreign carriers were seeds, across 23
repositories, against 51.4% for extensions on carriers the project declares. Restoring the answer
recovered **7 seeds of 4,947, none lost** — mostly `switch self` over `extension Optional where
Wrapped == …`, plus `String.globPatternToRegex()`.

Only `self` *as a whole value* is admitted. A member reached through it — `self.count` on a
`String` — still refuses, because the project declares no stored properties for a type it does not
own, and admitting an arbitrary member of a foreign type would be a general relaxation rather than
an answer the analyzer already had. A carrier that is neither a project declaration nor a known
stdlib value type — `extension NSTextView` — refuses as before.

**Swift 5.7's shorthand optional binding is a read, not a binding.** `if let tagFilter` — with no
`=` — introduces nothing; it takes its value from whatever `tagFilter` already meant. So the name is
resolved rather than assumed local, and the table above applies to it: a shorthand-bound stored
`let` is a function of `self`, a shorthand-bound stored `var` is not a candidate, and a name this
file cannot see refutes. Rebinding a local still works, because the local's own `let` or `var` is
what bound the name.

Treating it as a fresh local admitted methods that read mutable instance state. The three arms below
are the same logic, and only the first was a candidate:

```swift
if let tagFilter, !item.tags.contains(tagFilter) { return false }        // was a candidate
if let filter = self.tagFilter, !item.tags.contains(filter) { … }       // correctly refused
guard let value = tagFilter else { return true }                        // correctly refused
```

Measured across 13 repositories: **five seeds withdrawn of 4,670**, including `EditorFormatter`'s
`selectedText`, which shorthand-binds a `weak var textView: NSTextView?` — a live view object.

**A key-path component is a member of its root, not of `self`.** In `rules.filter(\.value.enabled)`,
`value` and `enabled` name members of the dictionary's element, and in `words.map(\.count)` of the
string. The analyzer used to collect them as bare identifiers, find no local and no stored property
by that name, and refuse the method as reading instance state it could not see. Through the
clean-method catalog the refusal then reached every sibling that called it. Only the component's
name is skipped: the argument of a subscript component is a real read, so a method doing
`rows.map(\.[index])` over a stored `var index` is still refused.

Measured across 23 repositories: **52 seeds added of 6,527, none withdrawn**. Every one of the 52
had a key path as its only blocker, directly or in a sibling it calls. Read by hand, 45 are
functions of their inputs and their own immutable state. Seven are not, each through a limit that
predates this change and that the refusal had been hiding:

- **A `let` holding a reference type.** `PreviewChangesView.rulesSummary` reads `model.changes`
  through `let model: LivePreviewModel`, an `@Observable` class whose `changes` an asynchronous lint
  pass rewrites. A `let` binding is treated as immutable whatever its type; the same view's
  `addedCount` and `removedCount` were already seeds for the same reason.
- **A protocol requirement as callee.** SwiftMutator's `MuterProcess.find` (both overloads),
  `findExecutable` and `which` reach `runProcess(url:arguments:)`, a protocol requirement that
  spawns `/usr/bin/find` or `/usr/bin/which`. The clean-method catalog reads no protocol
  declarations, and a same-named overload makes the call look like one it has cleared.
- **A Foundation initializer that reads the environment.** `HTMLFormatter.detailedListSection`
  calls `URL(fileURLWithPath:)`, which resolves a relative path against the current directory and
  asks the filesystem whether it is a directory. The purity oracle treats it as a value initializer.
- **Hash-ordered output.** `SwiftUIManagementVisitor.findRelatedViews` returns `Array(Set(…))`, whose
  order varies from process to process. The oracle has no model of order that depends on hash
  seeding.

### Constructions: what building a value runs

**A function that builds a value of a package type runs that type's construction**, and its body
does not show it. `public struct HealthRecommendation: Identifiable { public let id = UUID(); … }`
mints an identity on every `HealthRecommendation(title:)`, so a function returning one fails
`f(x) == f(x)` on correct code. The purity oracle used to judge each declaration alone and called
such a function pure.

It now knows what constructing each of the package's types runs — stored-property defaults, the
initializer the call reaches and its defaulted parameters, a superclass's construction — through
SwiftEffectInference's `ConstructionFacts`, built once per run by `PackagePurity` and read by every
oracle the run creates. A function that constructs a refuted type is refused, with a witness naming
the step (`SimulationIssue.init(id:severity:message:affectedKey:suggestion:): id's default: UUID`).
As with every refuter, any doubt refutes: a function that builds an `Item` and returns only its
`n` is refused too. The one-hop callee join counts the witness as evidence, so a caller of such a
function is withdrawn as well.

**Which files' types count** is `ConstructionUniverse`, a rule shared word for word with
SwiftInferProperties (the agreed rows are in [`Docs/construction-universe.tsv`](../construction-universe.tsv)):
every `.swift` file under the lint root except a manifest and anything under a test-target folder
(`Tests/`, `*Tests/`), a hidden directory or a build-product directory. **No reporting filter
applies.** `excluded_paths`, `include_nested_packages` and the generated-file filter decide what is
reported, not what is compiled, so a type declared in a nested package the root depends on, a
generated file or a directory you excluded still refutes the production code that builds it.
Test-support targets, `Mocks/` and `Examples/` are kept too: they compile, and dropping a type
production constructs would call its construction pure — the unsound direction.

**What bounds it is what the root compiles.** A nested package is a directory below the root whose
`Package.swift` is a manifest — its first line a `// swift-tools-version` comment, as SwiftPM
requires. A source file named `Package.swift` (a `struct Package` in an app's `Models/`), a directory
or a dangling link of that name is not one, and takes nothing out. A nested package counts only when
it is reached: through the root's `.package(path:)` dependencies, followed transitively through
every manifest reached — a directory's `Package.swift` together with its `Package@swift-*.swift`
files; through a target whose `path:` lies inside it; or because the run reports on its files, so
`--include-nested-packages` judges a package with its own types. Paths are read for their value, as
SwiftPM reads them (escapes decoded, raw strings allowed), and matched where they resolve, so
`/tmp/x` and `/private/tmp/x`, a link to a package's directory, and `packages/core` for
`Packages/Core` on a case-insensitive volume each name the package. A dependency is followed by its
path even into a test folder or a hidden directory, whose own files stay out. Doubt counts every
nested package: a manifest that computes a path or cannot be read, a root with no `Package.swift`
(an Xcode project, a workspace folder), and a root whose manifest has an `.xcodeproj` or
`.xcworkspace` beside it, since nothing cheap says what those compile.

Leaving an unrelated package out is not tidiness: over-refuting is not harmless here. A `Demo/`
package's own `Row`, minting a `UUID`, refuted the app's plain `Row(n:)`; that withdrew two
candidates and cost the app's `ReportBuilder` its [Direct Instantiation](direct-instantiation.md)
pure-kernel exemption, a new warning, in a run that had said it was not analysing `Demo/`. Judging a
reported package with its own types brings that cost back on purpose, and only then: lint `Demo/`
alongside the app and its `Row` refutes the app's again. Three smaller rules complete it: a
symlinked file counts **where the link is**, wherever its target lives; two paths to one file count
once, as the smaller path; and a file that is not strict UTF-8 does not count, since no compiler
reads it. A file Finder hides (the `UF_HIDDEN` flag) counts like any other; a dot-prefixed one does
not.

What it still does not see, or sees too much of:

- **Types outside the lint root** — a dependency's, Foundation's (`URL(fileURLWithPath:)` above is
  judged by its name, not by what it runs), or a sibling package linted on its own. Lint the package
  root to put every first-party type in the universe.
- **A symlinked directory's files.** The walk does not follow a link to a directory (a link to a
  file it does follow), and neither does SwiftInferProperties'.
- **A `Package.swift` or a `Tests`/`*Tests` folder inside an Xcode app target.** The universe drops
  every file named `Package.swift` and everything under a folder named like a test target, wherever
  it is — right for SwiftPM, where neither is compiled into a production target; an Xcode target
  can compile both.
- **An Xcode project below the root** (`Apps/iOS/App.xcodeproj`): only one directly beside the
  root's manifest counts as doubt.
- **Namesakes across modules.** The table is one name space: two modules' `Row`s in one universe are
  one `Row`, and if either refutes, both do. The bound keeps an unrelated package's out; a
  reported one's, and a dependency's, stay in.
- **What SwiftEffectInference leaves out by design**: an unlabelled `.init(…)` with no type context,
  a generic parameter or metatype constructed (`T()`, `type(of: x).init()`), literal conversion
  through `ExpressibleBy…Literal`, an enum case's associated-value default, a `deinit`, a property
  wrapper the package does not declare, and a `lazy` or `static` default — which run on first access
  or once per process, not on construction.
- **Witness order, not verdicts.** Which witness is reported first among several declarations of
  one name depends on the order the table reads them; the universe is sorted by path, so it is
  stable from run to run and the same in both consumers. Which types refute does not depend on
  order. Until SwiftEffectInference `9d0bf6d` it did: a typealias name declared twice resolved to
  the first declaration read, so `typealias Stamp = UUID` in one type and `typealias Stamp =
  String` in another could leave a construction unrefuted. SEI now follows every alias a name may
  mean, and reads one its own type declares in that type.

Measured with the release CLI at `main` and with the facts wired, JSON output, nine runs over seven
repositories: **16 candidates withdrawn from SwiftCompilerFlagStudio** (default rules, through an
empty `--config`) and **1 from SwiftAssist** (`makeInsight`). Thirteen of the 17 build a model whose
initializer defaults `id: UUID = UUID()`, or whose stored `id` does — `validate` constructs a
`ValidationResult.Issue`, `computeDiff` a `SettingDiff`. The other four (`diffConfigurations`,
`diffTargets`, `effectiveSettings`, `redundantSettings`) build nothing themselves and were withdrawn
by the one-hop join, each calling one of the thirteen. Nothing was added, and SwiftProjectLint,
SwiftLintRuleStudio (with and without its nested packages), SwiftUMLStudio, SwiftInferProperties and
SwiftFormatRuleStudio did not move for this rule; nor did SwiftCompilerFlagStudio under its own
`.swiftprojectlint.yml`, which enables three rules and reports nothing on `main` or with the facts.
The nested-package bound, link-location classification and the UTF-8 rule were re-measured over the
same nine runs and moved no row of any rule; so, again, did the shared spec's third amendment — what
a manifest is, an Xcode project beside it, dependency values and canonical matching, the closure by
path, reported packages, version-specific manifests and target paths, and the hidden flag. What it
fixed shows on the joint review's own fixtures instead, each a false candidate withdrawn: an
absolute dependency through `/tmp`, an escaped one, an Xcode-built local package, a `Package.swift`
source file, a reported `Demo/` package's own functions (its Direct Instantiation warning restored),
and the critic's `Package@swift-6.0.swift`, target-path and linked-directory cases; and a deep
manifest in a dependency no longer crashes the run. One candidate was added, rightly: a fixture's
`IntegrationTests/Package.swift` puts a `let` above its tools-version line, so it is no manifest,
its computed path is no doubt, and an unrelated `Demo/`'s `Row` no longer refutes the app's. The
case that motivated the facts, SwiftLintRuleStudio's `generateRecommendations`, was never offered
here:
`HealthRecommendation` is not `Equatable`, so the assertable-return gate already withheld it.

### Throwing candidates: pure but partial

A `throws` function can be a candidate. `throws` refutes **totality**, not referential transparency,
and only one of those makes a function untestable: a function that rejects the inputs it cannot map
is a deterministic function of its inputs on all the rest. The message says *"looks pure but
partial"* and the suggestion tells you to narrow the law's domain — compare `try? f(x)` on both
sides, so an input in the throwing domain is a no-op for the property rather than a failure.

For a tuple result that comparison does not compile: `(try? f(x)) == (try? f(x))` compares two
Optionals of a tuple, and an Optional has `==` only when what it wraps is `Equatable`, which a tuple
never is. So a throwing function that returns a tuple is **not a candidate**. `swift-infer` writes the
`try?` form for every throwing seed, so seeding one would hand it a law that does not build. Binding
both results with `if let` would compile, but it is a weaker law: it makes "one call throws and the
other returns" a no-op, which is exactly the nondeterminism the comparison exists to catch. A tuple
waits for a law that compares the two outcomes — both throw, or both return equal tuples.

**But only when the function throws its own errors.** A `try` into a callee refutes:

| the body | verdict |
|---|---|
| `guard let v = Int(text) else { throw ParseError.bad }` | **pure but partial** — it rejects an input |
| `try process.run()`, `try String(contentsOf: url)` | not a candidate — the throw, and whatever else the callee does, comes from code this rule cannot see |

That second gate is load-bearing, and the reason is worth knowing before anyone relaxes it. **The
old blanket `throws` exclusion was silently doing a second job**: nearly all real I/O in Swift
throws, so gating on `throws` masked every impurity marker the set does not name — `Process`,
`Pipe`, `FileHandle`, `String(contentsOf:)`, `Data(contentsOf:)`, the SQLite surface. Admitting
throwing candidates without the propagation check re-admitted all of them at once, and a
subprocess-spawning `runSwiftLint(executable:workingDirectory:lintFile:)` was judged pure — the
lattice-bottom mistake this rule exists to avoid. Measured on a real subject, the unnarrowed form
added 11 seeds of which ~10 were I/O; the narrowed form adds 3.

The cost is a pure function that happens to call another pure throwing function, refused for want of
a cross-file view. That is the sound direction.

### Access level: `internal` is the floor

A candidate is only useful if a test can *call* it. `@testable import` reaches `internal` and stops
— it does not reach `private` or `fileprivate`.

This rule still surfaces `private` candidates, and `swift-infer` will still write the law for one
when a seed names it, because knowing your pure logic exists is worth something. But no test can run
that law until the access widens. If a candidate is `private`, either widen it to `internal` or lift
the logic into a type of its own.

Note the tension with [Could Be Private Member](could-be-private-member.md), which will happily tell
you to narrow the very function this rule just flagged. That rule now names the cost when it does.

---

### Not listed in the default report

This rule is a **census**, and on a real codebase it is a large one: 804 findings here, alongside
290 from [Pure Closure Property-Test Candidate](pure-closure-candidate.md) — together **66% of
everything the linter prints**. A pure function is not a defect and there is nothing to fix per
line, so enumerating them buries the findings that *are* defects. During this project's own road
test the linter found a real bug in its configuration code, reported it correctly, and the finding
went unread in exactly that pile. Volume that large does not inform; it functions as silence.

So `--format text` counts these findings in its summary and names them in a footer, but does not
print one line each:

```
Found 1656 issues (127 warnings, 1529 info)

1094 of these are property-test candidates, not listed above (804 Pure Function …, 290 Pure Closure …).
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
