[← Back to Rules](RULES.md)

## Hardcoded Strings

**Identifier:** `Hardcoded Strings`
**Category:** Code Quality
**Severity:** Info

### Rationale
String literals of 10 or more characters that appear directly in source code and are not part of a URL, file path, or keyword are likely user-facing text that should be localized. Hardcoded strings prevent internationalization and make content updates require code changes.

### Discussion
`CodeQualityVisitor` checks single-segment string literals (no interpolation) whose content is at least 10 characters long. Strings containing common non-UI patterns — `http`, `https`, `file://`, `data:`, `base64`, and Swift keywords — are skipped. The fix is to use `String(localized: "key", defaultValue: "...")` or `NSLocalizedString("key", comment: "...")`, allowing translators to adapt the text without touching code.

### Non-Violating Examples
```swift
// Localized string
Text(String(localized: "welcome_message"))

// URL — skipped
let endpoint = "https://api.example.com/v1/users"
```

### Violating Examples
```swift
// User-facing text hardcoded
Text("Welcome to the app")

// Error message hardcoded
label.text = "Please try again later"
```

---
