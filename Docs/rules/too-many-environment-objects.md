[← Back to Rules](RULES.md)

## Too Many Environment Objects

**Identifier:** `Too Many Environment Objects`
**Category:** State Management
**Severity:** Warning

### Rationale
When a SwiftUI view declares four or more `@EnvironmentObject` properties, it signals that the view depends on too many external state sources. This makes the view harder to reason about, test, and reuse because every parent must supply every expected object.

### Discussion
`TooManyEnvironmentObjectsVisitor` counts `@EnvironmentObject` declarations inside each struct conforming to `View`. When the count reaches 4, the rule fires. Other property wrappers (`@State`, `@Binding`, `@Environment`, etc.) are not counted — only `@EnvironmentObject` is tracked because it represents a dependency on a shared, externally-provided object.

The threshold of 4 balances pragmatism against architectural hygiene. Three environment objects is common in mid-sized apps (e.g., settings, theme, user state); four or more usually indicates the view is doing too much or that related state should be consolidated.

### Non-Violating Examples
```swift
struct DashboardView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var user: UserSession

    var body: some View { Text("OK") }
}
```

### Violating Examples
```swift
struct OverloadedView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var theme: ThemeManager
    @EnvironmentObject var user: UserSession
    @EnvironmentObject var navigation: NavigationState  // 4th — triggers warning

    var body: some View { Text("Too many") }
}
```

---
