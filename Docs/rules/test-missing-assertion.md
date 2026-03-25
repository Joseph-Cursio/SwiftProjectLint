[← Back to Rules](RULES.md)

## Test Missing Assertion

**Identifier:** `Test Missing Assertion`
**Category:** Code Quality
**Severity:** Warning

### Rationale
A `@Test` function that contains neither `#expect` nor `#require` is effectively a "does it crash" test. While this is occasionally intentional (verifying that setup completes without throwing), it usually indicates a forgotten assertion. The test exercises a code path but never checks the result.

Unlike `testMissingRequire` (which nudges toward precondition checks), this rule catches tests that verify *nothing at all*.

### Scope
- Flags `@Test` functions whose body contains no `#expect` and no `#require` macro call
- Searches the entire function body, including nested scopes (loops, closures, etc.)
- Does not flag non-test functions
- Does not flag tests that have at least one `#expect` or `#require`

### Non-Violating Examples
```swift
@Test
func testValueComputation() {
    let result = compute()
    #expect(result == 42)        // has #expect
}

@Test
func testUnwrapAndCheck() throws {
    let item = try #require(createItem())  // has #require
    #expect(item.isValid)
}

@Test
func testPreconditionOnly() throws {
    let val = try #require(fetchValue())   // has #require — still a real test
}
```

### Violating Examples
```swift
@Test
func testSetupOnly() {
    let result = compute()
    print(result)              // no assertions at all
}

@Test
func testEmpty() {
    // forgot to write the assertion
}
```

---
