[← Back to Rules](RULES.md)

## Retroactive Conformance

**Identifier:** `Retroactive Conformance`
**Category:** Code Quality
**Severity:** Warning

### Rationale

`@retroactive` marks a conformance where you make a type you don't own conform to a protocol you also don't own. Swift 5.7+ warns about this because two libraries can independently declare the same conformance, and the linker will silently pick one — leading to undefined behavior that is extremely hard to debug.

This rule flags the highest-risk subset: conformances where **both** the extended type and the protocol are from well-known framework modules (`Swift`, `Foundation`, `SwiftUI`, `UIKit`, `AppKit`, `Combine`). These are exactly the types that many libraries may independently target.

### Discussion

`RetroactiveConformanceVisitor` inspects `ExtensionDeclSyntax` nodes for `@retroactive` in the inheritance list. It checks both the extended type name and the protocol name against a curated set of commonly-used framework types. Only conformances where both sides are high-risk framework types are flagged.

```swift
// Before — linker picks a conformance winner arbitrarily if two libraries do this
extension Array: @retroactive Identifiable {
    public var id: Int { count }
}

// After — wrap your type instead
struct IdentifiableArray<Element>: Identifiable {
    var elements: [Element]
    var id: Int { elements.count }
}
```

### Not Flagged

- Your own type conforming `@retroactive` to a framework protocol — only one side is framework-owned, lower collision risk
- A framework type conforming `@retroactive` to your own protocol — same, only one side is at risk
- Extensions without any `@retroactive` in the inheritance clause

### Violating Examples

```swift
// Both Array (stdlib) and Identifiable (Swift) are framework types
extension Array: @retroactive Identifiable {
    public var id: Int { count }
}

// Both Date (Foundation) and Hashable (Swift) are framework types
extension Date: @retroactive Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(timeIntervalSinceReferenceDate)
    }
}

// Both URL (Foundation) and CustomStringConvertible (Swift) are framework types
extension URL: @retroactive CustomStringConvertible {
    public var description: String { absoluteString }
}
```

---
