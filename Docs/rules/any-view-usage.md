[← Back to Rules](RULES.md)

## AnyView Usage

**Identifier:** `AnyView Usage`
**Category:** Performance
**Severity:** Warning

### Rationale
`AnyView` is a type-erasing wrapper that hides the concrete view type from SwiftUI's diffing engine. Because SwiftUI cannot see through the erasure, it must destroy and recreate the entire wrapped subtree on every update cycle, rather than performing a targeted structural diff. The alternatives — `@ViewBuilder` and generic constraints — preserve structural identity at zero runtime cost and should be preferred in almost all cases.

### Discussion
`AnyViewUsageVisitor` detects `AnyView(...)` call expressions. The most common motivation for reaching for `AnyView` is returning different view types from a conditional, which `@ViewBuilder` handles natively.

```swift
// Before — forces full recreation on every update
func badge(for user: User) -> AnyView {
    if user.isPremium {
        return AnyView(Image(systemName: "crown").foregroundStyle(.yellow))
    } else {
        return AnyView(EmptyView())
    }
}

// After — @ViewBuilder preserves structural identity
@ViewBuilder
func badge(for user: User) -> some View {
    if user.isPremium {
        Image(systemName: "crown").foregroundStyle(.yellow)
    }
}

// Before — AnyView in a body conditional
var body: some View {
    if showDetail {
        return AnyView(DetailView())
    } else {
        return AnyView(SummaryView())
    }
}

// After — no return needed with @ViewBuilder (body already is one)
var body: some View {
    if showDetail {
        DetailView()
    } else {
        SummaryView()
    }
}
```

When you truly need type erasure (e.g. storing heterogeneous views in an array), `AnyView` is acceptable — suppress the rule with `// swiftprojectlint:disable any-view-usage`.

### Non-Violating Examples
```swift
@ViewBuilder
func makeContent() -> some View {
    if isLoggedIn {
        DashboardView()
    } else {
        LoginView()
    }
}

var body: some View {
    Group {
        Text("Hello")
        Image(systemName: "star")
    }
}
```

### Violating Examples
```swift
AnyView(Text("Hello"))

func makeView() -> AnyView {
    AnyView(VStack { Text("A"); Text("B") })
}

var body: some View {
    if flag {
        return AnyView(ViewA())
    } else {
        return AnyView(ViewB())
    }
}
```

---
