[← Back to Rules](RULES.md)

## Map Used For Side Effects

**Identifier:** `Map Used For Side Effects`
**Category:** Code Quality
**Severity:** Warning

### Rationale
`map`, `compactMap`, and `flatMap` return a transformed collection. Using them as bare statements throws that collection away, making the transformation meaningless. This is almost always a `forEach` mistake — common in AI-generated code and among developers from imperative languages.

### Discussion
`MapUsedForSideEffectsVisitor` visits every `FunctionCallExprSyntax`. It fires when the callee is a member access named `map`, `compactMap`, or `flatMap` and the call is the direct item of a `CodeBlockItemSyntax` — meaning the result is not assigned, returned, or passed anywhere.

`filter`, `reduce`, `sorted`, and other non-transform methods are not flagged.

### Non-Violating Examples
```swift
let names = users.map { $0.name }          // result captured

return items.compactMap { $0.value }       // result returned

items.forEach { save($0) }                 // correct API for side effects
```

### Violating Examples
```swift
items.map { save($0) }                     // result thrown away — use forEach

users.compactMap { $0.profile }            // result discarded

nodes.flatMap { $0.children }              // result never used
```

---
