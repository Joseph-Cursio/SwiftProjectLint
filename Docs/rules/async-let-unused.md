[← Back to Rules](RULES.md)

## Async Let Unused

**Identifier:** `Async Let Unused`
**Category:** Code Quality
**Severity:** Warning

### Rationale
`async let _ = expression` spawns an asynchronous task but immediately discards the result. Because the task is tied to the enclosing scope via structured concurrency, it is automatically cancelled when the scope exits. This wastes the work and can mask bugs where the result was intended to be awaited.

### Discussion
`AsyncLetUnusedVisitor` detects `VariableDeclSyntax` nodes where:
1. The declaration has an `async` modifier
2. The binding specifier is `let`
3. The binding pattern is a wildcard (`_`)

If you need the side effect of the async work, assign to a named variable and `await` it. If you do not need the result, remove the `async let` entirely.

### Non-Violating Examples
```swift
// Named async let — result will be awaited
func example() async {
    async let result = fetchData()
    let data = await result
    process(data)
}

// Regular let with wildcard — not async, no wasted work
let _ = syncFunc()
```

### Violating Examples
```swift
// async let with wildcard — task cancelled at scope exit
func example() async {
    async let _ = fetchData()
}
```

---
