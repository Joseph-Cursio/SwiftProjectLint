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

**The finding is gated on the view being able to trap at all.** The ordering is only dangerous for a view in this rule's precondition — one reading `@Environment(SomeType.self)`. Every other view inspects out-of-tree perfectly well, which is ViewInspector's ordinary mode of operation, so reporting the ordering alone means reporting an `error` against tests that pass and will keep passing. A project-wide pre-scan (`ObservableEnvironmentViewCollector`) catalogs the views that read the observable form, and a finding requires the test file to name one of them.

The catalog is optional, and the two empty states are not the same. An **empty** catalog means the project was scanned and has no such view, so the rule stays silent. A **`nil`** catalog means no pre-scan ran — a single-file invocation — and the rule keeps its ungated behaviour rather than going quiet where it has no way to know better.

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

### Known Limitations

- **The catalog match is per file, not per test.** The view under test is often built by a helper
  elsewhere in the same file, so its type name never appears in the test function — a function-scoped
  match would miss exactly the cases that matter. The cost is that a test file exercising both a
  trapping view and a safe one reports the safe test too.
- **A view reached only through an existential or a generic is invisible.** The gate matches
  identifier tokens, so a test that never names the concrete view type is not reported even when the
  view can trap.

---
