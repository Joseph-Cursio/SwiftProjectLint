[← Back to Rules](RULES.md)

## Law of Demeter

**Identifier:** `Law of Demeter`
**Category:** Architecture
**Severity:** Warning

### Rationale
The Law of Demeter (also called the "principle of least knowledge") states that an object should only communicate with its immediate collaborators. A chain like `manager.service.data` requires the calling code to know about `manager`, about `manager`'s `service` property, and about `service`'s `data` property — three layers of internal structure that the caller should not be aware of.

### Discussion
`LawOfDemeterVisitor` detects three-level member access chains where the root is a plain identifier (not `self`, `super`, or a function call). Chains rooted at `self` are exempt because accessing `self.manager.service` is standard within a class's own implementation. Chains rooted at function calls — such as SwiftUI modifier chains like `Text("hi").frame(width: 100).background(.red)` — are also exempt because fluent APIs intentionally chain method calls.

The fix is to add a method on `manager` that encapsulates the `service.data` access, so callers need only know about `manager`.

### Non-Violating Examples
```swift
// Two-level chain — fine
class Owner {
    func run() { let _ = manager.data }
}

// self-chain — fine
class ViewModel {
    func run() { let _ = self.manager.service }
}

// SwiftUI modifier chain — fine
struct MyView: View {
    var body: some View {
        Text("hello").frame(width: 100).background(.red)
    }
}
```

### Violating Examples
```swift
// Three-level chain — Law of Demeter violation
class Owner {
    func run() { let _ = manager.service.data }
}

class Display {
    let user = User()
    func show() -> String { return user.profile.address }  // three-level chain
}
```

---
