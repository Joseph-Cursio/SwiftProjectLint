[← Back to Rules](RULES.md)

## Long Function

**Identifier:** `Long Function`
**Category:** Code Quality
**Severity:** Warning

### Rationale
A function whose body exceeds 200 characters of source code (in default configuration) is doing too much. Long functions are hard to reason about, difficult to test, and resist refactoring. They accumulate responsibilities that should be separated into smaller, focused functions.

### Discussion
`CodeQualityVisitor` measures function body length in characters (the raw text of the `{ ... }` block). The default threshold is 200 characters. In strict mode the threshold is 150. This is an unconventional metric — most linters count lines — but character count provides a coarser, faster approximation without needing to track newlines. Functions that approach or exceed the threshold should be decomposed into private helper functions with clear, descriptive names.

### Non-Violating Examples
```swift
func validate(_ value: String) -> Bool {
    return !value.isEmpty
}
```

### Violating Examples
```swift
func processUser(_ user: User) {
    // ... 200+ characters of logic mixed together ...
    validateName(user.name)
    validateEmail(user.email)
    saveToDatabase(user)
    sendWelcomeEmail(user)
    logAnalytics(user)
    updateCache(user)
}
```

---
