[← Back to Rules](RULES.md)

## Law of Demeter

**Identifier:** `Law of Demeter`
**Category:** Architecture
**Severity:** Info

### Rationale
The Law of Demeter (also called the "principle of least knowledge") states that an object should only communicate with its immediate collaborators. A chain like `manager.service.data` requires the calling code to know about `manager`, about `manager`'s `service` property, and about `service`'s `data` property — three layers of internal structure that the caller should not be aware of.

### Discussion
`LawOfDemeterVisitor` detects three-level member access chains where the root is a plain identifier (not `self`, `super`, or a function call). The following patterns are exempt because they do not represent true object-graph coupling:

- **`self` and `super` chains** — accessing your own instance members is standard
- **Function-call chains** — SwiftUI modifier chains and fluent APIs intentionally chain method calls
- **Closure parameter chains** — `$0.severity.rawValue.capitalized` is idiomatic in closures
- **Singleton / static accessor chains** — `FileManager.default.temporaryDirectory.appendingPathComponent(...)` and `ProcessInfo.processInfo.arguments.contains(...)` are standard Foundation API usage, not object coupling
- **Nested type / enum case access** — `ValidationResult.ConfigField.optInRules.description` is type navigation, not object-graph navigation
- **Value-transform members** — any chain that passes through a value-converting member before reaching the violation threshold is suppressed. This covers two cases:
  - *Intermediate transform*: a transform member appears before the minimum depth, meaning all subsequent access is on a plain value rather than an object graph. For example, `node.extendedType.description.trimmingCharacters(in:)` — `.description` converts to `String` at depth 2, so `.trimmingCharacters` is String manipulation, not hidden coupling. Same for `.trimmedDescription` (SwiftSyntax shorthand) and `.color` (enum-to-SwiftUI-Color mapping).
  - *Terminal transform*: a transform member is the final component of a chain at exactly the minimum depth. For example, `violation.severity.rawValue.capitalized` or `chunk.lineRange.lowerBound` — `.lowerBound`/`.upperBound` extract a primitive from a standard Swift Range.
  - Recognized transform members: `rawValue`, `hashValue`, `capitalized`, `uppercased`, `lowercased`, `description`, `debugDescription`, `trimmedDescription`, `color`, `lowerBound`, `upperBound`
- **Test files** — XCUI chains and test setup code are inherently deep and not production architecture

The fix for real violations is to add a method on the immediate collaborator that encapsulates the deeper access, so callers need only know about one level.

### Non-Violating Examples
```swift
// Two-level chain — fine
class Owner {
    func run() { let _ = manager.data }
}

// self-chain — fine
class ViewModel {
    func run() { let _ = self.manager.service }
}

// SwiftUI modifier chain — fine
struct MyView: View {
    var body: some View {
        Text("hello").frame(width: 100).background(.red)
    }
}

// Singleton / Foundation API chain — fine
let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("test.txt")
let isTesting = ProcessInfo.processInfo.arguments.contains("--testing")

// Nested type / enum access — fine
let desc = ValidationResult.ConfigField.optInRules.description

// Closure parameter chain — fine
items.sorted { $0.category.name.count < $1.category.name.count }

// Value-transform terminal — fine
let label = violation.severity.rawValue.capitalized

// Value-transform intermediate — fine (.description converts to String at depth 2)
let name = node.extendedType.description.trimmingCharacters(in: .whitespaces)

// Value-transform intermediate — fine (.color maps enum to SwiftUI Color at depth 2)
Color.clear.background(item.severity.color.opacity(0.06))

// Range value access — fine (.lowerBound/.upperBound are terminal value extracts)
let start = chunk.lineRange.lowerBound
```

### Violating Examples
```swift
// Three-level chain — Law of Demeter violation
class Owner {
    func run() { let _ = manager.service.data.count }
}

class Display {
    let user = User()
    func show() -> String { return user.profile.address.street }  // three-level chain
}
```

---
