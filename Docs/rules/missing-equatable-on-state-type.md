[← Back to Rules](RULES.md)

## Missing Equatable on State Type

**Identifier:** `Missing Equatable on State Type`
**Category:** Testability
**Severity:** Info

### Rationale
Property-based testing asserts on values and shrinks failing cases by comparing them — both require `Equatable`. A value type held in SwiftUI state (`@State`, `@Binding`, `@Published`) that conforms to neither `Equatable` nor `Hashable` therefore can't be a property-test subject: you can't write `#expect(reduce(state, action) == expected)` over generated inputs, and a shrinker can't tell two candidate states apart. Adding the conformance — which the compiler synthesizes for a `struct`/`enum` whose members are themselves `Equatable` — turns untestable view state into a direct SwiftPropertyLaws target.

### Discussion
`MissingEquatableOnStateTypeVisitor` is a **cross-file** rule (it runs after the whole project is parsed). In one pass it records every `struct`/`enum` declaration and the conformances it declares — both inline (`struct Foo: Equatable`) and via a separate `extension Foo: Equatable {}` in any file — and the value types used in `@State` / `@Binding` / `@Published`. It then emits one issue, at the type's declaration, for each value type used in state that declares neither `Equatable` nor `Hashable` (the latter refines the former, so either satisfies the rule).

Reference-type wrappers (`@StateObject`, `@ObservedObject`, `@EnvironmentObject`) are excluded — they wrap `ObservableObject` classes, where identity rather than value equality is the model. The rule is conservative: a type whose declaration is in another module isn't flagged, since its conformances can't be seen from the scanned sources.

```swift
// Before — flagged: Settings is held in @State but isn't Equatable
struct Settings {
    var volume: Int
}
struct ContentView: View {
    @State private var settings: Settings
}

// After — synthesized Equatable makes Settings a property-test subject
struct Settings: Equatable {
    var volume: Int
}
```

### Non-Violating Examples
```swift
// Declares Equatable inline
struct Settings: Equatable { var volume: Int }

// Hashable refines Equatable — also fine
struct Filter: Hashable { var query: String }

// Conformance added in a separate file / extension is seen (cross-file)
struct Theme { var accent: Int }
extension Theme: Equatable {}

// Stdlib state types are already Equatable
struct V: View { @State var count: Int = 0 }

// Reference-type wrappers are out of scope
final class Store: ObservableObject {}
struct W: View { @StateObject var store = Store() }
```

### Violating Examples
```swift
// Non-Equatable struct in @State
struct DraftPost { var title: String; var body: String }
struct Editor: View { @State var draft: DraftPost }

// Non-Equatable enum behind @Published
enum LoadState { case idle, loading, loaded }
final class Model: ObservableObject { @Published var state: LoadState = .idle }
```

---
