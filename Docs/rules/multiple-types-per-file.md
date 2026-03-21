[← Back to Rules](RULES.md)

## Multiple Types Per File

**Identifier:** `Multiple Types Per File`
**Category:** Code Quality
**Severity:** Info

### Rationale
Each type (struct, class, enum, actor) should live in its own file. This makes types easy to find by filename, keeps files focused, and reduces merge conflicts.

### Scope
- Flags top-level type declarations (struct, class, enum, actor) when more than one appears in a file
- Only the second and subsequent types are flagged — the first type is always allowed
- Does **not** flag nested types — a struct containing a private helper enum is a normal pattern
- Does **not** flag extensions — splitting a type across extensions in the same file is idiomatic Swift
- Does **not** flag tightly-coupled companion types whose name shares a prefix with the file's primary type or the file name stem

### Tightly-Coupled Naming Convention
Types that share a camelCase prefix with the primary type are considered companions and are allowed in the same file. This covers common patterns like:

- **Error enums**: `WorkspaceError` in `WorkspaceManager.swift` (shared prefix "Workspace")
- **Supporting data types**: `RuleCategory`, `RuleParameter` in `Rule.swift` (shared prefix "Rule")
- **View subcomponents**: `HealthScoreRing`, `HealthScoreIndicator` in `HealthScoreBadge.swift` (shared prefix "HealthScore")

For `+Extension` files (e.g., `ViolationInspectorViewModel+Options.swift`), the file name stem before the `+` is used for prefix matching.

The minimum shared prefix is 3 characters to avoid spurious matches on short common prefixes.

### Non-Violating Examples
```swift
// Single type per file
struct UserProfile {
    let name: String
}

extension UserProfile: Codable {}
```

```swift
// Nested types are fine
struct TableSection {
    enum Style { case plain, grouped }
    let style: Style
}
```

```swift
// Companion types with shared prefix — fine
// File: WorkspaceManager.swift
class WorkspaceManager {
    func load() {}
}

enum WorkspaceError: Error {
    case notFound
}
```

### Violating Examples
```swift
// Unrelated types in one file
struct Logger {
    let level: Int
}

struct NetworkClient {       // ← should be in NetworkClient.swift
    let url: String
}
```

```swift
// File: Rule.swift
struct Rule {
    let identifier: String
}

enum Severity {              // ← no shared prefix with "Rule"
    case warning, error
}
```

---
