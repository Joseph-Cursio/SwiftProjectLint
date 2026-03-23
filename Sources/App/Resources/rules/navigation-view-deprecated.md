[← Back to Rules](RULES.md)

## NavigationView Deprecated

**Identifier:** `Navigation View Deprecated`
**Category:** Modernization
**Severity:** Warning

### Rationale
`NavigationView` was deprecated in iOS 16. Apple introduced `NavigationStack` for single-column navigation and `NavigationSplitView` for multi-column navigation as replacements. The new APIs provide better control over navigation state and support programmatic navigation via `NavigationPath`.

### Discussion
`NavigationViewDeprecatedVisitor` detects `NavigationView { }` calls. These should be replaced with the appropriate modern alternative depending on your navigation needs.

```swift
// Before
NavigationView {
    List {
        NavigationLink("Detail", destination: DetailView())
    }
}

// After — single column
NavigationStack {
    List {
        NavigationLink("Detail", value: item)
    }
    .navigationDestination(for: Item.self) { item in
        DetailView(item: item)
    }
}

// After — multi-column (sidebar + detail)
NavigationSplitView {
    List(selection: $selected) {
        ForEach(items) { item in
            Text(item.name)
        }
    }
} detail: {
    DetailView(item: selected)
}
```

### Non-Violating Examples
```swift
// NavigationStack — modern replacement
NavigationStack {
    Text("Hello")
}

// NavigationSplitView — modern replacement
NavigationSplitView {
    SidebarView()
} detail: {
    DetailView()
}
```

### Violating Examples
```swift
// NavigationView — deprecated in iOS 16
NavigationView {
    Text("Hello")
}

NavigationView {
    List {
        Text("Item 1")
        Text("Item 2")
    }
}
```

---
