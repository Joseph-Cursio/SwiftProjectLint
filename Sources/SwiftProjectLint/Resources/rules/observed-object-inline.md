[← Back to Rules](RULES.md)

## ObservedObject Inline

**Identifier:** `Observed Object Inline`
**Category:** State Management
**Severity:** Warning

### Rationale
`@ObservedObject` does not own the object it observes. When you initialize an object inline with `@ObservedObject var viewModel = ViewModel()`, the object is recreated every time the view re-renders. This leads to lost state and unexpected behavior. Use `@StateObject` instead when the view is responsible for creating the object.

### Discussion
`ObservedObjectInlineVisitor` detects `@ObservedObject` variable declarations that have an initializer. The presence of an initializer (`= SomeType()`) indicates the view is creating the object, which means `@StateObject` should be used instead. `@ObservedObject` is appropriate only when the object is passed in from a parent view.

```swift
// Before — object recreated on every re-render
struct MyView: View {
    @ObservedObject var viewModel = ViewModel()
}

// After — object properly owned by the view
struct MyView: View {
    @StateObject var viewModel = ViewModel()
}

// Also correct — object passed from parent
struct ChildView: View {
    @ObservedObject var viewModel: ViewModel
}
```

### Non-Violating Examples
```swift
// @ObservedObject without initializer — passed from parent
@ObservedObject var viewModel: ViewModel

// @StateObject with initializer — correctly owns the object
@StateObject var viewModel = ViewModel()

// @State — different property wrapper
@State var count = 0
```

### Violating Examples
```swift
// @ObservedObject with inline initialization
@ObservedObject var viewModel = ViewModel()
@ObservedObject var store = DataStore()
```

---
