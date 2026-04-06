[<- Back to Rules](RULES.md)

## GeometryReader Overuse

**Identifier:** `GeometryReader Overuse`
**Category:** Performance
**Severity:** Info *(opt-in)*

### Rationale
`GeometryReader` is a sledgehammer — it eagerly consumes all available space and passes geometry to a closure, making the layout inflexible. iOS 17 introduced `containerRelativeFrame()` for proportional sizing and `visualEffect()` for geometry-dependent effects, both of which are more composable and don't disrupt the surrounding layout.

### Discussion
`GeometryReaderOveruseVisitor` flags all `GeometryReader` instantiations. Since `GeometryReader` is sometimes legitimately necessary (e.g. reading size for a custom layout, or complex scroll effects that `visualEffect` can't express), this rule is disabled by default and must be explicitly enabled in `.swiftprojectlint.yml`.

Note: `containerRelativeFrame()` and `visualEffect()` require iOS 17+ / macOS 14+.

### Non-Violating Examples
```swift
// Modern proportional sizing (iOS 17+)
Text("Hello")
    .containerRelativeFrame(.horizontal) { length, _ in
        length * 0.8
    }

// Geometry-dependent effect (iOS 17+)
Text("Hello")
    .visualEffect { content, proxy in
        content.offset(y: proxy.frame(in: .global).minY)
    }
```

### Violating Examples
```swift
// GeometryReader for simple proportional sizing
GeometryReader { geometry in
    Text("Hello")
        .frame(width: geometry.size.width * 0.8)
}

// GeometryReader for scroll-dependent effect
GeometryReader { proxy in
    Color.blue
        .opacity(proxy.frame(in: .global).minY / 500)
}
```

---
