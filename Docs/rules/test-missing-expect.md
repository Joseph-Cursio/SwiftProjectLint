[← Back to Rules](RULES.md)

## Test Missing Expect

**Identifier:** `Test Missing Expect`
**Category:** Code Quality
**Severity:** Info

### Rationale
In design-by-contract testing, `#require` validates preconditions and `#expect` verifies postconditions. A test with `#require` but no `#expect` confirms that setup is valid but never asserts anything about the behavior under test.

This is the mirror of `testMissingRequire`: together they enforce the full contract pattern where every test has at least one precondition (`#require`) and at least one postcondition (`#expect`).

### Scope
- Flags `@Test` functions whose body contains no `#expect` macro call
- Searches the entire function body, including nested scopes (loops, closures, etc.)
- Does not flag non-test functions
- Does not flag tests that have at least one `#expect`
- **Cross-file aware:** does not flag tests that delegate to a helper function containing `#expect`, even if that helper is defined in a different file
- **`_ = try` aware:** does not flag `throws` test functions that use `_ = try expr` as their postcondition — the throw-as-assertion idiom used by ViewInspector and similar frameworks

### Non-Violating Examples
```swift
@Test
func testItemCreation() throws {
    let item = try #require(createItem())
    #expect(item.name == "Expected")       // postcondition present
}

@Test
func testSimpleValue() {
    #expect(compute() == 42)               // postcondition present
}

// Verification helper in another file — not flagged
func verifyResult(_ result: Result) {
    #expect(result.isValid)
    #expect(result.value == 42)
}

@Test
func testComputation() {
    let item = try #require(createItem())
    verifyResult(item.result)              // delegates to helper — not flagged
}

// ViewInspector presence assertion — not flagged
@Test
func testTitleExists() throws {
    let view = MyView()
    let inspected = try view.inspect()
    _ = try inspected.find(ViewType.Text.self)  // throws if absent — not flagged
}
```

### Violating Examples
```swift
@Test
func testPreconditionOnly() throws {
    let item = try #require(createItem())  // precondition only
    let child = try #require(item.children.first)
    // no #expect — what is this test verifying?
}

@Test
func testSetupOnly() {
    let result = compute()
    print(result)                          // no assertions at all
}
```

### Known Limitations
- **Helper detection is name-based.** If a helper function shares its name with another function in the project that does not contain `#expect`, the rule may incorrectly suppress a violation.
- **`_ = try` requires `throws`.** The discarded-try pattern is only recognised in `throws` test functions.
- **Bare `try` is not suppressed.** Only `_ = try expr` (result explicitly discarded) is treated as a throw-as-assertion. A plain `try setup()` with no binding is considered setup, not a postcondition.

---
