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
- **Cross-file aware:** does not flag tests that delegate to a helper function containing assertions, even if that helper is defined in a different file
- **`_ = try` aware:** does not flag `throws` test functions that use `_ = try expr` as their assertion — the throw-as-assertion idiom used by ViewInspector and similar frameworks

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

// Verification helper in another file — not flagged
func verifyIssues(_ issues: [LintIssue], count: Int) {
    #expect(issues.count == count)
}

@Test
func testDetection() {
    let issues = lint(source)
    verifyIssues(issues, count: 2)         // delegates to helper — not flagged
}

// ViewInspector presence assertion — not flagged
@Test
func testButtonExists() throws {
    let view = MyView()
    let inspected = try view.inspect()
    _ = try inspected.find(ViewType.Button.self)  // throws if absent — not flagged
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

### Known Limitations
- **Helper detection is name-based.** If a helper function shares its name with another function in the project that does not contain assertions, the rule may incorrectly suppress a violation.
- **`_ = try` requires `throws`.** The discarded-try pattern is only recognised in `throws` test functions. A non-throwing test with `_ = try?` or `_ = try!` is not suppressed.
- **Bare `try` is not suppressed.** Only `_ = try expr` (result explicitly discarded) is treated as a throw-as-assertion. A plain `try setup()` with no binding is considered setup, not an assertion.

---
