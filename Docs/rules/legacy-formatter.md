[<- Back to Rules](RULES.md)

## Legacy Formatter

**Identifier:** `Legacy Formatter`
**Category:** Modernization
**Severity:** Info

### Rationale
`DateFormatter`, `NumberFormatter`, and `MeasurementFormatter` are expensive to create — they allocate internal caches and parse locale data on initialization. Swift 5.5+ introduced `FormatStyle` (`.formatted()`) which is the modern replacement. When `FormatStyle` is not an option, formatters should be cached as static properties rather than instantiated repeatedly.

### Discussion
`LegacyFormatterVisitor` inspects `FunctionCallExprSyntax` nodes for direct instantiation of `DateFormatter`, `NumberFormatter`, or `MeasurementFormatter`. To avoid double-flagging with the existing `formatterInViewBody` rule (which fires at `.warning` severity), this rule skips the `body` computed property of View-conforming structs.

### Non-Violating Examples
```swift
// Modern FormatStyle API
let formatted = date.formatted(.dateTime.month().day().year())
let price = amount.formatted(.currency(code: "USD"))

// Cached as static property
extension DateFormatter {
    static let medium: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        return fmt
    }()
}

// Inside view body — handled by formatterInViewBody rule
struct MyView: View {
    var body: some View {
        Text(DateFormatter().string(from: date))
    }
}
```

### Violating Examples
```swift
// Instantiation anywhere outside view body
let formatter = DateFormatter()
formatter.dateStyle = .medium

func format(_ value: Double) -> String {
    let fmt = NumberFormatter()
    fmt.numberStyle = .decimal
    return fmt.string(from: NSNumber(value: value)) ?? ""
}

class DataExporter {
    func export(_ measurement: Measurement<UnitLength>) -> String {
        let fmt = MeasurementFormatter()
        return fmt.string(from: measurement)
    }
}
```

---
