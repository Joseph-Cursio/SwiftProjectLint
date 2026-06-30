[← Back to Rules](RULES.md)

## Impure Call in View Body

**Identifier:** `Impure Call in View Body`
**Category:** Testability
**Severity:** Warning

### Rationale
A SwiftUI view's `body` should be a pure function of its state — it builds a view tree and does nothing else. Reaching into persistence, the file system, the network, logging, or the dispatch queue from `body` couples *rendering* to side effects and external mutable state. Two things break:

- **Untestable rendering.** The view renders differently depending on state outside the view, so you can't snapshot- or property-test it by simply rendering it and asserting on the output — the output isn't a function of the inputs you control.
- **Repeated effects.** SwiftUI may invoke `body` many times per state change; a side effect in `body` re-fires on every render.

Drive the view from state instead: perform effects in an action or `onAppear`, and read external values through `@AppStorage` or injected state.

### Discussion
`ImpureCallInViewBodyVisitor` mirrors `FormatterInViewBodyVisitor`: on any `struct` conforming to `View`, it scans the getter of the `body` computed property and reports a reference to a known impure API — `UserDefaults`, `FileManager`, `URLSession`, `NotificationCenter`, `DispatchQueue`, `print`, `NSLog`. Each surfaces its marker as a `DeclReferenceExprSyntax` (the member-access base in `UserDefaults.standard.set(…)`, the callee in `print(…)`), so both reads and writes are caught.

Only `body` is scanned — the same API used in a helper method or an action is fine. Value-source nondeterminism (`Date()`, `.random`) is **not** flagged here: the **Non-Injected Nondeterminism** rule already covers it in any computed-property body, so this rule stays focused on side-effecting / external-state calls and avoids double-reporting.

```swift
// Before — body reads external mutable state on every render
struct CounterView: View {
    var body: some View {
        Text("\(UserDefaults.standard.integer(forKey: "count"))")
    }
}

// After — the value is injected as state; rendering is a function of `count`
struct CounterView: View {
    @AppStorage("count") private var count = 0
    var body: some View {
        Text("\(count)")
    }
}
```

### Non-Violating Examples
```swift
// Impure work lives in an action, not in body
struct ContentView: View {
    @State private var items: [Item] = []
    var body: some View {
        List(items) { Text($0.name) }
            .onAppear { items = load() }   // effect outside body
    }
}

// The same API in a helper method is fine — only `body` is scanned
struct ProfileView: View {
    func save() { UserDefaults.standard.set(true, forKey: "seen") }
    var body: some View { Text("Profile") }
}
```

### Violating Examples
```swift
struct FeedView: View {
    var body: some View {
        let _ = print("rendering feed")                       // logging side effect
        let cached = FileManager.default.fileExists(atPath: p) // file-system read
        Text(cached ? "cached" : "fresh")
    }
}
```

---
