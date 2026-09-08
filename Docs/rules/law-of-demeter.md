[← Back to Rules](RULES.md)

## Law of Demeter

**Identifier:** `Law of Demeter`
**Category:** Architecture
**Severity:** Info

### Rationale

The Law of Demeter (also called the "principle of least knowledge") states that an object should only communicate with its immediate collaborators — the objects it directly owns or receives as parameters. A chain like `manager.service.data` forces the calling code to know about three layers of internal structure: that `manager` has a `service`, that `service` has a `data` property, and implicitly what type `data` is. This tight coupling makes refactoring fragile: renaming or restructuring any link in the chain breaks every caller.

The idiomatic fix is to add a method on the *immediate* collaborator that encapsulates the deeper access. Instead of `manager.service.data`, the caller asks `manager` directly — `manager.fetchData()` or `manager.data` — and `manager` is the only code that knows how that data is obtained.

### What the rule detects

Member-access chains of **3 or more dots** (i.e., four or more components: `a.b.c.d`) where the root is a plain identifier — not `self`, a type name, or the result of a function call. The rule reports the full chain in the message so the violation is immediately visible.

### One finding per reach-through, not per occurrence

A finding is reported once per **(enclosing declaration, reach-through target)**, where the target is
the *penultimate* component — the thing being reached into. A second chain into the same target from
the same declaration is the same problem and the same fix, so it is not reported again.

**The old count was not merely noisy, it was backwards.** Measured on two repositories before this
changed: five sort comparators in SwiftInferProperties produced **48 findings for one missing
`Comparable` conformance**, while eleven DTO-flattening constructors in SwiftAssist produced eleven
for zero problems — flattening a nested `Range` into flat wire fields is what a DTO is *for*.

Ranking by occurrence therefore put the largest cluster on the page at the top, and that cluster was
the *cheapest* fix — one conformance, one line — while the single-digit findings were the ones
needing judgement. The ranking sent a reader to the easy work and called it the biggest thing there.

**The key is the penultimate hop rather than the root**, because that is where the encapsulation
goes. `lhs.member.location.file` and `rhs.member.location.line` are one problem with `location`;
keyed on the root they would be two, splitting one fix in half.

Re-measured against source that still contained those clusters: **90 occurrences, 40
reach-throughs.** Expect reductions on this rule to look smaller and mean more.

> **What the count is good for is finding the file, not sizing the work.** Worked across three
> repositories, the defect sat *beside* the chain every time rather than in it — five comparators
> that all ignored `column`, so two declarations on one line compared equal and their order fell to
> a sort Swift does not promise is stable; a second path format built from
> `context.jail.root.path`, so one file had two names; a private colour switch four lines under an
> exempt chain that disagreed with the shared one on four of five categories. One finding in a
> three-finding repository was worth more than the forty-eight one conformance cleared.

### Exempt patterns

Several common patterns look like deep chains but are not object-graph coupling. The rule suppresses all of the following:

| Pattern | Why it's exempt |
|---|---|
| `self.a.b.c` | Accessing your own instance members through `self` is always fine |
| `super.a.b.c` | Same rationale as `self` |
| Modifier/fluent chains | The root is a function call: `Text("x").frame(width:).padding()` |
| Closure parameter chains | `$0`, `$1`, etc.: `items.sorted { $0.category.name < $1.category.name }` |
| Method-call chains | The outermost member is being called as a function: `collection.filter { }.sorted { }` |
| Singleton / static accessors | Root is capitalized + second component is `default`, `shared`, `main`, `current`, `processInfo`, or `standard` |
| Nested type / enum access | Two consecutive capitalized components: `ValidationResult.ConfigField.optInRules` |
| Known Foundation prefixes | `FileManager.default.temporaryDirectory`, `ProcessInfo.processInfo.arguments`, `URLSession.shared.data`, etc. |
| Value-transform members (intermediate) | A recognized transform member appears before the violation threshold; subsequent access is on a plain value, not an object. E.g., `node.extendedType.description.trimming…` — `.description` converts to `String` at depth 2. |
| Value-transform members (terminal, depth = 3) | The final component of a 3-dot chain is a recognized value terminal. E.g., `violation.severity.rawValue.capitalized`, `chunk.lineRange.lowerBound`, `node.body.statements.isEmpty` |
| Test files | Any file path containing `Tests/` or ending in `Test.swift` |
| Binding projections | `$viewModel.user.name` — projected value chains |
| KeyPath literals | `\SomeType.property.nested` — inside `KeyPathExprSyntax` |
| Environment/navigation roots | Root is `environment`, `theme`, `settings`, `coordinator`, `navigator`, `router` |
| Geometry/layout chains | Chain contains `frame`, `size`, `bounds`, `origin`, `width`, `height`, etc. |
| Framework API chains | Chain passes through known framework structural members (SwiftSyntax: `signature`, `parameterClause`, `parameters`, `leadingTrivia`, etc.) |

**Recognized value-transform members:** `rawValue`, `hashValue`, `capitalized`, `uppercased`, `lowercased`, `description`, `debugDescription`, `trimmedDescription`, `color`, `lowerBound`, `upperBound`, `start`, `end`, `text`, `baseName`, `isEmpty`, `count`, `absoluteURL`, `standardizedFileURL`, `lastPathComponent`

