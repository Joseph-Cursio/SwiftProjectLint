[← Back to Rules](RULES.md)

## Force Try

**Identifier:** `Force Try`
**Category:** Code Quality
**Severity:** Warning

### Rationale
`try!` force-unwraps the result of a throwing expression. If the expression throws an error, the program will crash at runtime. Using `do/catch` or `try?` provides safe error handling.

### Discussion
`ForceTryVisitor` detects `try!` expressions by checking for `TryExprSyntax` nodes where `questionOrExclamationMark` is `!`. Regular `try` and `try?` are not flagged.

```swift
// Before
let data = try! JSONDecoder().decode(Model.self, from: jsonData)
let result = try! riskyOperation()

// After
let data = try? JSONDecoder().decode(Model.self, from: jsonData)

do {
    let result = try riskyOperation()
} catch {
    print(error)
}
```

### Non-Violating Examples
```swift
// Regular try inside do/catch
do {
    let result = try someFunc()
} catch {
    handleError(error)
}

// Optional try
let result = try? someFunc()
```

### Violating Examples
```swift
// Force try — crashes on error
let data = try! JSONDecoder().decode(Model.self, from: jsonData)
let value = try! someFunc()
```

---
