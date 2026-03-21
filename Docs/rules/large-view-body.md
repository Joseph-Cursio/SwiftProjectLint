[← Back to Rules](RULES.md)

## Large View Body

**Identifier:** `Large View Body`
**Category:** Performance
**Severity:** Warning

### Rationale
A view body with more than 20 statements or a view struct exceeding 50 lines is difficult to comprehend and slows Xcode's type-checker. SwiftUI's type inference is applied to the entire `body` expression at once; very large bodies can cause compilation timeouts and degraded editor responsiveness.

### Discussion
`PerformanceVisitor` triggers this rule in two ways:

1. **Statement count > 20** — counts statements inside the `body` getter. This directly affects the type-checker, which evaluates the entire body expression at once.
2. **Line count > 100** — counts lines in the overall View struct. Views this large are difficult to navigate and typically contain logic that belongs in child views.

The fix is to extract logical sub-sections of the body into dedicated child view structs. This also improves SwiftUI's incremental recomputation because smaller views have narrower dependency graphs.

### Non-Violating Examples
```swift
struct DashboardView: View {
    var body: some View {
        VStack {
            HeaderSection()
            ContentSection()
            FooterSection()
        }
    }
}

struct HeaderSection: View {
    var body: some View { Text("Header") }
}
```

### Violating Examples
```swift
struct DashboardView: View {
    var body: some View {
        VStack {
            Text("Line 1")
            Text("Line 2")
            Text("Line 3")
            // ... 20+ statements in the body
            Text("Line 25")
        }
    }
}
```

---
