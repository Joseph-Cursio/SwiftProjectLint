[← Back to Rules](RULES.md)

## Missing StateObject

**Identifier:** `Missing StateObject`
**Category:** State Management
**Severity:** Warning

### Rationale
An `@ObservedObject` that the view's own initializer constructs. `@ObservedObject` says the object belongs to someone else, so SwiftUI does not keep it. A view struct is rebuilt every time its parent's `body` runs, and its initializer runs again with it. An initializer that builds the object therefore builds a new one on every parent update, and the old object's state is lost. Declare it `@StateObject`, which keeps one object for the view's lifetime, or pass the object in from the parent.

### Discussion
`MissingStateObjectVisitor` checks each `View` struct's `@ObservedObject` properties that have no inline value, and reports one that any of the view's initializers assigns a newly constructed object. It reports at the property's declaration.

What counts as constructing:
- `self.model = Model(…)` or `model = Model(…)`, also written `Model.init(…)` or `Model<T>(…)`;
- `_model = ObservedObject(wrappedValue: Model(…))`, or the older `initialValue:` label.

A capitalized callee is read as a type, so the check is syntactic. These are not construction, and are not reported:
- assigning a parameter (`self.model = model`), the object passed in, which is what `@ObservedObject` is for;
- a shared instance (`Model.shared`) or a factory's result (`makeModel()`);
- `init() { self.init(model: Model()) }`: the delegating call is not followed, which makes the rule quieter rather than louder.

**The inline form belongs to another rule.** `@ObservedObject var model = Model()` is [ObservedObject Inline](observed-object-inline.md)'s, so a property with an inline value is never reported by this rule as well.

### Non-Violating Examples
```swift
// The view owns the object: @StateObject, built once for the view's lifetime
struct CounterView: View {
    @StateObject private var model: CounterModel
    init(start: Int) { _model = StateObject(wrappedValue: CounterModel(start: start)) }
    var body: some View { Text("\(model.count)") }
}

// The object is passed in: @ObservedObject is right
struct CounterRow: View {
    @ObservedObject var model: CounterModel
    init(model: CounterModel) { self.model = model }
    var body: some View { Text("\(model.count)") }
}
```

### Violating Examples
```swift
struct CounterView: View {
    @ObservedObject var model: CounterModel   // reported here
    init(start: Int) {
        self.model = CounterModel(start: start)  // a new model on every parent update
    }
    var body: some View { Text("\(model.count)") }
}
```

---
