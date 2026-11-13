[← Back to Rules](RULES.md)

## Unused State Variable

**Identifier:** `Unused State Variable`
**Category:** State Management
**Severity:** Warning

### Rationale
A `private` or `fileprivate` `@State` whose name appears nowhere else in its file is never read or written. SwiftUI still allocates and tracks storage for it, and a reader has to work out that it does nothing. Remove it, or use it.

### Discussion
`UnusedStateVariableVisitor` counts names over the file's tokens. A property is used when its name appears anywhere besides its own declaration: as `x`, as the projected binding `$x`, or as the storage `_x` an initializer assigns. Key paths (`\.x`), string interpolations and same-file extensions all count, and a backticked name matches without its backticks.

**Why only `private` and `fileprivate`.** Nothing outside the file can reach a member with those access levels, extensions in other files included. So a name the file never mentions is a name nothing mentions, and the check needs no other file. An `internal` or `public` property, or one that is only `private(set)`, could be read elsewhere, so it is skipped.

**The count is deliberately generous.** A local variable, a parameter or another type's member with the same name also counts as a use. That can hide a real unused property, but a property whose name appears in the file's source is never reported. Access the source does not spell out is not seen: `Mirror` reflection, or code a macro generates.

**Why not `@StateObject`.** Holding one does work without naming it. SwiftUI keeps the object alive for the view's lifetime and re-renders the view whenever it publishes a change, so a clock or a subscription can depend on a `@StateObject` nobody names. Removing it would change behaviour, so it is never reported. A `@State` nobody names can never change, so it cannot affect anything.

The issue is reported on the first line of the declaration, where its attribute is.

Related: [Unnecessary View Update](unnecessary-view-update.md) reports a `@State` that is written through `self.` but never read through `self.` in the body. This rule reports one that is never named at all.

### Non-Violating Examples
```swift
struct CounterView: View {
    @State private var count = 0
    var body: some View {
        Button("Tap") { count += 1 }
        Text("\(count)")
    }
}

// Named only through its binding or its storage: still used
struct FormView: View {
    @State private var name: String
    init(name: String) { _name = State(initialValue: name) }
    var body: some View { TextField("Name", text: $name) }
}

// Not private: another file could read it, so it is not reported
struct SettingsView: View {
    @State var showAdvanced = false
    var body: some View { Text("Settings") }
}
```

### Violating Examples
```swift
struct MyView: View {
    @State private var count = 0   // never named again
    @State private var name = ""   // never named again
    var body: some View {
        Text("Hello")
    }
}
```

---
