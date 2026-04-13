[← Back to Rules](RULES.md)

## Test Missing Require

**Identifier:** `Test Missing Require`
**Category:** Code Quality
**Severity:** Info

### Rationale
In design-by-contract style testing, `#require` validates preconditions before the actual assertion. When a precondition fails, `#require` stops the test immediately with a clear diagnostic pointing at the broken assumption — rather than letting the test cascade into a confusing `#expect` failure downstream.

For example, if a test unwraps an optional and then checks a property on it, using `#require` for the unwrap makes it obvious whether the failure was "the value was nil" versus "the value existed but had the wrong property."

### Scope
- Flags `@Test` functions whose body contains no `#require` macro call
- Searches the entire function body, including nested scopes (loops, closures, etc.)
- Does not flag non-test functions, even if they have "test" in the name
- Does not flag `@Test` functions that already contain at least one `#require`
- **Cross-file aware:** does not flag tests that delegate to a helper function containing `#require`, even if that helper is defined in a different file
- **`_ = try` aware:** does not flag `throws` test functions that use `_ = try expr` as their precondition — the throw-as-assertion idiom used by ViewInspector and similar frameworks, where a thrown error directly communicates a failed precondition

### Non-Violating Examples
```swift
@Test
func testItemCreation() throws {
    let item = try #require(createItem())  // precondition: item must exist
    #expect(item.name == "Expected")
}

@Test
func testCollectionProcessing() throws {
    let items = fetchItems()
    let first = try #require(items.first)  // precondition: must have at least one
    #expect(first.isValid)
}

// Verification helper in another file — not flagged
func verifyNonEmpty(_ collection: [Item]) throws {
    let first = try #require(collection.first)
    #expect(first.isValid)
}

@Test
func testResults() throws {
    let items = fetchItems()
    try verifyNonEmpty(items)              // delegates to helper — not flagged
}

// ViewInspector presence check — not flagged
@Test
func testSectionExists() throws {
    let view = MyView()
    let inspected = try view.inspect()
    _ = try inspected.find(MySectionView.self)  // throws if absent — not flagged
}
```

### Violating Examples
```swift
@Test
func testWithoutPreconditions() {
    let result = compute()
    #expect(result == 42)  // no #require to validate setup
}

@Test
func testEmptyBody() {
    // no assertions at all
}
```

### Known Limitations
- **Helper detection is name-based.** If a helper function shares its name with another function in the project that does not contain `#require`, the rule may incorrectly suppress a violation.
- **`_ = try` requires `throws`.** The discarded-try pattern is only recognised in `throws` test functions.
- **Bare `try` is not suppressed.** Only `_ = try expr` (result explicitly discarded) is treated as a throw-as-precondition. A plain `try setup()` with no binding is considered setup, not a precondition check.

---
