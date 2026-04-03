[← Back to Rules](RULES.md)

## Variable Shadowing

**Identifier:** `Variable Shadowing`
**Category:** Code Quality
**Severity:** Error / Warning (tiered)

### Rationale
When an inner scope declares a variable with the same name as one in an outer scope, the outer variable becomes inaccessible within that scope. This can cause subtle bugs, especially inside closures where the captured value may not be what the developer expects.

### Discussion
`VariableShadowingVisitor` maintains a scope stack that tracks variable names across nested scopes. When a new declaration reuses a name from an outer scope, the rule flags it as a potential source of confusion.

The visitor pushes a new scope frame on entering `CodeBlockSyntax`, `ClosureExprSyntax`, and `ForStmtSyntax` nodes, and pops the frame on exit. Variable declarations, function parameters, closure parameters, and for-loop binding patterns are all checked against outer scope frames.

**Idiomatic type-narrowing patterns are excluded.** The visitor recognises several Swift patterns where shadowing is intentional and expected:

- **Optional binding** — `if let x = x` / `guard let x = x`, and the Swift 5.7+ shorthand `if let x` / `guard let x`. These intentionally shadow an optional with its unwrapped value.
- **Conditional type cast binding** — `if let x = x as? T` / `guard let x = x as? T`. These narrow a value to a more specific type within a scope, analogous to optional unwrapping.
- **Weak-to-strong self capture** — `guard let self = self` / `guard let self` inside `[weak self]` closures. This is the standard pattern for promoting a weak reference to a strong one.

The visitor detects these by walking up to `OptionalBindingConditionSyntax` and checking whether the bound name matches the initializer expression directly, via a conditional `as?` cast, or has no initializer (shorthand form).

**Tiered severity.** The rule uses two severity levels:

- **Error** — Clear-cut shadowing where the inner declaration has no relationship to the outer variable. These are almost always bugs or sources of confusion (e.g., `let x = 1; if true { let x = 2 }`).
- **Warning** — Ambiguous shadowing where the initializer references the same-named outer variable. The developer likely intended to derive a new value from the original (e.g., `let config = config.cleaned()`), but a different name would be clearer.

### Flagged as Error

| Context | Example |
|---------|---------|
| Nested block re-declaration | `let x = 1; if true { let x = 2 }` |
| Closure re-declaration | `let x = 1; closure { let x = 2 }` |
| Closure parameter shadow | `let x = 1; closure { (x: Int) in ... }` |
| Nested function parameter | `let x = 1; func inner(x: Int) { ... }` |
| For-loop variable | `let i = 0; for i in 0..<10 { ... }` |
| Type-changing shadow | `let x = 1; if true { let x = "hello" }` |

### Flagged as Warning

| Context | Example |
|---------|---------|
| Var-to-let immutability | `var x = load(); if true { let x = x.cleaned() }` |
| Derived value in closure | `let items = [1, 2]; closure { let items = items.sorted() }` |
| Transform with same name | `let data = fetch(); if true { let data = transform(data) }` |

### Ignored Patterns (Not Flagged)

| Context | Example |
|---------|---------|
| Optional binding | `if let x = x { ... }` |
| Shorthand optional binding | `if let x { ... }` |
| Guard unwrapping | `guard let x = x else { return }` |
| Shorthand guard | `guard let x else { return }` |
| Conditional type cast | `if let x = x as? Int { ... }` |
| Guard type cast | `guard let x = x as? String else { return }` |
| Weak-to-strong self | `guard let self = self else { return }` |
| Shorthand weak self | `guard let self else { return }` |
| Sibling scopes (no nesting) | `if a { let x = 1 }; if b { let x = 2 }` |
| Underscore placeholder | `let _ = foo(); if true { let _ = bar() }` |

### Violating Examples

**Error-level** (clear-cut shadowing):
```swift
func example() {
    let value = 10
    if someCondition {
        let value = 20  // error: shadows outer 'value' with unrelated value
        print(value)
    }
}

func process() {
    let count = items.count
    let closure = { (count: Int) in  // error: parameter shadows outer 'count'
        print(count)
    }
}
```

**Warning-level** (ambiguous — initializer references outer variable):
```swift
func prepare() {
    var config = loadConfig()
    if needsCleanup {
        let config = config.cleaned()  // warning: derives from outer 'config'
        apply(config)
    }
}

func process() {
    let data = fetchData()
    let closure = {
        let data = data.sorted()  // warning: derives from outer 'data'
        print(data)
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

func handle(response: Any) {
    let data = response
    if let data = data as? Data {  // conditional type cast, not flagged
        parse(data)
    }
}

class Controller {
    func loadData() {
        fetchAsync { [weak self] in
            guard let self = self else { return }  // weak-to-strong self, not flagged
            self.updateUI()
        }
    }
}
```

---
