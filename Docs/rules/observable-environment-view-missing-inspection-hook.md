[← Back to Rules](RULES.md)

## Observable Environment View Missing Inspection Hook

**Identifier:** `Observable Environment View Missing Inspection Hook`
**Category:** Testability
**Severity:** Info

### Rationale
`@Environment(SomeType.self)` — the `@Observable` form — has **no default value**. Read outside a hosted view hierarchy it traps in SwiftUICore's `EnvironmentValues.subscript.getter`, killing the test process rather than failing a single test.

The keypath form is not affected. `@Environment(\.someKey)` falls back to a default and merely logs *"Accessing Environment<X>'s value outside of being installed on a View"*. Only the `Type.self` form is fatal, and that distinction is the rule's entire discriminator.

A view reading the fatal form can only be inspected by hosting it and inspecting from inside the live render, which requires the view to carry an inspection relay. Without one, the view is untestable by ViewInspector — and the way you find out is a process-killing trap whose backtrace names neither ViewInspector nor the test that triggered it.

### Discussion
`ObservableEnvironmentViewMissingInspectionHookVisitor` reports a `struct` conforming to `View` that declares at least one `@Environment(SomeType.self)` property and no stored property named `inspection`. The message names each offending environment type.

This is **advisory**, not a defect: a view nobody inspects needs no hook, and adding one to every view would be noise. It is `Info` severity for that reason. The value is that it fires at the moment the view is written, rather than leaving the constraint to be discovered later from a crash log.

The relay is two lines, and deliberately lives in the app target so the app never links ViewInspector — the test target supplies the protocol conformance:

```swift
// App target
internal final class Inspection<V>: @unchecked Sendable {
    let notice = PassthroughSubject<UInt, Never>()
    var callbacks = [UInt: (V) -> Void]()
    func visit(_ view: V, _ line: UInt) {
        if let callback = callbacks.removeValue(forKey: line) { callback(view) }
    }
}

// Test target
extension Inspection: InspectionEmissary {}
```

```swift
// Before — cannot be inspected without trapping
struct ContentView: View {
    @Environment(VaultManager.self) private var vaultManager

    var body: some View {
        Text(vaultManager.title)
    }
}

// After — hosted inspection becomes possible
struct ContentView: View {
    @Environment(VaultManager.self) private var vaultManager
    internal let inspection = Inspection<Self>()

    var body: some View {
        Text(vaultManager.title)
            .onReceive(inspection.notice) { inspection.visit(self, $0) }
    }
}
```

### Non-Violating Examples
```swift
// The keypath form has a default; it warns rather than traps.
struct SettingsView: View {
    @Environment(\.dependencies) private var dependencies
    var body: some View { Text("x") }
}

// Already carries the relay.
struct HookedView: View {
    @Environment(VaultManager.self) private var vault
    internal let inspection = Inspection<Self>()
    var body: some View {
        Text(vault.title)
            .onReceive(inspection.notice) { inspection.visit(self, $0) }
    }
}

// Not a View.
struct Holder {
    @Environment(VaultManager.self) private var vault
}
```

### Companion
[ViewHosting Before Inspection](view-hosting-before-inspection.md) catches the same hazard from the *test* side.
