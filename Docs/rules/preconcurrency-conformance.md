[← Back to Rules](RULES.md)

## Preconcurrency Conformance

**Identifier:** `Preconcurrency Conformance`
**Category:** Code Quality
**Severity:** Warning

### Rationale

`@preconcurrency` exists to ease migration of code that predates Swift Concurrency. On an `import` statement, it softens isolation errors from a third-party library that hasn't adopted `Sendable` annotations yet — a legitimate use outside your control.

On a **conformance of your own type**, it grandfathers in isolation errors that belong to you. Those errors are not noise — they point to real actor isolation or `Sendable` problems in your design. Silencing them delays the fix and leaves potential data races unaddressed.

### Discussion

`PreconcurrencyConformanceVisitor` distinguishes the two forms:

| Form | Flagged? |
|---|---|
| `@preconcurrency import SomeLegacySDK` | No — legitimate third-party migration aid |
| `@preconcurrency extension MyType: Protocol` where `MyType` is project-defined | Yes |

Detection uses `knownLocalTypeNames`, a project-wide pre-scan of all class, struct, enum, and actor declarations. If the extended type is found in that set, it's yours to fix.

```swift
// Before — silences isolation errors you own
@preconcurrency
extension MyViewModel: SomeProtocol {}

// After — fix the underlying isolation
@MainActor
extension MyViewModel: SomeProtocol {}

// Or — make the type Sendable where appropriate
extension MyViewModel: SomeProtocol, Sendable {}
```

### Not Flagged

```swift
// Import form — third-party SDK, legitimate
@preconcurrency import SomeLegacySDK

// Conformance of a type not recognized as local (treat as third-party)
@preconcurrency
extension ExternalLibraryType: MyProtocol {}
```

### Scope

This rule is most precise for **single-target monoliths** where all types are visible to the pre-scan. In multi-package projects, types defined in other packages won't appear in `knownLocalTypeNames` and won't be flagged — that's a false negative, not a false positive.

---
