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

**Recognized value-transform members:** `rawValue`, `hashValue`, `capitalized`, `uppercased`, `lowercased`, `description`, `debugDescription`, `trimmedDescription`, `color`, `lowerBound`, `upperBound`, `text`, `baseName`, `isEmpty`

> **Note on `text` and `baseName`:** These are included because SwiftSyntax nodes expose token text through a fixed `node.declName.baseName.text` accessor chain that is idiomatic framework API, not object-graph navigation. The chain ends at a `String` value and does not expose further structural knowledge.

> **Note on `isEmpty`:** Included as a terminal-only exemption at depth 3. Testing whether a collection is empty is a scalar Boolean result; it does not chain further into internal structure. At depth 4+, `.isEmpty` is not exempt because the preceding four-component chain already constitutes a violation regardless of the terminal.

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

// Value-transform terminal at depth 3 — .capitalized, .lowerBound, .isEmpty
let label = violation.severity.rawValue.capitalized
let start = chunk.lineRange.lowerBound
let empty = node.body.statements.isEmpty

// Value-transform intermediate — .description converts to String at depth 2
let name = node.extendedType.description.trimmingCharacters(in: .whitespaces)

// Value-transform intermediate — .color maps enum to SwiftUI Color at depth 2
Color.clear.background(item.severity.color.opacity(0.06))
```

### Violating examples

```swift
// Three-level chain — LoD violation
class Owner {
    func run() { let _ = manager.service.data.count }
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
