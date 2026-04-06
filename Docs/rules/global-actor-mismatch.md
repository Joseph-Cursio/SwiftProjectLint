[<- Back to Rules](RULES.md)

## Global Actor Mismatch

**Identifier:** `Global Actor Mismatch`
**Category:** Code Quality
**Severity:** Warning

### Rationale
When a function isolated to one global actor calls a function isolated to a different global actor (or no actor) without `await`, it causes a compiler error under strict concurrency. But in Swift 5 mode with `@preconcurrency`, these can be silent. Detecting them early surfaces migration issues before turning on strict concurrency.

### Discussion
`GlobalActorMismatchVisitor` tracks global actor annotations (`@MainActor` and custom `@globalActor` types) on types, functions, and variable type annotations within the same file. It flags calls that appear to cross actor boundaries without `await`.

This is a heuristic rule — without full type information it cannot replicate the compiler's isolation checking. It focuses on obvious cases:
- Static method calls on `@MainActor` types from non-isolated contexts
- Instance method calls on variables with known actor-annotated type annotations
- Direct calls to explicitly actor-annotated free functions from a different context

### Non-Violating Examples
```swift
@MainActor
class ViewModel {
    func updateUI() { }
}

// Properly awaited
func processData(viewModel: ViewModel) async {
    await viewModel.updateUI()
}

// Same actor context
@MainActor
func refreshUI(viewModel: ViewModel) {
    viewModel.updateUI()
}
```

### Violating Examples
```swift
@MainActor
class ViewModel {
    func updateUI() { }
}

// Missing await — crosses actor boundary
func processData(viewModel: ViewModel) {
    viewModel.updateUI()
}

// Static call across actor boundary
func doWork() {
    ViewModel.shared.refresh()
}
```

---
