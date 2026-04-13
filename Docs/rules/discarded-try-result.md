[← Back to Rules](RULES.md)

## Discarded Try Result

**Identifier:** `Discarded Try Result`
**Category:** Code Quality
**Severity:** Warning

### Rationale
`try?` as a bare statement discards both the return value and the error — the maximum-discard form of a function call. Almost always a mistake: either the result matters and should be captured, or the error matters and should be handled with `do/catch`.

### Discussion
`DiscardedTryResultVisitor` visits every `TryExprSyntax`. It fires when the `?` operator is present and the entire expression is the direct item of a `CodeBlockItemSyntax` — meaning the result is not assigned, returned, or passed anywhere.

Not flagged:
- `let x = try? call()` — result captured
- `guard let x = try? call() else { … }` — result checked
- `_ = try? call()` — explicit discard, developer intent is clear
- `try call()` / `try! call()` — different operators

### Non-Violating Examples
```swift
let data = try? loadData()             // result captured

guard let user = try? decode(json) else { return }  // result checked

_ = try? cleanupTemporaryFile()        // explicit discard — intent is clear
```

### Violating Examples
```swift
try? save()                            // result and error both silently lost

for item in queue {
    try? process(item)                 // failures invisible in a loop
}
```

---
