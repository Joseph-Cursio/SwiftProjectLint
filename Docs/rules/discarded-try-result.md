[← Back to Rules](RULES.md)

## Discarded Try Result

**Identifier:** `Discarded Try Result`
**Category:** Code Quality
**Severity:** Warning

### Rationale
`try?` as a bare statement discards both the return value and the error — the maximum-discard form of a function call. Almost always a mistake: either the result matters and should be captured, or the error matters and should be handled with `do/catch`.

### Discussion
`DiscardedTryResultVisitor` visits every `TryExprSyntax`. It fires when the `?` operator is present and the entire expression is the direct item of a `CodeBlockItemSyntax` — meaning the result is not assigned, returned, or passed anywhere.

One structural exception: a single-expression closure body is *also* a bare `CodeBlockItemSyntax`, but when that closure is passed to a value-transforming method (`map`, `compactMap`, `flatMap`) the `try?` is the closure's **result**, collected by the caller rather than discarded. So a `try?` that is the last statement of a `map`/`compactMap`/`flatMap` closure is not flagged (e.g. the common `findAll(...).compactMap { try? $0.string() }` idiom). A `try?` in a Void-returning closure such as `Button { try? save() }` or `forEach { try? f() }` still fires, because there the value really is discarded. (Misusing `map` purely for side effects is covered separately by the [Map Used For Side Effects](map-used-for-side-effects.md) rule.)

Not flagged:
- `let x = try? call()` — result captured
- `guard let x = try? call() else { … }` — result checked
- `_ = try? call()` — explicit discard, developer intent is clear
- `items.compactMap { try? f($0) }` — `try?` is the transform closure's result
- `try call()` / `try! call()` — different operators

### A common intentional case: best-effort I/O in tests
Test setup/teardown frequently uses bare `try? FileManager.default.createDirectory(…)`, `try? "…".write(…)`, or `try? FileManager.default.removeItem(…)` to set up or clean up scratch state where failure is deliberately ignored. These **are** flagged — the result genuinely is discarded — and that is technically correct. In production code the same pattern usually warrants a real fix or a `_ =`. If the test-scaffolding occurrences dominate the report, exclude the rule from test paths via a per-rule override in `.swiftprojectlint.yml`:

```yaml
rules:
  "Discarded Try Result":
    excluded_paths:
      - "Tests/"
```

This keeps the rule active on production code while silencing the intentional best-effort I/O in tests.

### Non-Violating Examples
```swift
let data = try? loadData()             // result captured

guard let user = try? decode(json) else { return }  // result checked

_ = try? cleanupTemporaryFile()        // explicit discard — intent is clear

// try? as a transform closure's result — collected, not discarded
let names = views.compactMap { try? $0.string() }
```

### Violating Examples
```swift
try? save()                            // result and error both silently lost

for item in queue {
    try? process(item)                 // failures invisible in a loop
}

Button("Save") { try? save() }         // Void closure — result is discarded
```

---
