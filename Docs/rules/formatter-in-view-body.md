[← Back to Rules](RULES.md)

## Formatter In View Body

**Identifier:** `Formatter In View Body`
**Category:** Performance
**Severity:** Warning

### Rationale
Foundation formatter and coder types — `DateFormatter`, `NumberFormatter`, `JSONDecoder`, and their relatives — are expensive to initialize. They allocate internal caches, parse locale and calendar data, and register with the system on creation. When constructed inside a SwiftUI view's `body` computed property, they are rebuilt from scratch on every render pass triggered by a state change. This makes one of the most common SwiftUI performance mistakes invisible until profiled.

`Calendar.current` and `Locale.current` are lighter — they return struct copies rather than heap-allocated objects — but each access inside a `ForEach` or a frequently re-rendering body still adds unnecessary overhead. More importantly, reading them directly bypasses SwiftUI's environment system: views that use `@Environment(\.calendar)` and `@Environment(\.locale)` automatically re-render when the user changes their locale or calendar in Settings, while direct `.current` accesses do not.

### Discussion
`FormatterInViewBodyVisitor` scans the getter of the `body` computed property on any `struct` conforming to `View`, searching for:
- **Call expressions** whose callee is a known expensive formatter type (`DateFormatter()`, `JSONDecoder()`, etc.).
- **Member access expressions** of the form `Calendar.current` or `Locale.current`.

Because all SwiftUI Views must be structs, the visitor only inspects `StructDeclSyntax` nodes. It extracts the `body` property's accessor block and walks it with a focused inner visitor, so formatter calls in unrelated computed properties or helper methods are never flagged.

No suppression logic is required: `static` stored properties can only be declared at type scope in Swift — not inside a computed property getter — so any formatter construction visible inside `body` is structurally guaranteed to be a per-render allocation.

### Detected Types

| Type | Notes |
|------|-------|
| `DateFormatter` | Parses locale and calendar data on init |
| `NumberFormatter` | Parses locale number formatting on init |
| `ISO8601DateFormatter` | Heavyweight date parser |
| `DateComponentsFormatter` | Allocates calendar internals on init |
| `ByteCountFormatter` | Locale-aware, expensive init |
| `MeasurementFormatter` | Locale-aware, expensive init |
| `PersonNameComponentsFormatter` | Locale-aware, expensive init |
| `JSONDecoder` | Allocates decoding strategy internals |
| `JSONEncoder` | Allocates encoding strategy internals |
| `Calendar.current` | Returns a struct copy; use `@Environment(\.calendar)` instead |
| `Locale.current` | Returns a struct copy; use `@Environment(\.locale)` instead |

`Date.FormatStyle` and the `.formatted()` API are **not** flagged — they are value types with negligible allocation cost and are the recommended modern API.

### Non-Violating Examples
```swift
// Static stored property — created once, reused across all renders
struct EventRow: View {
    private static let dateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        return fmt
    }()

    var body: some View {
        Text(Self.dateFormatter.string(from: event.date))
    }
}

// Stored instance property — created once when the view is initialized
struct EventRow: View {
    private let formatter = DateFormatter()

    var body: some View {
        Text(formatter.string(from: event.date))
    }
}

// Modern format style API — lightweight value type, not flagged
struct EventRow: View {
    var body: some View {
        Text(event.date.formatted(.dateTime.month().day()))
    }
}

// Calendar and Locale via environment — correct pattern, not flagged
struct EventRow: View {
    @Environment(\.calendar) var calendar
    @Environment(\.locale) var locale

    var body: some View {
        Text(calendar.isDateInToday(event.date) ? "Today" : "Other")
    }
}
```

### Violating Examples
```swift
// FLAGGED: DateFormatter recreated on every render
struct EventRow: View {
    let event: Event

    var body: some View {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return Text(formatter.string(from: event.date))
    }
}

// FLAGGED: JSONDecoder inside body
struct DataView: View {
    let payload: Data

    var body: some View {
        let decoder = JSONDecoder()
        let model = try? decoder.decode(MyModel.self, from: payload)
        return Text(model?.title ?? "")
    }
}

// FLAGGED: Multiple formatters, each rebuilt every render
struct StatsView: View {
    var body: some View {
        VStack {
            let numFmt = NumberFormatter()
            let dateFmt = DateFormatter()
            Text("...")
        }
    }
}

// FLAGGED: Calendar.current and Locale.current in body
struct EventRow: View {
    var body: some View {
        let cal = Calendar.current
        let locale = Locale.current
        Text(cal.isDateInToday(event.date) ? "Today" : "Other")
    }
}
```

---