> **Note on `text` and `baseName`:** These are included because SwiftSyntax nodes expose token text through a fixed `node.declName.baseName.text` accessor chain that is idiomatic framework API, not object-graph navigation. The chain ends at a `String` value and does not expose further structural knowledge.

> **Note on `isEmpty` and `count`:** Both are terminal exemptions at depth 3. Asking a collection how many elements it holds, or whether it holds any, is a scalar result; it does not chain further into internal structure. At depth 4+ neither is exempt, because the preceding four-component chain is already a violation regardless of the terminal.
>
> **`count` was added five months after `isEmpty`, and the gap was the finding.** The two are the same shape and the same argument — `report.totals.regions.isEmpty` was waved through while `report.totals.regions.count` was reported — so the rule was answering one question two ways depending on which scalar the caller happened to want. It cost five findings across the corpus, and it also cost the rule's own documentation: `manager.service.data.count` stood as the flagship *violating* example here and in two tests, and is a chain the rule's own exemption principle says should never have fired. The violating examples below now end in a member of the object graph, which is what the rule is actually about.

> **Note on `start` and `end`:** These are `lowerBound` and `upperBound` under the names LSP and SourceKit give them. A `Range`'s bounds were already exempt as "standard Range value accessors"; a protocol that spells the same two fields `start` and `end` was not, so `diag.range.start.file` was reported and `chunk.lineRange.lowerBound` was not. Measured over the 26-repo corpus the exemption removes **five findings and moves nothing else** — all five are constructors flattening a nested source range into flat wire fields, which is what the rule's own note below calls "what a DTO is *for*".

> **Note on the URL members:** `absoluteURL` and `standardizedFileURL` are URL-to-URL normalisations and `lastPathComponent` is URL-to-String. In `sources.absoluteURL.standardizedFileURL.path` the object-graph coupling is `sources.absoluteURL` — one hop — and every component after it operates on a normalised value. Foundation's URL API is written as a chain by design; treating each normalisation as a hop into someone's internals mistakes a value pipeline for an object graph.

### Fixing a violation

Add a method or computed property on the **immediate collaborator** that hides the internal navigation:

```swift
// Before — caller knows too much about manager's internals
func run() {
    let street = user.profile.address.street
}

// After — User encapsulates its own structure
extension User {
    var street: String { profile.address.street }
}

func run() {
    let street = user.street  // one level, caller knows nothing about internals
}
```

For framework types you cannot extend, extract the deep access to a local variable or a helper function with a meaningful name:

```swift
// Before
guard node.signature.parameterClause.parameters.isEmpty else { return }

// After — intermediate local removes the visible chain from call sites
let params = node.signature.parameterClause.parameters
guard params.isEmpty else { return }

// Or with an extension on the framework type
extension FunctionDeclSyntax {
    var parameterList: FunctionParameterListSyntax { signature.parameterClause.parameters }
}
guard node.parameterList.isEmpty else { return }
```

### Non-violating examples

```swift
// Two-level chain — below the threshold
class Owner {
    func run() { let _ = manager.data }
}

// self-chain — always exempt
class ViewModel {
    func run() { let _ = self.manager.service }
}

// SwiftUI modifier chain — root is a function call, exempt
struct MyView: View {
    var body: some View {
        Text("hello").frame(width: 100).background(.red)
    }
}

// Singleton / Foundation API — capitalized root + known singleton accessor
let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("test.txt")
let isTesting = ProcessInfo.processInfo.arguments.contains("--testing")

// Nested type / enum access — two consecutive capitalized components
let desc = ValidationResult.ConfigField.optInRules.description

// Closure parameter chain — root is $0
items.sorted { $0.category.name.count < $1.category.name.count }

// Method-call chain — outermost member is a function call target
let filtered = structNode.memberBlock.members.contains { $0.name == target }

// Range bounds, under either spelling
let startLine = diagnostic.range.start.line
let endLine = diagnostic.range.end.line

// Value-transform terminal at depth 3 — .capitalized, .lowerBound, .isEmpty
let label = violation.severity.rawValue.capitalized
let start = chunk.lineRange.lowerBound
let empty = node.body.statements.isEmpty

// Value-transform intermediate — .description converts to String at depth 2
let name = node.extendedType.description.trimmingCharacters(in: .whitespaces)

// Value-transform intermediate — .color maps enum to SwiftUI Color at depth 2
Color.clear.background(item.severity.color.opacity(0.06))

// Scalar terminal at depth 3 — .count, on the same footing as .isEmpty
let regions = report.totals.regions.count

// URL normalisation — absoluteURL and standardizedFileURL are URL -> URL value transforms
let resolved = sources.absoluteURL.standardizedFileURL.path
let name = input.task.workspaceRoot.lastPathComponent
```

### Violating examples

```swift
// Three-level chain — LoD violation. The terminal is another member of the object graph.
class Owner {
    func run() { let _ = manager.service.data.owner }
}

// Three-level chain — Display knows User's internal structure
class Display {
    let user = User()
    func show() -> String { return user.profile.address.street }
}

// Four-level chain — depth 4 is never exempt by terminal value-transform
class Owner {
    func run() { let _ = a.b.c.d.description }
}
```

---
