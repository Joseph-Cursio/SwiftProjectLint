[← Back to Rules](RULES.md)

## Multiple Types Per File

**Identifier:** `Multiple Types Per File`
**Category:** Code Quality
**Severity:** Info

### Rationale
Each type (struct, class, enum, actor) should live in its own file. This makes types easy to find by filename, keeps files focused, and reduces merge conflicts. Extensions of a type in the same file are fine — the rule only flags additional type declarations.

### Discussion
`MultipleTypesPerFileVisitor` counts top-level type declarations (struct, class, enum, actor) in each file. If more than one is found, every declaration after the first is flagged with a suggestion to move it to its own file.

Nested types are not flagged — a struct containing a private helper enum is a normal pattern. Only declarations at the source-file level are counted. Extensions are also excluded since splitting a type's implementation across extensions in the same file is idiomatic Swift.

### Non-Violating Examples
```swift
// Single type per file — ideal
struct UserProfile {
    let name: String
    let email: String
}

extension UserProfile: Codable {}
```

```swift
// Nested types are fine
struct TableSection {
    enum Style {
        case plain
        case grouped
    }

    let style: Style
    let rows: [Row]
}
```

### Violating Examples
```swift
// Two top-level types in one file
struct User {
    let name: String
}

struct UserViewModel {       // ← should be in UserViewModel.swift
    let user: User
}
```

```swift
// Mixed type kinds
enum Theme {
    case light, dark
}

class ThemeManager {         // ← should be in ThemeManager.swift
    var current: Theme = .light
}
```

---
