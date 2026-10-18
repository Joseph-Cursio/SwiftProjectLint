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

Two more places where a bare `try?` statement is not a discard:

- **A `defer` block.** It can neither throw nor hand a value on, so `defer { try? handle.close() }` is the only form best-effort cleanup can take there. The same goes for a `try?` nested in an `if`, loop or `do` inside the defer (`defer { if let handle { try? handle.close() } }`). A closure the defer creates is a different matter — `defer { queue.async { try? handle.close() } }` still fires, since that body runs later and could throw or return.
- **An implicit return.** The sole expression of a function, getter or subscript with a non-`Void` result is that body's return value: `func makeBookmark(for url: URL) -> Data? { try? url.bookmarkData(…) }`. The same goes for a closure that spells out a non-`Void` return type, and for `Task { try? work() }.value`, whose value is read. A closure with no signature, such as `Button { try? save() }`, is still flagged: whether its value is used depends on a type the syntax does not show.

Not flagged:
- `let x = try? call()` — result captured
- `guard let x = try? call() else { … }` — result checked
- `_ = try? call()` — explicit discard, developer intent is clear
- `items.compactMap { try? f($0) }` — `try?` is the transform closure's result
- `defer { try? FileManager.default.removeItem(at: url) }` — cleanup in a `defer`
- `func data() -> Data? { try? load() }` — the implicit return value
- `await Task.detached { try? describe() }.value` — the task's value is read
- `try call()` / `try! call()` — different operators

### A common intentional case: best-effort I/O in tests
Test setup/teardown frequently uses bare `try? FileManager.default.createDirectory(…)`, `try? "…".write(…)`, or `try? FileManager.default.removeItem(…)` to set up or clean up scratch state where failure is deliberately ignored. Inside a `defer` these are not flagged (see above). Elsewhere they **are** flagged — the result genuinely is discarded — and that is technically correct. In production code the same pattern usually warrants a real fix or a `_ =`. If the test-scaffolding occurrences dominate the report, exclude the rule from test paths via a per-rule override in `.swiftprojectlint.yml`:

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

// best-effort cleanup in a defer block
defer { try? FileManager.default.removeItem(at: scratch) }

// the implicit return value of a single-expression function
func deflate(_ text: String) -> NSData? {
    try? (Data(text.utf8) as NSData).compressed(using: .zlib)
}
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
