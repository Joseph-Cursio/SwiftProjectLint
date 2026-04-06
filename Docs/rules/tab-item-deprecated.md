[<- Back to Rules](RULES.md)

## tabItem Deprecated

**Identifier:** `tabItem Deprecated`
**Category:** Modernization
**Severity:** Info

### Rationale
iOS 18 introduced a new `TabView` API using `Tab` views directly as content, replacing the `.tabItem { }` modifier pattern. The new API is declarative and composable, and supports sidebar-style navigation on iPadOS without extra work.

### Discussion
`TabItemDeprecatedVisitor` inspects `FunctionCallExprSyntax` nodes for member accesses named `tabItem`. Any `.tabItem { }` call is flagged since the modern `Tab` API is the preferred replacement.

Note: The `Tab` API requires iOS 18+ / macOS 15+. If your project targets earlier versions, this rule may produce false positives.

### Non-Violating Examples
```swift
// Modern Tab API (iOS 18+)
TabView {
    Tab("Home", systemImage: "house") {
        ContentView()
    }
    Tab("Settings", systemImage: "gear") {
        SettingsView()
    }
}
```

### Violating Examples
```swift
// Legacy tabItem modifier
TabView {
    ContentView()
        .tabItem {
            Label("Home", systemImage: "house")
        }
    SettingsView()
        .tabItem {
            Label("Settings", systemImage: "gear")
        }
}
```

---
