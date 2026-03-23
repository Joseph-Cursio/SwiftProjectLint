[← Back to Rules](RULES.md)

## Fat View Detection

**Identifier:** `Fat View Detection`
**Category:** Architecture
**Severity:** Warning

### Rationale
This is the architecture-category counterpart to the state-management `fatView` rule. A SwiftUI view with more than five `@State` or `@StateObject` declarations has accumulated business logic that belongs in a ViewModel. The architecture perspective focuses on the separation-of-concerns violation.

### Discussion
`ArchitectureVisitor` counts `@State` and `@StateObject` properties within each view struct. After visiting the entire struct, if the count exceeds five, an issue is reported pointing to MVVM as the recommended pattern. Extracting state into a `ViewModel: ObservableObject` makes the view a pure render function of the model's published properties.

### Non-Violating Examples
```swift
struct ProfileView: View {
    @StateObject private var viewModel = ProfileViewModel()
    @State private var showingSheet = false

    var body: some View {
        Text(viewModel.name)
            .sheet(isPresented: $showingSheet) { EditView() }
    }
}
```

### Violating Examples
```swift
struct ProfileView: View {
    @State private var name = ""
    @State private var email = ""
    @State private var age = 0
    @StateObject private var imageLoader = ImageLoader()
    @State private var showingAlert = false
    @State private var errorMessage = ""  // sixth property — exceeds threshold

    var body: some View { Text(name) }
}
```

---
