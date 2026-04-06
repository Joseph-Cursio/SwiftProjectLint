[← Back to Rules](RULES.md)

## Variable Shadowing

**Identifier:** `Variable Shadowing`
**Category:** Code Quality
**Severity:** Error

### Rationale
When an inner scope declares a variable with the same name as one in an outer scope, the outer variable becomes inaccessible within that scope. This can cause subtle bugs, especially inside closures where the captured value may not be what the developer expects.

### Discussion
`VariableShadowingVisitor` maintains a scope stack that tracks variable names across nested scopes. Each scope frame is tagged with a kind (`typeMember`, `codeBlock`, `closure`, or `forLoop`) so the visitor can distinguish between scope types. When a new declaration reuses a name from an outer scope, the rule flags it as a potential source of confusion.

The visitor pushes a new scope frame on entering `MemberBlockSyntax` (type bodies), `CodeBlockSyntax`, `ClosureExprSyntax`, and `ForStmtSyntax` nodes, and pops the frame on exit. Variable declarations, function parameters, and for-loop binding patterns are checked against outer scope frames. Closure parameters are registered in their scope but not checked for shadows.

**Idiomatic type-narrowing patterns are excluded.** The visitor recognises several Swift patterns where shadowing is intentional and expected:

- **Optional binding** — `if let x = x` / `guard let x = x`, and the Swift 5.7+ shorthand `if let x` / `guard let x`. These intentionally shadow an optional with its unwrapped value.
- **Conditional type cast binding** — `if let x = x as? T` / `guard let x = x as? T`. These narrow a value to a more specific type within a scope, analogous to optional unwrapping.
- **Weak-to-strong self capture** — `guard let self = self` / `guard let self` inside `[weak self]` closures. This is the standard pattern for promoting a weak reference to a strong one.

The visitor detects these by walking up to `OptionalBindingConditionSyntax` and checking whether the bound name matches the initializer expression directly, via a conditional `as?` cast, or has no initializer (shorthand form).

**Closure parameters are excluded.** Closures create their own scope, and reusing names from an outer scope is idiomatic Swift. Patterns like `mutex.withLock { value in }`, `array.map { item in }`, and `collection.contains { record in }` intentionally shadow outer variables. Closure parameters are registered in the scope stack (so declarations inside the closure body can shadow-check against them) but the parameters themselves are never flagged.

**Rebinding transforms are excluded.** When the initializer references the same-named outer variable — such as `let config = config.cleaned()`, `let items = items.sorted()`, or `let data = transform(data)` — the developer clearly knows about the outer variable and is intentionally deriving a new value from it. These are skipped entirely.

**Locals matching type properties are excluded.** The visitor tracks type-member scopes (`MemberBlockSyntax`) separately from code-block scopes. Variables declared at type level (stored properties) are placed in a `typeMember` scope frame, which is skipped during shadow checks. This means `let configuration = self.configuration` inside a method body is not flagged — Swift uses `self.` for disambiguation, making this safe by design. Function and init parameters matching property names are also excluded by the same mechanism.

**For-loop iteration variables are excluded from shadow checks.** Variables in a for-loop scope frame (the iteration variable itself) are skipped when checking for shadows. Reusing iteration variable names in nested loops (e.g., `for i in outer { for i in inner { } }`) is common and the inner variable naturally supersedes the outer within its scope.

### Flagged (Error)

| Context | Example |
|---------|---------|
| Nested block re-declaration | `let x = 1; if true { let x = 2 }` |
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
| Conditional type cast | `if let x = x as? Int { ... }` |
| Guard type cast | `guard let x = x as? String else { return }` |
| Weak-to-strong self | `guard let self = self else { return }` |
| Shorthand weak self | `guard let self else { return }` |
| Sibling scopes (no nesting) | `if a { let x = 1 }; if b { let x = 2 }` |
| Underscore placeholder | `let _ = foo(); if true { let _ = bar() }` |
| Function param matching type property | `struct S { var name: String; init(name: String) { ... } }` |
| Method param matching type property | `class C { var config: Config; func update(config: Config) { ... } }` |
| Closure parameter | `let x = 1; items.map { x in ... }` |
| withLock closure parameter | `mutex.withLock { value in ... }` |
| Rebinding with transform | `let config = config.cleaned()` |
| Rebinding with function | `let data = transform(data)` |
| Local matching stored property | `struct S { var x: Int; func f() { let x = self.x } }` |
| Codable init locals | `init(from:) { let name = container.decode(...) }` |
| Nested for-loop iteration variable | `for i in a { for i in b { ... } }` |
| Variable shadowing for-loop variable | `for i in a { let i = i + 1 }` |

### Violating Examples

```swift
func example() {
    let value = 10
    if someCondition {
        let value = 20  // error: shadows outer 'value' with unrelated value
        print(value)
    }
}

func outer() {
    let name = "hello"
    func inner(name: String) {  // error: parameter shadows outer 'name'
        print(name)
    }
}
```

### Non-Violating Examples
```swift
// Idiomatic optional unwrapping — not flagged
func example() {
    let name: String? = fetchName()
    guard let name else { return }
    print(name)
}

// Conditional type cast — not flagged
func handle(response: Any) {
    let data = response
    if let data = data as? Data {
        parse(data)
    }
}

// Weak-to-strong self — not flagged
class Controller {
    func loadData() {
        fetchAsync { [weak self] in
            guard let self = self else { return }
            self.updateUI()
        }
    }
}

// Closure parameters — not flagged
func process() {
    let counter = Mutex(0)
    counter.withLock { counter in
        counter += 1
    }

    let items = [3, 1, 2]
    items.forEach { items in
        print(items)
    }
}

// Rebinding transforms — not flagged
func prepare() {
    var config = loadConfig()
    if needsCleanup {
        let config = config.cleaned()
        apply(config)
    }
}

// Locals matching stored properties — not flagged
struct Runner {
    var configuration: Configuration
    func run() {
        let configuration = self.configuration.withDefaults()
        execute(configuration)
    }
}

// Codable init locals matching properties — not flagged
struct Location {
    let fileID: String
    let line: Int
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fileID = try container.decode(String.self, forKey: .fileID)
        let line = try container.decode(Int.self, forKey: .line)
        self.init(fileID: fileID, line: line)
    }
}

// Function/init parameters matching type properties — not flagged
struct ViewModel {
    let name: String
    let count: Int
    init(name: String, count: Int) {
        self.name = name
        self.count = count
    }
}

// Nested for-loop iteration variables — not flagged
func buildMatrix() {
    for index in 0..<5 {
        for index in 0..<3 {
            print(index)
        }
    }
}
```

---
