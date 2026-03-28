[← Back to Rules](RULES.md)

## SwiftLint Suppression

**Identifier:** `SwiftLint Suppression`
**Category:** Code Quality
**Severity:** Warning

### Rationale
`// swiftlint:disable` and `// swiftlint:disable:next` comments suppress SwiftLint rules, hiding potential issues from static analysis. While sometimes necessary, suppression comments often indicate an underlying problem that should be fixed rather than silenced.

Tracking suppressions makes it easy to audit how often lint rules are bypassed and whether those bypasses are still justified.

### Scope
- Flags `// swiftlint:disable <rule>` (block suppression)
- Flags `// swiftlint:disable:next <rule>` (next-line suppression)
- Handles block comment variants (`/* swiftlint:disable ... */`)
- Reports one issue per suppressed rule when multiple rules appear on one line
- Does not flag `// swiftlint:enable` (re-enabling is not a suppression)
- Does not flag `// swiftprojectlint:disable` (different tool)

### Non-Violating Examples
```swift
// This is a normal comment
let value = 42

// swiftlint:enable force_cast
let restored = foo as! Bar

// swiftprojectlint:disable force-try
let val = try! something()
```

### Violating Examples
```swift
// swiftlint:disable force_cast
let val = foo as! Bar

// swiftlint:disable:next line_length
let veryLongVariableName = "something that makes the line too long for the configured limit"

// swiftlint:disable force_cast force_unwrapping line_length
// ^ reports three separate issues, one per rule

/* swiftlint:disable identifier_name */
let x = 1
```

---
