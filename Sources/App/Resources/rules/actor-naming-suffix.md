[← Back to Rules](RULES.md)

## Actor Naming Suffix

**Identifier:** `Actor Naming Suffix`
**Category:** Code Quality
**Severity:** Info

### Rationale
Naming actors with an `Actor` suffix makes Swift's concurrency isolation semantics visible at every call site. When a property is typed as `ImageDownloaderActor`, any `await` expressions at call sites have a clear explanation — the call crosses an actor boundary.

### Discussion
`NamingConventionVisitor` checks every `actor` declaration. If the name does not end with `Actor`, an issue is reported. Like the protocol naming rule, this is a project-specific convention that prioritizes clarity over brevity.

### Non-Violating Examples
```swift
actor ImageDownloaderActor {
    func download(url: URL) async -> Data { ... }
}
```

### Violating Examples
```swift
actor ImageDownloader {  // missing "Actor" suffix
    func download(url: URL) async -> Data { ... }
}
```

---
