[<- Back to Rules](RULES.md)

## iOS 17 Observation Migration

**Identifier:** `iOS 17 Observation Migration`
**Category:** Modernization
**Severity:** Info *(opt-in)*

### Rationale
The `@Observable` macro (iOS 17+) replaces the `ObservableObject` protocol + `@Published` pattern with a simpler, more performant model. Views using `@Observable` objects get more granular update tracking — they only re-render when actually-read properties change, not when any `@Published` property changes.

### Discussion
`IOS17ObservationMigrationVisitor` identifies `ObservableObject` classes and provides a migration readiness score:
- **High readiness**: Only uses `@Published`, no manual `objectWillChange.send()`, no Combine publisher usage.
- **Medium readiness**: Uses `objectWillChange.send()` manually (needs removal during migration).
- **Low readiness**: No `@Published` properties (may be using `objectWillChange` for other purposes).

Classes that use Combine publisher features (`$property` projected values, `objectWillChange` chained with `.sink`/`.assign`) are suppressed since `@Observable` doesn't provide Combine publishers. NSObject subclasses are also suppressed since they can't use the `@Observable` macro.

This is an opt-in companion to the simpler `legacyObservableObject` rule, providing actionable migration prioritization.

### Non-Violating Examples
```swift
// Already using @Observable
@Observable
class ProfileViewModel {
    var name: String = ""
}

// Uses Combine publishers — suppressed
class StreamViewModel: ObservableObject {
    @Published var items: [Item] = []
    var cancellable: AnyCancellable?
    init() {
        cancellable = $items.debounce(for: .seconds(1), scheduler: RunLoop.main).sink { _ in }
    }
}

// NSObject subclass — suppressed
class LegacyModel: NSObject, ObservableObject {
    @Published var value: Int = 0
}
```

### Violating Examples
```swift
// High readiness — straightforward migration
class ProfileViewModel: ObservableObject {
    @Published var name: String = ""
    @Published var avatar: Image?
}

// Medium readiness — manual objectWillChange needs removal
class CounterViewModel: ObservableObject {
    @Published var count: Int = 0
    func increment() {
        objectWillChange.send()
        count += 1
    }
}
```

---
