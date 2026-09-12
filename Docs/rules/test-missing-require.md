[← Back to Rules](RULES.md)

## Test Missing Require

**Identifier:** `Test Missing Require`
**Category:** Code Quality
**Severity:** Info
**Opt-in:** yes — enable with `enabled_only` or `--rules`

### Rationale
A `@Test` that force-unwraps, `try!`s or `as!`s **traps** when the value is not what the test assumed — and a trap takes the whole test process down, every other test with it, with no diagnostic naming the test that did it. `try #require(…)` fails that one test, says why, and is a one-line replacement.

### What this rule is not
It does **not** flag a test for using only `#expect`. The two macros are not interchangeable and the choice is not a quality signal:

- `#expect` records a failure and **continues** — correct for assertions about the result under test.
- `#require` **throws and halts** — correct when continuing would be meaningless or would crash.

A test whose assertions are independent observations should use `#expect` throughout. Adding `#require` to satisfy a rule would make those tests worse, since a first failure would then hide the rest.

The rule previously flagged every `@Test` containing no `#require`, which is the normal shape: **1,341 findings on one subject, 47% of that run**, against a suite with no defect it was pointing at.

### Discussion
`TestMissingRequireVisitor` flags a `@Test` with no `#require` **and** at least one trapping construct: a force unwrap, `try!`, or `as!`. The message names which one it found, since a rule that fires on a subset owes the reader why it picked this test out of the suite.

Measured over 13,200 `@Test` functions without `#require` across fifteen repositories: **101** carry one of these shapes, 0.8%.

**Index subscripting is deliberately excluded.** It was proposed as a fourth shape and measured: 448 of those 13,200 subscript by a literal index — more than all three trapping shapes combined. In a test the collection is usually one the test just built as a literal, where it cannot trap, and syntax cannot tell that apart from an unchecked access on a fetched one.

The honest caveat: `#expect(items.count == 3)` does **not** halt, so a subscript after it still traps when the expectation fails. Those cases are real and this rule does not find them.

Source inside a string literal is text, not code — a linter's own suite is full of embedded Swift fixtures, and they are not flagged.

### Non-Violating Examples
```swift
@Test func hasVersion() {                    // #expect alone — the normal shape
    #expect(CLI.configuration.version.isEmpty == false)
}

@Test func unwrapsSafely() throws {          // already halts with a diagnostic
    let snapshot = try #require(fetchSnapshots().first)
    #expect(snapshot.id == 1)
}

@Test func optionalHandling() throws {       // `try?` and `as?` do not trap
    let value = try? decode()
    #expect(value?.isEmpty == false)
}
```

### Violating Examples
```swift
@Test func snapshot() throws {
    let snapshot = fetchSnapshots().first!   // empty → traps the whole process
    #expect(snapshot.id == 1)
}

@Test func decodes() {
    let value = try! decode()                // throws → traps
    #expect(value == 1)
}

@Test func casts() {
    let typed = anything() as! Int           // wrong type → traps
    #expect(typed == 1)
}
```

---
