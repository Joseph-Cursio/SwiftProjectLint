[← Back to Rules](RULES.md)

## Could Be Private

**Identifier:** `Could Be Private`
**Category:** Code Quality
**Severity:** Info

### Rationale
Types with default (`internal`) access that are only used in their declaring file have a wider scope than necessary. Narrowing them to `private` makes the codebase easier to reason about — readers know at a glance that a `private` type is only relevant within its file, and the compiler can optimize accordingly.

### Discussion
This is a **cross-file rule**. It scans all project files in two phases:

1. **Collection phase:** Walks every file to record top-level type declarations (struct, class, enum, actor) that have no explicit access modifier, and records every type reference.
2. **Analysis phase:** Compares declarations against references. Types that are never referenced outside their declaring file are flagged.

### Scope
- Flags top-level types with default (internal) access that are only referenced in their declaring file
- Does **not** flag types with explicit access modifiers (`private`, `fileprivate`, `public`, `open`, `internal`)
- Does **not** flag nested types — only top-level declarations
- Does **not** flag types in test files (paths containing `Test` or `Tests`)
- Does **not** flag `App`-conforming structs (the app entry point cannot be private)

### Non-Violating Examples
```swift
// File: SharedModel.swift
struct SharedModel {        // Used in other files — not flagged
    let name: String
}

// File: Consumer.swift
struct Consumer: View {
    let model: SharedModel  // ← cross-file reference
    var body: some View { Text(model.name) }
}
```

```swift
// Already private — not flagged
private struct HelperView: View {
    var body: some View { Text("helper") }
}
```

### Violating Examples
```swift
// File: MyView.swift
struct MyView: View {
    var body: some View { BadgeView() }
}

struct BadgeView: View {    // ← only used in this file, could be private
    var body: some View { Text("badge") }
}
```

---
