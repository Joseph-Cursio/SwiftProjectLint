[← Back to Rules](RULES.md)

## onChange Old API

**Identifier:** `onChange Old API`
**Category:** Modernization
**Severity:** Info

### Rationale
The `.onChange(of:)` modifier with a single-parameter closure was deprecated in iOS 17. The old API passes the new value to the closure; the modern API provides either zero parameters (action-only) or two parameters (old value and new value).

### Discussion
`OnChangeOldAPIVisitor` detects `.onChange(of:)` calls where the trailing closure has exactly one parameter in its signature. This indicates the deprecated single-value form. The visitor ignores closures with zero parameters (the new action-only form) and two parameters (the new old/new value form).

```swift
// Before — deprecated single-parameter form
.onChange(of: value) { newValue in
    handle(newValue)
}

// After — zero-parameter form
.onChange(of: value) {
    handle(value)
}

// After — two-parameter form
.onChange(of: value) { oldValue, newValue in
    handle(oldValue, newValue)
}
```

### Non-Violating Examples
```swift
// Zero-parameter form — modern API
.onChange(of: value) {
    doSomething()
}

// Two-parameter form — modern API
.onChange(of: value) { old, new in
    handle(old, new)
}

// Other modifiers
.onAppear {
    loadData()
}
```

### Violating Examples
```swift
// Single-parameter form — deprecated in iOS 17
.onChange(of: value) { newValue in
    doSomething(newValue)
}

.onChange(of: count) { val in
    print(val)
}
```

---
