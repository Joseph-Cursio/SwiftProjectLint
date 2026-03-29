[← Back to Rules](RULES.md)

## SwiftProjectLint Suppression

**Identifier:** `SwiftProjectLint Suppression`
**Category:** Code Quality
**Severity:** Warning

### Rationale
`// swiftprojectlint:disable`, `// swiftprojectlint:disable:next`, and `// swiftprojectlint:disable:this` comments suppress SwiftProjectLint rules, hiding potential issues from static analysis. While sometimes necessary, suppression comments often indicate an underlying problem that should be fixed rather than silenced.

Tracking suppressions makes it easy to audit how often lint rules are bypassed and whether those bypasses are still justified.

### Scope
- Flags `// swiftprojectlint:disable <rule>` (block suppression)
- Flags `// swiftprojectlint:disable:next <rule>` (next-line suppression)
- Flags `// swiftprojectlint:disable:this <rule>` (current-line suppression)
- Handles block comment variants (`/* swiftprojectlint:disable ... */`)
- Reports one issue per suppressed rule when multiple rules appear on one line
- Does not flag `// swiftprojectlint:enable` (re-enabling is not a suppression)
- Does not flag `// swiftlint:disable` (different tool — see SwiftLint Suppression rule)

### Non-Violating Examples
```swift
// This is a normal comment
let value = 42

// swiftprojectlint:enable force-try
let restored = try! something()

// swiftlint:disable force_cast
let val = foo as! Bar
```

### Violating Examples
```swift
// swiftprojectlint:disable force-try
let val = try! something()

// swiftprojectlint:disable:next magic-number
let timeout = 30

// swiftprojectlint:disable:this could-be-private
func helper() { }

// swiftprojectlint:disable force-try force-unwrap magic-number
// ^ reports three separate issues, one per rule

/* swiftprojectlint:disable print-statement */
print("debug")
```

---
