[← Back to Rules](RULES.md)

## Could Be Private Member

**Identifier:** `Could Be Private Member`
**Category:** Code Quality
**Severity:** Info

### Rationale
Methods and properties with default (`internal`) access that are only used within their declaring file have a wider scope than necessary. Narrowing them to `private` communicates intent, reduces the type's public interface, and lets the compiler optimize.

### Discussion
This is a **cross-file rule**. It scans all project files in two phases:

1. **Collection phase:** Records all non-private member declarations (functions and properties) with their declaring type and file, and records every identifier reference per file.
2. **Analysis phase:** Flags members whose name does not appear in any file other than the one where they are declared.

Because SwiftSyntax has no type resolution, the rule uses a conservative strategy: a member is only flagged when its name is **unique across the entire project** (does not appear in any other file). This avoids false positives from same-named members on different types (e.g., `name` on `Rule` vs `name` on `User`), at the cost of missing common names.

### Scope
- Flags `internal` (default access) functions and properties only referenced in their declaring file
- Does **not** flag members with explicit access modifiers (`private`, `fileprivate`, `public`, `open`, `internal`)
- Does **not** flag `override` members — they implement a superclass requirement
- Does **not** flag `@objc` members — they may be invoked via selectors
- Does **not** flag properties with property wrappers (`@State`, `@Binding`, etc.) — accessed by the SwiftUI framework
- Does **not** flag struct stored properties without default values — these are part of the memberwise initializer and must remain accessible to callers
- Does **not** flag operator conformances (`==`, `<`, `>`) — typically protocol requirements
- Does **not** flag members inside already-private types — they are already inaccessible outside the file
- Does **not** flag local variables inside function bodies, closures, or computed property accessors
- Does **not** flag framework delegate hooks (`body`, `init`, `makeBody`, `sizeThatFits`, `applicationDidFinishLaunching`, `userNotificationCenter`, etc.)
- Does **not** flag members in test files
- Does **not** flag members in example/fixture directories (`ExampleCode/`, `Fixtures/`, `Resources/`, `Examples/`, `Samples/`)
- Does **not** flag members on types conforming to project-defined protocols — these may be protocol requirements that cannot be private

### Non-Violating Examples
```swift
// File: Service.swift
struct Service {
    func fetchData() -> [String] { [] }   // used in Consumer.swift
}

// File: Consumer.swift
struct Consumer {
    let service = Service()
    func load() { let data = service.fetchData() }
}
```

### See Also
For more thorough access-level analysis with full type resolution, consider [Periphery](https://github.com/peripheryapp/periphery). It uses SourceKit's build index to track member references precisely, catching cases this rule misses due to name ambiguity. The tradeoff is it requires a full build step, while this rule runs instantly alongside other SwiftProjectLint checks.

### Violating Examples
```swift
// File: MyView.swift
struct MyView: View {
    func buildAttributedTitle() -> AttributedString { ... }  // only used here
    var body: some View { Text(buildAttributedTitle()) }
}
```

---
