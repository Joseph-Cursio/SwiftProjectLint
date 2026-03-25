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

---
