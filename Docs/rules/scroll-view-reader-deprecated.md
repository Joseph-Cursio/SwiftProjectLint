[← Back to Rules](RULES.md)

## ScrollViewReader Deprecated

**Identifier:** `ScrollViewReader Deprecated`
**Category:** Modernization
**Severity:** Info

### Rationale
`ScrollViewReader` and the imperative `ScrollViewProxy.scrollTo(_:anchor:)` were the only way to programmatically control scroll position before iOS 17. The modern replacement uses `.scrollPosition(id:)` with a `@State` binding, which is declarative, eliminates the proxy indirection, and integrates naturally with SwiftUI's state-driven update model.

### Discussion
`ScrollViewReaderDeprecatedVisitor` detects `ScrollViewReader { }` usage. Consider migrating to the iOS 17 `scrollPosition(id:)` API.

```swift
// Before
ScrollViewReader { proxy in
    ScrollView {
        ForEach(messages) { message in
            MessageRow(message)
                .id(message.id)
        }
    }
    .onChange(of: messages) { _, _ in
        proxy.scrollTo(messages.last?.id, anchor: .bottom)
    }
}

// After — iOS 17
@State private var scrollPosition: MessageID?

ScrollView {
    ForEach(messages) { message in
        MessageRow(message)
            .id(message.id)
    }
}
.scrollPosition(id: $scrollPosition)
.onChange(of: messages) { _, _ in
    scrollPosition = messages.last?.id
}
```

### Non-Violating Examples
```swift
ScrollView {
    ForEach(items) { item in Text(item.name) }
}
.scrollPosition(id: $selectedID)
```

### Violating Examples
```swift
ScrollViewReader { proxy in
    ScrollView {
        ForEach(items) { item in Text(item.name).id(item.id) }
    }
}
```

---
