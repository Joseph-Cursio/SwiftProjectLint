[← Back to Rules](RULES.md)

## Animation Without State Change

**Identifier:** `Animation Without State Change`
**Category:** Animation
**Severity:** Info

### Rationale
A `withAnimation` block that contains no state mutations — no assignments, no compound-assignment operators, no `.toggle()` calls — produces no visual change. The animation wrapper wraps nothing and is dead code.

### Discussion
`WithAnimationVisitor` delegates to a `StateMutationChecker` sub-visitor that walks the closure body looking for `AssignmentExprSyntax`, compound binary operators (`+=`, `-=`, etc.), and zero-argument `.toggle()` calls. If none are found, the block is flagged. The info severity acknowledges that this may be a work in progress during development. An empty `withAnimation { }` block is the clearest trigger.

### Non-Violating Examples
```swift
struct MyView: View {
    @State private var isVisible = false

    var body: some View {
        Button("Toggle") {
            withAnimation {
                isVisible = true   // state mutation present — no issue
            }
        }
    }
}

struct CounterView: View {
    @State private var count = 0

    var body: some View {
        Button("Increment") {
            withAnimation {
                count += 1  // compound assignment counts as mutation
            }
        }
    }
}
```

### Violating Examples
```swift
struct MyView: View {
    var body: some View {
        Button("Tap") {
            withAnimation {
                print("hello")  // no state mutation inside withAnimation
            }
        }
    }
}

struct EmptyView: View {
    var body: some View {
        Button("Tap") {
            withAnimation { }  // completely empty
        }
    }
}
```

---
