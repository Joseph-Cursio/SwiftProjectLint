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

---
