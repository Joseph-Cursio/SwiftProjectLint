[← Back to Rules](RULES.md)

## ViewHosting Before Inspection

**Identifier:** `ViewHosting Before Inspection`
**Category:** Testability
**Severity:** Error

### Rationale
ViewInspector evaluates a view's `body` *outside* SwiftUI unless the view is hosted and the inspection runs from inside that live render. For a view reading `@Environment(SomeType.self)` — the `@Observable` form, which has **no default value** — out-of-tree evaluation does not fail. It **traps**, inside SwiftUICore's `EnvironmentValues.subscript.getter`.

A trap is not a test failure. It kills the test process, so every test scheduled alongside it is reported failed at **0.000 seconds with no assertion message**, and the set differs run to run because scheduling is nondeterministic. The reported crash site names neither ViewInspector nor the offending test, so the visible symptom is a large, shifting set of unrelated suites failing for no stated reason.

Hosting *before* inspecting does not help: the inspection still evaluates the body out-of-tree. The ordering has to be inverted — register the inspection, then let hosting drive it.

### Discussion
Measured on macOS 27 against a minimal reproduction of [nalexn/ViewInspector#329](https://github.com/nalexn/ViewInspector/issues/329):

| shape | result |
|---|---|
| `.environment(obj)` then `.inspect()` | traps |
| `.environment(obj)`, `ViewHosting.host(…)`, then `.inspect()` | traps |
| inspection registered, then hosted | **passes** |

Only the last works, and it is what ViewInspector's maintainer prescribed when closing that issue: *"hosting the view should be the last step, after you setup the inspection."*

`ViewHostingBeforeInspectionVisitor` walks each `FunctionDeclSyntax` body and compares **sibling** statements only. If a single statement contains both the hosting call and an inspection call, the inspection is nested inside the hosting closure — the correct async shape — and nothing is reported. A violation requires the two calls to be in *different* top-level statements with the hosting first.

That sibling restriction is the whole difficulty of the rule. The correct async form places `ViewHosting.host` textually first, so a naive position comparison flags working code.

```swift
// Before — hosted, then inspected: traps and takes the process with it
func testContent() throws {
    let view = ContentView().environment(VaultManager())
    ViewHosting.host(view: view)
    _ = try view.inspect().find(NoteListView.self)
}

// After — the inspection is nested inside the hosting scope
func testContent() async throws {
    let sut = ContentView()
    try await ViewHosting.host(sut.environment(VaultManager())) {
        try await sut.inspection.inspect { view in
            _ = try view.find(NoteListView.self)
        }
    }
}
```

### Non-Violating Examples
```swift
// XCTest shape: the inspection is registered first, hosting drives it.
func testContent() throws {
    let sut = ContentView()
    let exp = sut.inspection.inspect { view in
        _ = try view.find(NoteListView.self)
    }
    ViewHosting.host(view: sut.environmentObject(model))
    wait(for: [exp], timeout: 0.1)
}

// Inspection with no hosting — a different question, not this rule's.
func testPlain() throws {
    _ = try PlainView().inspect().find(ViewType.Text.self)
}

// An unrelated `.host` member call is not ViewHosting.
func testServer() throws {
    server.host(view: thing)
    _ = try view.inspect()
}
```

### Companion
[Observable Environment View Missing Inspection Hook](observable-environment-view-missing-inspection-hook.md) catches the same hazard from the *view* side, before any test is written.
