[← Back to Rules](RULES.md)

## Observable Environment View Missing Inspection Hook

**Identifier:** `Observable Environment View Missing Inspection Hook`
**Category:** Testability
**Severity:** Info

### Rationale
`@Environment(SomeType.self)` — the `@Observable` form — has **no default value**. Read outside a hosted view hierarchy it traps in SwiftUICore's `EnvironmentValues.subscript.getter`, killing the test process rather than failing a single test.

The keypath form is not affected. `@Environment(\.someKey)` falls back to a default and merely logs *"Accessing Environment<X>'s value outside of being installed on a View"*. Only the `Type.self` form is fatal, and that distinction is the rule's entire discriminator.

A view reading the fatal form can only be inspected by hosting it and inspecting from inside the live render, which requires the view to carry an inspection relay. Without one, the view is untestable by ViewInspector — and the way you find out is a process-killing trap whose backtrace names neither ViewInspector nor the test that triggered it.

**That claim was re-measured against the pinned ViewInspector revision, because it had a plausible expiry date.** ViewInspector gained `@Observable` environment injection (`EnvironmentInjection.environmentKeyPaths(for:)`), and its own suite inspects such a view with `sut.environment(obj).inspect()` and no relay at all — so the rule looked obsolete. It is not. Three attempts against the revision this project pins, each killing the test process:

| Attempt | Result |
| --- | --- |
| `SubjectView().inspect()` | trap |
| `SubjectView().environment(store).inspect()` | trap |
| `VStack { SubjectView() }.environment(store).inspect()` | trap |

ViewInspector's passing case differs in a way that matters: its `ObservableOptionalView` declares the environment as **optional** (`… private var obj1: TestObservableObject1?`), which returns `nil` rather than trapping, and its `ObservableOuterView` reads the objects in a *child* rather than in its own body. Neither is the shape this rule reports. The hazard is real and current.

### Discussion
`ObservableEnvironmentViewMissingInspectionHookVisitor` reports a `struct` conforming to `View` that declares at least one `@Environment(SomeType.self)` property and no stored property named `inspection`. The message names each offending environment type.

This is **advisory**, not a defect: a view nobody inspects needs no hook, and adding one to every view would be noise. It is `Info` severity for that reason.

**The rule now implements that sentence, having stated it for several runs without doing so.** A finding requires the view to be *named from a file that imports ViewInspector*, which is the project-wide answer to "is anybody trying to inspect this?"

The measurement that prompted it: across seven repositories the rule reported **58 findings, and not one of the 58 views was named from a ViewInspector-importing file**. Nor did any of them carry the relay. The rule was asking fifty-eight views to add production code for tests that did not exist.

What the corpus *does* contain is one repository that took the advice, and it is the argument for keeping the rule rather than deleting it. SwiftMarkdownWiki's `ContentView` and `EditorView` carry the relay and are genuinely inspected through it (`sut.inspection.inspect { … }`), and its vendored `Inspection.swift` records why the type lives in the app target. **The advice works end to end; it was taken exactly where someone wanted the test.** Which is also when the gated rule fires.

The gate does not trade the "fires early" property away. A developer writing `import ViewInspector` and naming the view gets the finding *before the test is ever run* — earlier than the trap, not later.

**Do not answer this question with `grep`.** Asked that way over this corpus it reports four inspected views. Three are a doc comment listing views the file does not touch, and the fourth is a comment recording that the author hit the trap and chose to stop descending. `InspectedTypeNameCollector` walks syntax, so it sees none of them, and there is a test pinning exactly that.

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

The catalog is **name-keyed and deliberately over-collects**: every capitalised identifier in a ViewInspector-importing file counts, not only views and not only ones under inspection. A view sharing a name with something merely mentioned in such a file will be reported. That is the safe direction — the cost of collecting too much is a finding that still reports, and the cost of collecting too little is a view that takes a test process down with no warning.

### Companion
[ViewHosting Before Inspection](view-hosting-before-inspection.md) catches the same hazard from the *test* side, and consumes the sibling prescan `ObservableEnvironmentViewCollector` as its own precondition — the two rules ask "can this view trap?" and "is anyone about to make it?" from opposite ends.

### A note on wiring

This gate shipped dead the first time. Seven of the eight hops that carry a prescan from `ProjectLinter` to a visitor were done, the eighth was a `det.known… =` assignment whose parameter had a `nil` default, and so the package built, 3,537 tests passed, and the corpus count did not move by one. The visitor was correct in isolation the whole time.

`ProjectLinterTests.testInspectionHookGateReachesTheVisitorEndToEnd` exists for that reason and no other: it drives the real linter over a two-view fixture and fails if the catalog does not arrive. Verified by removing the eighth hop again and watching it fail. **A unit test on the visitor cannot catch this class of bug, and this project has now shipped it twice.**
