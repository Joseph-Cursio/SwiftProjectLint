[<- Back to Rules](RULES.md)

## Magic Boolean Parameter

**Identifier:** `Magic Boolean Parameter`
**Category:** Code Quality
**Severity:** Info

### Rationale
Boolean literal arguments passed without labels are "magic booleans" — `configureView(true, false, true)` is impossible to understand without looking up the function signature. Labeled arguments (`animated: true, recursive: false`) are self-documenting.

### Discussion
`MagicBooleanParameterVisitor` flags function calls with unlabeled boolean literal arguments when:
- There are 2+ unlabeled booleans, OR
- There is 1 unlabeled boolean with 2+ total arguments (context makes it confusing)

Single-argument calls like `setEnabled(false)` are not flagged since the meaning is usually clear from the function name.

Well-known APIs where unlabeled booleans are standard are suppressed: `print`, `XCTAssert*`, `min`, `max`, `assert`, `precondition`.

### Non-Violating Examples
```swift
// Labeled — self-documenting
configureView(animated: true, recursive: false, verbose: true)

// Single boolean argument — clear from function name
setEnabled(false)
toggle(true)

// Known APIs
XCTAssertEqual(result, true)
print(value, true)
```

### Violating Examples
```swift
// Multiple unlabeled booleans — unclear
configureView(true, false, true)

// Mixed arguments with unlabeled boolean
process(data, true)
render(view, false, 42)
```

---
