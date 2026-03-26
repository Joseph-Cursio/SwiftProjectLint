[← Back to Rules](RULES.md)

## Large View Helper

**Identifier:** `Large View Helper`
**Category:** Performance
**Severity:** Warning

### Rationale
Helper computed properties and methods within a View struct that exceed 50 lines are candidates for extraction into dedicated child views. Large helpers are hard to reason about and often indicate that a section of UI should be its own view component with its own dependency graph.

### Discussion
`PerformanceVisitor` measures the line count of each non-`body` computed property and method inside a View struct. Helpers under 50 lines are fine — well-factored views naturally have many small helpers. Only individually large helpers are flagged.

This complements the **Large View Body** rule, which counts statements in the `body` property itself. Together they catch both bloated bodies and bloated helpers without penalizing good decomposition.

### Non-Violating Examples
```swift
struct DashboardView: View {
    var body: some View {
        VStack {
            headerSection
            contentSection
        }
    }

    // 20 lines — no issue
    private var headerSection: some View {
        HStack {
            Image(systemName: "star")
            Text("Dashboard")
                .font(.headline)
        }
    }

    // 15 lines — no issue
    private var contentSection: some View {
        Text("Content goes here")
    }
}
```

### Violating Examples
```swift
struct DashboardView: View {
    var body: some View {
        headerSection
    }

    // 60+ lines — should be its own view
    private var headerSection: some View {
        VStack {
            Text("Line 1")
            Text("Line 2")
            // ... 50+ lines of nested view code
            Text("Line 55")
        }
    }
}
```

---
