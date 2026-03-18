[← Back to Rules](RULES.md)

## Potential Retain Cycle

**Identifier:** `Potential Retain Cycle`
**Category:** Memory Management
**Severity:** Warning

### Rationale
When a `@StateObject` property is both typed and initialized with the same concrete type — `@StateObject var viewModel: ContentViewModel = ContentViewModel()` — and that type internally holds a reference back to its owner, a retain cycle can form. SwiftUI manages `@StateObject` lifetime through strong references; a circular reference in that chain prevents deallocation.

### Discussion
`MemoryManagementVisitor` detects the specific pattern where a `@StateObject` binding has an explicit type annotation and an initializer, and both name the same type. This is a heuristic: the same-type pattern is a necessary but not sufficient condition for a retain cycle. The suggestion is to review the object's lifecycle and consider using `weak` references for callbacks or delegates, or restructuring to use dependency injection.

### Non-Violating Examples
```swift
// Initialized with a different type (e.g., a subclass or mock)
struct ContentView: View {
    @StateObject var viewModel: ContentViewModel = DifferentViewModel()
    var body: some View { Text("Hello") }
}

// No initializer — injected externally
struct ContentView: View {
    @StateObject var viewModel: ContentViewModel
    var body: some View { Text("Hello") }
}
```

### Violating Examples
```swift
// Same type in annotation and initializer — potential cycle
struct ContentView: View {
    @StateObject var viewModel: ContentViewModel = ContentViewModel()
    var body: some View { Text("Hello") }
}
```

---
