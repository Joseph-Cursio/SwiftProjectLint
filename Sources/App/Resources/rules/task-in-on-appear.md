[← Back to Rules](RULES.md)

## Task in onAppear

**Identifier:** `Task in onAppear`
**Category:** UI Patterns
**Severity:** Warning

### Rationale
Creating a `Task { }` or `Task.detached { }` inside `.onAppear { }` starts async work whose lifecycle is not tied to the view. If the view disappears before the task completes, the work continues running — wasting resources and potentially updating state on a view that no longer exists. The `.task { }` modifier automatically cancels the task when the view disappears.

### Discussion
`TaskInOnAppearVisitor` inspects `FunctionCallExprSyntax` nodes for `Task` or `Task.detached` calls, then walks up the parent chain to determine whether the call is inside an `.onAppear` closure. Function declaration boundaries stop the walk, so tasks created in helper methods called from `.onAppear` are not flagged.

The fix is straightforward — replace `.onAppear` + `Task` with the `.task` modifier:

```swift
// Before
.onAppear {
    Task {
        await loadData()
    }
}

// After
.task {
    await loadData()
}
```

### Non-Violating Examples
```swift
// .task modifier — cancels automatically
Text("Hello")
    .task {
        await loadData()
    }

// Task in a button action — intentional user-initiated work
Button("Refresh") {
    Task {
        await refresh()
    }
}

// Helper method called from onAppear — not flagged
.onAppear {
    startLoading()
}
```

### Violating Examples
```swift
// Task inside .onAppear — not cancelled when view disappears
Text("Hello")
    .onAppear {
        Task {
            await loadData()
        }
    }

// Task.detached inside .onAppear — same problem
Text("Hello")
    .onAppear {
        Task.detached {
            await doWork()
        }
    }
```

---
