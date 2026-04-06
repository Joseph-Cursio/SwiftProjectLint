[<- Back to Rules](RULES.md)

## Legacy Replacing Occurrences

**Identifier:** `Legacy Replacing Occurrences`
**Category:** Modernization
**Severity:** Info

### Rationale
`.replacingOccurrences(of:with:)` is the Foundation/Objective-C string replacement API. Swift 5.7 (iOS 16+) introduced `.replacing(_:with:)` which accepts `RegexComponent` or `Collection`, is generic over the replacement type, and reads more naturally in Swift code.

### Discussion
`LegacyReplacingOccurrencesVisitor` inspects `FunctionCallExprSyntax` nodes for member accesses named `replacingOccurrences` where the first argument label is `of`. This matches the standard `.replacingOccurrences(of:with:)` call pattern.

Note: `.replacing(_:with:)` requires iOS 16+ / macOS 13+. If your project targets earlier versions, this rule may produce false positives.

### Non-Violating Examples
```swift
// Modern API
let result = str.replacing("hello", with: "world")

// Regex replacement
let cleaned = input.replacing(/\s+/, with: " ")
```

### Violating Examples
```swift
// Legacy Foundation API
let result = str.replacingOccurrences(of: "hello", with: "world")

let cleaned = path.replacingOccurrences(of: "\\", with: "/")
```

---
