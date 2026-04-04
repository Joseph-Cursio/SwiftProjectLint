[← Back to Rules](RULES.md)

## String Switch Over Enum

**Identifier:** `String Switch Over Enum`
**Category:** Code Quality
**Severity:** Info
**Opt-in:** Yes

### Rationale
When developers switch on `someEnum.rawValue` (a `String`) instead of switching on the enum itself, they lose exhaustiveness checking. If a new case is added to the enum, the string switch silently falls through to `default` instead of producing a compiler error. This defeats one of Swift's most valuable safety features.

### Discussion
`StringSwitchOverEnumVisitor` detects two patterns:

1. **`.rawValue` switch:** The switch subject is a member access ending in `.rawValue` and at least one case arm uses a string literal pattern.
2. **`String(describing:)` switch:** The switch subject is a `String(describing: expr)` call with string literal cases.

Because the rule operates without full type information, it uses `knownEnumTypes` (populated by cross-file pre-scan) when available, and falls back to a structural heuristic — any `.rawValue` access with string literal cases is flagged. This is why the rule is opt-in.

### Suppression: Codable Methods

The warning is suppressed when the switch appears inside a `Codable` implementation:
- `init(from decoder: Decoder)` — custom decoding
- `func encode(to encoder: Encoder)` — custom encoding

In these contexts, switching on raw string values from external input is the expected pattern.

### Non-Violating Examples
```swift
// Direct enum switch — compiler enforces exhaustiveness
switch status {
case .active: handleActive()
case .inactive: handleInactive()
case .pending: handlePending()
}

// Inside Codable init — suppressed
init(from decoder: Decoder) throws {
    let raw = try container.decode(String.self, forKey: .status)
    switch raw {
    case "active": self.status = .active
    default: self.status = .unknown
    }
}

// Integer rawValue — not flagged (only string literals trigger)
switch code.rawValue {
case 0: handleZero()
case 1: handleOne()
default: break
}
```

### Violating Examples
```swift
// String switch on .rawValue — loses exhaustiveness
switch status.rawValue {
case "active": handleActive()
case "inactive": handleInactive()
default: break  // Silently ignores new cases
}

// String(describing:) — same problem
switch String(describing: status) {
case "active": handleActive()
case "inactive": handleInactive()
default: break
}
```

---
