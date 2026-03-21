[← Back to Rules](RULES.md)

## Hardcoded Strings

**Identifier:** `Hardcoded Strings`
**Category:** Code Quality
**Severity:** Info

### Rationale
String literals that appear directly inside user-facing SwiftUI views should be localized. Hardcoded strings prevent internationalization and make content updates require code changes.

### Scope
- Flags hardcoded string literals (no interpolation) that are direct arguments to user-facing SwiftUI calls: `Text`, `Label`, `Button`, `Toggle`, `Picker`, `Slider`, `Section`, `NavigationLink`, `TabItem`, `DisclosureGroup`, `.navigationTitle()`, `.alert()`, `.confirmationDialog()`, `.help()`, `.badge()`, and others
- Does **not** flag strings in non-UI contexts — model code, test assertions, logging, configuration
- Does **not** flag strings in test files (`*Tests.swift` or files under a `Tests/` directory)
- Does **not** flag strings of 2 characters or fewer — punctuation and single-letter formatting artifacts
- Does **not** flag URL patterns (`http`, `https`, `file://`, `data:`, `base64`)
- Does **not** flag SF Symbol names — dot-separated lowercase identifiers like `"checkmark.circle.fill"`
- Does **not** flag `systemImage`/`systemName`/`imageName`/`symbolName` arguments

### Non-Violating Examples
```swift
// Localized string
Text(String(localized: "welcome_message"))

// URL — skipped
Text("https://api.example.com/v1/users")

// SF Symbol names — skipped
Label("Settings", systemImage: "gear")
Image(systemName: "checkmark.circle.fill")

// Short strings — skipped
Text("•")
Text("OK")

// Non-UI context — not flagged
let errorMessage = "Something went wrong"
logger.info("Processing completed")

// Test files — not flagged
// (any file under Tests/ or ending in Tests.swift)
```

### Violating Examples
```swift
Text("Welcome to the app")

Button("Delete this item") { delete() }

NavigationLink("Account Settings") { SettingsView() }

VStack {
    Text("Please try again later")
}
.navigationTitle("My Dashboard")
```

---
