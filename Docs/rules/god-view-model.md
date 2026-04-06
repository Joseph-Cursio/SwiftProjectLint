[<- Back to Rules](RULES.md)

## God View Model

**Identifier:** `God View Model`
**Category:** Architecture
**Severity:** Warning

### Rationale
View models with many `@Published` properties become god objects — they manage too much state, are hard to test, and couple unrelated concerns. This is the MVVM equivalent of the `fatView` rule. When a view model exceeds 10 published properties, it's a strong signal that it should be split into focused sub-view-models.

### Discussion
`GodViewModelVisitor` checks two patterns:
1. Classes conforming to `ObservableObject` — counts `@Published` properties (threshold: 10)
2. Classes annotated with `@Observable` — counts stored `var` properties (threshold: 15, higher because the macro encourages more granular observation)

Computed properties are excluded from the count.

### Non-Violating Examples
```swift
// Under threshold
class AuthViewModel: ObservableObject {
    @Published var email: String = ""
    @Published var password: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
}

// @Observable with reasonable property count
@Observable
class SettingsModel {
    var theme: Theme = .system
    var fontSize: Int = 14
    var showNotifications: Bool = true
}
```

### Violating Examples
```swift
// 12 @Published properties — god object
class AppViewModel: ObservableObject {
    @Published var userName: String = ""
    @Published var email: String = ""
    @Published var isLoggedIn: Bool = false
    @Published var items: [Item] = []
    @Published var selectedItem: Item?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var searchText: String = ""
    @Published var filterOption: FilterOption = .all
    @Published var sortOrder: SortOrder = .dateDesc
    @Published var showSettings: Bool = false
    @Published var notificationCount: Int = 0
}
```

---
