[<- Back to Rules](RULES.md)

## SwiftData Unique Attribute CloudKit

**Identifier:** `SwiftData Unique Attribute CloudKit`
**Category:** Architecture
**Severity:** Warning

### Rationale
`@Attribute(.unique)` on a SwiftData `@Model` property silently breaks CloudKit sync. CloudKit doesn't support uniqueness constraints at the server level, and the combination causes sync conflicts or data loss. Apple's documentation warns against this but it's easy to miss.

### Discussion
`SwiftDataUniqueAttributeCloudKitVisitor` looks for `@Model` classes containing stored properties annotated with `@Attribute(.unique)`. Since detecting CloudKit usage from source alone is not reliable (it's configured in entitlements and project settings), this rule flags all occurrences at `.warning` severity. Projects that don't use CloudKit can suppress the rule per-line.

### Non-Violating Examples
```swift
// No @Attribute(.unique) — safe for CloudKit
@Model
class User {
    var email: String
    var name: String
}

// Other attributes are fine
@Model
class Item {
    @Attribute(.spotlight) var title: String
}

// Not a @Model class — not flagged
class RegularClass {
    @Attribute(.unique) var identifier: String
}
```

### Violating Examples
```swift
// @Attribute(.unique) inside @Model — breaks CloudKit sync
@Model
class User {
    @Attribute(.unique) var email: String
    var name: String
}

@Model
class Product {
    @Attribute(.unique) var sku: String
    @Attribute(.unique) var barcode: String
}
```

---
