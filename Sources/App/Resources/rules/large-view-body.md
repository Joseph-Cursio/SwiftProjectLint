[← Back to Rules](RULES.md)

## Large View Body

**Identifier:** `Large View Body`
**Category:** Performance
**Severity:** Warning

### Rationale
A view body with more than 20 statements is difficult to comprehend and slows Xcode's type-checker. SwiftUI's type inference is applied to the entire `body` expression at once; very large bodies can cause compilation timeouts and degraded editor responsiveness.

### Discussion
`PerformanceVisitor` triggers this rule when the `body` getter contains more than 20 statements. The statement count targets the actual type-checker bottleneck — the body expression itself.

Note: A related rule, **Large View Helper**, flags individual helper computed properties or methods within a View struct that exceed 50 lines. Well-factored views with many small helpers do not trigger either rule.

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
