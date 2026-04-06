[<- Back to Rules](RULES.md)

## Legacy Closure Syntax

**Identifier:** `Legacy Closure Syntax`
**Category:** Modernization
**Severity:** Info *(opt-in)*

### Rationale
Explicitly typing closure parameters when the types can be inferred adds noise without improving clarity. Swift's type inference handles closure parameter types in most contexts, especially standard library higher-order functions.

### Discussion
`LegacyClosureSyntaxVisitor` detects closures with explicit type annotations on parameters when used as trailing closures or arguments to known inferrable functions (`.map`, `.filter`, `.reduce`, `.sorted`, etc.). Closures with more than 10 statements are suppressed since explicit types aid readability in long closures.

This rule is opt-in because some teams prefer explicit closure types for documentation purposes.

### Non-Violating Examples
```swift
// Inferred types — clean
let names = users.map { user in user.name }
let adults = users.filter { $0.age >= 18 }

// Simple input without types
let sorted = items.sorted { lhs, rhs in lhs.date < rhs.date }

// Long closure — explicit types aid readability (suppressed)
let result = items.reduce(into: [:]) { (result: inout [String: Int], item: Item) in
    // ... many lines of processing
}
```

### Violating Examples
```swift
// Redundant type annotations in inferrable context
let names = users.map { (user: User) -> String in
    return user.name
}

let adults = users.filter { (user: User) -> Bool in
    user.age >= 18
}
```

---
