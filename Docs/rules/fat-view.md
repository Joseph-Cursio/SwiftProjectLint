[← Back to Rules](RULES.md)

## Fat View

**Identifier:** `Fat View`
**Category:** State Management
**Severity:** Warning

### Rationale
A view with more than five `@State` or `@StateObject` properties is doing too much work. It is managing business logic and data transformation that should live in a ViewModel. This makes the view hard to test, hard to read, and fragile when requirements change.

### Discussion
The threshold of five state variables is intentionally conservative. Even moderate views rarely need more than a few pieces of local UI state (e.g., a `showingAlert: Bool`, a `selectedTab: Int`). When variables represent business data — user profiles, fetched lists, computed properties — they belong in an `ObservableObject`. Note that this rule uses the `ArchitectureVisitor` but is categorized under state management because the root cause is state accumulation.

### Non-Violating Examples
```swift
struct ProfileView: View {
    @StateObject private var viewModel = ProfileViewModel()
    @State private var showingEditSheet = false
    var body: some View {
        Text(viewModel.name)
    }
}
```

### Violating Examples
```swift
struct ProfileView: View {
    @State private var name = ""
    @State private var email = ""
    @State private var age = 0
    @State private var isLoading = false
    @State private var showingAlert = false
    @State private var errorMessage = ""  // exceeds the 5-variable threshold
    var body: some View { Text(name) }
}
```

---
