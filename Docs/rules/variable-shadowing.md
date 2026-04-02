[← Back to Rules](RULES.md)

## Variable Shadowing

**Identifier:** `Variable Shadowing`
**Category:** Code Quality
**Severity:** Warning

### Rationale
When an inner scope declares a variable with the same name as one in an outer scope, the outer variable becomes inaccessible within that scope. This can cause subtle bugs, especially inside closures where the captured value may not be what the developer expects.

### Discussion
`VariableShadowingVisitor` maintains a scope stack that tracks variable names across nested scopes. When a new declaration reuses a name from an outer scope, the rule flags it as a potential source of confusion.

The visitor pushes a new scope frame on entering `CodeBlockSyntax`, `ClosureExprSyntax`, and `ForStmtSyntax` nodes, and pops the frame on exit. Variable declarations, function parameters, closure parameters, and for-loop binding patterns are all checked against outer scope frames.

**Idiomatic optional binding is excluded.** Swift's `if let` and `guard let` patterns intentionally shadow an optional with its unwrapped value. The visitor detects these by walking up to `OptionalBindingConditionSyntax` and checking whether the bound name matches the initializer expression (e.g., `if let x = x`) or has no initializer (Swift 5.7+ shorthand `if let x`).

### Flagged Patterns

| Context | Example |
|---------|---------|
| Nested block re-declaration | `let x = 1; if true { let x = 2 }` |
| Closure re-declaration | `let x = 1; closure { let x = 2 }` |
| Closure parameter shadow | `let x = 1; closure { (x: Int) in ... }` |
| Nested function parameter | `let x = 1; func inner(x: Int) { ... }` |
| For-loop variable | `let i = 0; for i in 0..<10 { ... }` |
| Type-changing shadow | `let x = 1; if true { let x = "hello" }` |

### Ignored Patterns (Not Flagged)

| Context | Example |
|---------|---------|
| Optional binding | `if let x = x { ... }` |
| Shorthand optional binding | `if let x { ... }` |
| Guard unwrapping | `guard let x = x else { return }` |
| Shorthand guard | `guard let x else { return }` |
| Sibling scopes (no nesting) | `if a { let x = 1 }; if b { let x = 2 }` |
| Underscore placeholder | `let _ = foo(); if true { let _ = bar() }` |

### Violating Examples
```swift
func example() {
    let value = 10
    if someCondition {
        let value = 20  // shadows outer 'value'
        print(value)
    }
}

func process() {
    let count = items.count
    let closure = { (count: Int) in  // shadows outer 'count'
        print(count)
    }
}
```

### Non-Violating Examples
```swift
func example() {
    let name: String? = fetchName()
    guard let name else { return }  // idiomatic unwrap, not flagged
    print(name)
}

func process() {
    let value: Int? = compute()
    if let value = value {  // idiomatic unwrap, not flagged
        use(value)
    }
}
```

---
