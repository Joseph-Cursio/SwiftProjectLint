[← Back to Rules](RULES.md)

## Hardcoded Strings

**Identifier:** `Hardcoded Strings`
**Category:** Code Quality
**Severity:** Info

### Rationale
String literals that appear directly inside user-facing SwiftUI views should be localized. Hardcoded strings prevent internationalization and make content updates require code changes.

### Discussion
This rule only fires when a hardcoded string (no interpolation) is a direct argument to a user-facing SwiftUI call such as `Text()`, `Label()`, `Button()`, `Section()`, `.navigationTitle()`, `.alert()`, or `.confirmationDialog()`. Strings in non-UI contexts — model code, test assertions, logging, configuration — are not flagged.

Strings containing URL patterns (`http`, `https`, `file://`, `data:`, `base64`) are always skipped.

The fix is to use `String(localized: "key", defaultValue: "...")` or `NSLocalizedString("key", comment: "...")`, allowing translators to adapt the text without touching code.

### Non-Violating Examples
```swift
// Localized string
Text(String(localized: "welcome_message"))

// URL — skipped
Text("https://api.example.com/v1/users")

// Non-UI context — not flagged
let errorMessage = "Something went wrong, please try again"
logger.info("Processing completed successfully")
```

### Violating Examples
```swift
// User-facing text hardcoded in SwiftUI views
Text("Welcome to the app")

Button("Delete this item") { delete() }

NavigationLink("Account Settings") { SettingsView() }

VStack {
    Text("Please try again later")
}
.navigationTitle("My Dashboard")
```

---
