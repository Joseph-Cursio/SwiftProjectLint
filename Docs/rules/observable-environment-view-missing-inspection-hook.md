[← Back to Rules](RULES.md)

## Observable Environment View Missing Inspection Hook

**Identifier:** `Observable Environment View Missing Inspection Hook`
**Category:** Testability
**Severity:** Info

### Rationale

**Run this rule and you find out at lint time what would otherwise be a runtime trap during testing.**

`@Environment(SomeType.self)` — the `@Observable` form — has **no default value**. Read outside a hosted view hierarchy it does not fail gracefully: it traps in SwiftUICore's `EnvironmentValues.subscript.getter` and kills the test process, so every suite scheduled alongside it is reported failed. With parallel execution that is a different set each run, and the backtrace names neither ViewInspector nor the test that triggered it.

The keypath form is not affected. `@Environment(\.someKey)` falls back to a default and merely logs *"Accessing Environment<X>'s value outside of being installed on a View"*. Only the `Type.self` form is fatal, and that distinction is the rule's entire discriminator.

A view reading the fatal form can only be inspected by hosting it and inspecting from inside the live render, which requires the view to carry an inspection relay. That is still true of current ViewInspector, including its `@Observable` environment injection — the visitor's doc comment records the measurement, because the natural assumption is that the library has since fixed it.

### Discussion

`ObservableEnvironmentViewMissingInspectionHookVisitor` reports a `struct` conforming to `View` that declares at least one `@Environment(SomeType.self)` property and no stored property named `inspection`. The message names each offending environment type.

**It fires only for a view something is actually trying to inspect** — one named from a file that imports ViewInspector. This is advisory rather than a defect: a view nobody inspects needs no hook, and asking every view for one is noise. `Info` severity for that reason.

Both authoring orders work, so there is no chicken-and-egg. Write the naive `MyView().inspect()` test and it compiles, traps at runtime, and the rule fires on the view; write the relay-style test first and the file does not compile — and the rule still fires, because the linter parses rather than builds. You do not need the relay in place for the rule to tell you to add it.

### The fix

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

### Known limitations

The catalog behind the gate is name-keyed and deliberately over-collects: every capitalised identifier in a ViewInspector-importing file counts. A view sharing a name with something merely mentioned in such a file will be reported. That is the safe direction — over-collecting costs a finding you dismiss, under-collecting costs a test process.

### Companion
[ViewHosting Before Inspection](view-hosting-before-inspection.md) catches the same hazard from the *test* side, and consumes the sibling prescan `ObservableEnvironmentViewCollector` as its own precondition — the two rules ask "can this view trap?" and "is anyone about to make it?" from opposite ends.
