[<- Back to Rules](RULES.md)

## Missing Dynamic Type Support

**Identifier:** `Missing Dynamic Type Support`
**Category:** Accessibility
**Severity:** Info *(opt-in)*

### Rationale
`.lineLimit(1)` on text elements can cause truncation when users select larger Dynamic Type sizes. This makes content inaccessible to users who rely on larger text. Views should generally allow text to flow onto multiple lines or provide scroll behavior for accessibility.

### Discussion
`MissingDynamicTypeSupportVisitor` detects `.lineLimit(1)` on `Text` views with dynamic content (variables, string interpolation, or long strings). Short static labels (under 20 characters like "Save", "Cancel") are not flagged since they rarely truncate.

The rule suppresses findings when `.minimumScaleFactor()` is in the modifier chain, as the text will shrink before truncating.

This rule is opt-in because `.lineLimit(1)` is legitimate in many UI designs (table rows, list cells).

### Non-Violating Examples
```swift
// Has minimumScaleFactor
Text(article.title)
    .lineLimit(1)
    .minimumScaleFactor(0.5)

// Short static label
Text("Save")
    .lineLimit(1)

// No lineLimit restriction
Text(article.title)
```

### Violating Examples
```swift
// Dynamic text with lineLimit(1)
Text(article.title)
    .lineLimit(1)

// String interpolation with lineLimit(1)
Text("Welcome, \(user.fullName)!")
    .lineLimit(1)
```

---
