[← Back to Rules](RULES.md)

## Could Be Private

**Identifier:** `Could Be Private`
**Category:** Code Quality
**Severity:** Info

### Rationale

Swift's default access level is `internal`, which means every type you declare is potentially visible to every other file in the same module. Most of the time that's far more access than needed. Types that are only used in their declaring file are implementation details — giving them `private` (or `fileprivate`) communicates this explicitly. Readers can see at a glance that the type is not part of the module's surface area, and the compiler can enforce the constraint so the type can't accidentally be used elsewhere.

Narrowing scope is one of the cheapest ways to keep a codebase easy to reason about. A type marked `private` is a promise: *this is internal machinery, not a contract*.

### How it works

This is a **cross-file rule**. It requires scanning the entire project before it can report anything — single-file analysis cannot determine whether a type escapes its declaring file. The rule runs in two phases:

**Phase 1 — Collection.** Every file is walked and two things are recorded:
- Top-level type declarations (`struct`, `class`, `enum`, `actor`) with no explicit access modifier
- Every reference to a type name across all files, tracked as *typeName → set of files that mention it*

References are collected from three AST sites:
- Type annotations and inheritance clauses — `IdentifierTypeSyntax` (`:`, `as`, generic constraints, etc.)
- Direct identifier expressions that start with an uppercase letter — `DeclReferenceExprSyntax`
- `Type.member` patterns — the base of a `MemberAccessExprSyntax` where base is uppercase (e.g., `Severity.error` registers a reference to `Severity`)

**Phase 2 — Analysis.** For each collected declaration, the rule checks whether the type name appears in any file *other than* the declaring file. If not, it reports the issue.

### Scope

The rule flags top-level types with default (`internal`) access that are never referenced outside their declaring file. The following are always skipped:

- **Explicit access modifiers** — types already marked `private`, `fileprivate`, `public`, `open`, or `internal`
- **Nested types** — only top-level declarations are checked; types nested inside another type are out of scope
- **Test files** — any file whose path contains `Tests/` or ends in `Test.swift`
- **`App`-conforming structs** — the SwiftUI app entry point (`struct MyApp: App`) cannot be `private`
- **`@main`-annotated types** — the compiler-designated entry point for a target cannot be `private`

### `private` vs. `fileprivate`

When a file contains multiple types that collaborate — for example, a view and its helper view — both types may be file-scoped but they need to reference each other. In that case `private` works because both declarations are in the same file. However, if a type is defined at file scope and accessed by a member of a *different* type in the same file, `fileprivate` may be the better choice depending on your style. The rule suggests `private`; use `fileprivate` if needed.

```swift
// File: MyView.swift
struct MyView: View {
    var body: some View { BadgeView() }
}

private struct BadgeView: View {    // private is fine — only used by MyView in this file
    var body: some View { Text("badge") }
}
```

### Known limitations

Because the rule uses name-based reference tracking without type resolution, it has two failure modes:

**False negatives (misses a real violation):** The rule can report a false *non*-violation if a type's name happens to be mentioned in another file as an unrelated identifier. For example, if a file happens to contain the word `Status` in a comment or string literal and another file has `enum Status`, the reference won't match (comments and string literals are not scanned). But if another type elsewhere in the project is also named `Status`, its usages will register as references to *this* `Status`, and the rule will conservatively not flag it. This is intentional — false negatives are preferable to false positives for an info-severity rule.

**Untracked reference patterns:** Some legitimate references are not visible to a syntax-only scanner:
- `NSClassFromString("MyClass")` — runtime string-based lookups
- `@objc` exposure consumed via selectors in Obj-C code
- Types only referenced through indirect module imports in mixed-language targets
- References in `#if` branches not active at parse time

For these cases, Periphery (see [See Also](#see-also)) provides more accurate analysis.

### Non-violating examples

```swift
// SharedModel.swift — referenced from another file, not flagged
struct SharedModel {
    let name: String
}

// Consumer.swift — cross-file reference keeps SharedModel internal
struct Consumer: View {
    let model: SharedModel          // ← reference in a different file
    var body: some View { Text(model.name) }
}
```

```swift
// Explicit access — not flagged regardless of usage
public struct PublicModel { }
private struct PrivateHelper { }
fileprivate struct FileHelper { }
```

```swift
// SwiftUI app entry — exempt
@main
struct MyApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}
```

### Violating examples

```swift
// MyView.swift — BadgeView used only in this file
struct MyView: View {
    var body: some View { BadgeView() }
}

struct BadgeView: View {            // ← only used above, could be private
    var body: some View { Text("badge") }
}
```

```swift
// StatusBar.swift — helper enum used only here
enum DisplayMode { case compact, expanded }   // ← could be private

struct StatusBar: View {
    var mode: DisplayMode = .compact
    var body: some View { Text(mode == .compact ? "—" : "≡") }
}
```

```swift
// AnalysisEngine.swift — helper class only used within this file
class ResultCache {                 // ← could be private
    var entries: [String: Any] = [:]
}

class AnalysisEngine {
    private let cache = ResultCache()
}
```

### See Also

- [Could Be Private Member](could-be-private-member.md) — same idea applied to individual methods and properties rather than top-level types
- [Protocol Could Be Private](protocol-could-be-private.md) — same idea applied to protocol declarations
- [Periphery](https://github.com/peripheryapp/periphery) — uses SourceKit's full build index for precise dead-code and unused-access analysis. More accurate than this rule, but requires a full build step

---
