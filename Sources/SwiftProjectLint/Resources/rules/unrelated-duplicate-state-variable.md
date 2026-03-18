[← Back to Rules](RULES.md)

## Unrelated Duplicate State Variable

**Identifier:** `Unrelated Duplicate State Variable`
**Category:** State Management
**Severity:** Info

### Rationale
When the same variable name appears in views that are unrelated in the hierarchy, it may indicate that the variable represents a shared concept that deserves a shared model. This rule nudges developers to evaluate whether a common `ObservableObject` would be clearer.

### Discussion
This is a softer signal than `relatedDuplicateStateVariable`. Unrelated views frequently have identically named local state variables without any problem — for example, `isLoading` is a common name used in many independently operating views. The info severity reflects this uncertainty: treat it as a prompt to evaluate, not a mandatory fix.

### Non-Violating Examples
```swift
// Two completely independent views with unrelated isLoading states — acceptable
struct FeedView: View {
    @State private var isLoading = false
    var body: some View { Text("Feed") }
}

struct ProfileView: View {
    @State private var isLoading = false
    var body: some View { Text("Profile") }
}
```

### Violating Examples
```swift
// Both views track "selectedItem" — may represent the same domain concept
struct ListingView: View {
    @State private var selectedItem: String? = nil
    var body: some View { Text("Listing") }
}

struct DetailView: View {
    @State private var selectedItem: String? = nil  // same concept in unrelated view
    var body: some View { Text("Detail") }
}
```

---
