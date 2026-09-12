[← Back to Rules](RULES.md)

## Map Used For Side Effects

**Identifier:** `Map Used For Side Effects`
**Category:** Code Quality
**Severity:** Warning

### Rationale
`map`, `compactMap`, and `flatMap` return a transformed collection. Using them as bare statements throws that collection away, making the transformation meaningless. This is almost always a `forEach` mistake — common in AI-generated code and among developers from imperative languages.

### Discussion
`MapUsedForSideEffectsVisitor` visits every `FunctionCallExprSyntax`. It fires when the callee is a member access named `map`, `compactMap`, or `flatMap`, the call is the direct item of a `CodeBlockItemSyntax`, **and that item is not an implicit return**.

That last clause is load-bearing and was missing. A bare statement is a `CodeBlockItem` — but so is the sole expression of a body that returns it, and Swift code omitting `return` is the common case rather than the exception. Without the check the rule fired on the ordinary shape: 38 findings across five repositories, **all 38 false positives**.

An item is an implicit return when it is the *sole* statement of its block (a statement among several cannot be one, since Swift admits the implicit form only for a single expression) and the block belongs to:

- a function with a return clause — `func f() -> [T] { items.map { … } }`
- a getter, in either spelling
- a closure — the expected type is not knowable from syntax, so this errs toward silence
- an `if` / `switch` **expression** branch, which defers to wherever the `if`/`switch` itself sits

`func f() { items.map { … } }` — a sole statement in a body returning nothing — is still flagged. That is the case the rule exists for.

`filter`, `reduce`, `sorted`, and other non-transform methods are not flagged.

### Non-Violating Examples
```swift
let names = users.map { $0.name }          // result captured

return items.compactMap { $0.value }       // result returned

items.forEach { save($0) }                 // correct API for side effects

func doubled(_ items: [Int]) -> [Int] {    // implicit return — the result IS the value
    items.map { $0 * 2 }
}

var doubled: [Int] { items.map { $0 * 2 } }   // implicit return from a getter
```

### Violating Examples
```swift
items.map { save($0) }                     // result thrown away — use forEach

users.compactMap { $0.profile }            // result discarded

nodes.flatMap { $0.children }              // result never used

func f(_ items: [Int]) {                   // sole statement, but nothing is returned
    items.map { save($0) }
}

if flag {                                  // a branch of an if STATEMENT, not an expression
    items.map { save($0) }
}
```

---
