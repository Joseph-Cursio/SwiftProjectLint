[← Back to Rules](RULES.md)

## Nested Navigation View

**Identifier:** `Nested Navigation View`
**Category:** UI Patterns
**Severity:** Warning

### Rationale
Nesting a `NavigationView` inside another `NavigationView` in the same view hierarchy creates two independent navigation stacks that fight for control. This produces visual artifacts — two navigation bars, broken back buttons, or unexpected title behavior — that are difficult to debug.

### Discussion
`UIVisitor` maintains a navigation stack as it walks struct declarations. When a `NavigationView` call is encountered inside a view that is already in the navigation stack, the nested navigation is flagged. The recommended fix is to use `NavigationStack` (iOS 16+) instead, which handles nested navigation destinations correctly and eliminates the ambiguity.

### Non-Violating Examples
```swift
// Single NavigationView
struct ContentView: View {
    var body: some View {
        NavigationView {
            Text("Single Navigation")
        }
    }
}

// NavigationStack — modern and safe
struct ContentView: View {
    var body: some View {
        NavigationStack {
            Text("Modern Navigation")
        }
    }
}
```

### Violating Examples
```swift
struct ContentView: View {
    var body: some View {
        NavigationView {
            VStack {
                NavigationView {  // nested NavigationView
                    Text("Nested Navigation")
                }
            }
        }
    }
}
```

---
