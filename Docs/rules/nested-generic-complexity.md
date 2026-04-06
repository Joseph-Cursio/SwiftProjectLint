[<- Back to Rules](RULES.md)

## Nested Generic Complexity

**Identifier:** `Nested Generic Complexity`
**Category:** Code Quality
**Severity:** Info *(opt-in)*

### Rationale
Types or functions with many generic parameters (4+) become difficult to read, understand, and use correctly. Deeply nested generics like `Result<Array<Optional<MyType>>, Error>` harm readability. Complex where clauses with many constraints are similarly hard to parse. These are often signs that a typealias or intermediate type would improve clarity.

### Discussion
`NestedGenericComplexityVisitor` checks three kinds of complexity:
1. **Parameter count:** Generic declarations with 4+ type parameters
2. **Nesting depth:** Generic argument usage with depth 3+ (e.g., `Result<Array<Optional<T>>, Error>`)
3. **Where clause:** Where clauses with 4+ constraints

This rule is opt-in because generic-heavy code is sometimes necessary in framework/library code.

### Non-Violating Examples
```swift
// 2 generic parameters — fine
func map<Input, Output>(_ transform: (Input) -> Output) -> [Output]

// Nesting depth 2 — fine
var result: Result<[UserResponse], NetworkError>

// 3 where constraints — fine
func process<T, U, V>() where T: Equatable, U: Hashable, V: Codable { }
```

### Violating Examples
```swift
// 4 generic parameters
func transform<Input, Output, Intermediate, Error>(...) { }

// Nesting depth 3
var result: Result<Array<Optional<UserResponse>>, NetworkError>

// 4 where constraints
func process<T>() where T: Equatable, T: Hashable, T: Codable, T: Sendable { }
```

---
