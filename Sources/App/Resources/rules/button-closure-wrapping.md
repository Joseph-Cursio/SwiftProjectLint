[← Back to Rules](RULES.md)

## Button Closure Wrapping

**Identifier:** `Button Closure Wrapping`
**Category:** Code Quality
**Severity:** Info

### Rationale
When a `Button` trailing closure contains only a single no-argument function call, the closure is unnecessary boilerplate. Swift allows passing the function reference directly via the `action:` parameter, which is more concise and idiomatic.

### Discussion
`ButtonClosureWrappingVisitor` detects `Button("Label") { singleCall() }` patterns where the trailing closure wraps a single bare function call with no arguments. Member access chains like `viewModel.save()` are not flagged because they cannot be passed as a simple function reference.

The fix is straightforward — pass the function reference directly:

```swift
// Before
Button("Save") { doSomething() }

// After
Button("Save", action: doSomething)
```

### Non-Violating Examples
```swift
// Already using action parameter
Button("Save", action: doSomething)

// Closure calls a function with arguments
Button("Save") { doSomething(with: value) }

// Closure calls a method on an object
Button("Save") { viewModel.save() }

// Closure has multiple statements
Button("Save") {
    validate()
    submit()
}

// Label form — trailing closure is the label, not the action
Button { doSomething() } label: { Text("Save") }
```

### Violating Examples
```swift
// Single no-argument call in trailing closure
Button("Save") { doSomething() }

// Dismiss wrapped in unnecessary closure
Button("Cancel") { dismiss() }
```

---
