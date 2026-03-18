[← Back to Rules](RULES.md)

## matchedGeometryEffect Misuse

**Identifier:** `matchedGeometryEffect Misuse`
**Category:** Animation
**Severity:** Warning

### Rationale
`matchedGeometryEffect` requires two things to work correctly: the namespace passed to `in:` must be declared with `@Namespace` in the same view struct, and each `id:` value must be unique within its namespace. Violating either requirement produces undefined layout behavior or crash-level assertion failures at runtime.

### Discussion
`MatchedGeometryVisitor` collects all `@Namespace` variable declarations during its first pass, then checks every `.matchedGeometryEffect(id:in:)` call. If the `in:` argument references a name not in the collected set, it fires the "undeclared namespace" variant. If the same `id:` value is encountered a second time for the same namespace, it fires the "duplicate ID" variant.

### Non-Violating Examples
```swift
struct HeroView: View {
    @Namespace private var ns

    var body: some View {
        VStack {
            Text("Source")
                .matchedGeometryEffect(id: "source", in: ns)
            Text("Destination")
                .matchedGeometryEffect(id: "destination", in: ns)  // unique id
        }
    }
}
```

### Violating Examples
```swift
// Undeclared namespace
struct HeroView: View {
    var body: some View {
        Text("Hero")
            .matchedGeometryEffect(id: "hero", in: undeclaredNS)  // namespace not @Namespace
    }
}

// Duplicate ID
struct DuplicateView: View {
    @Namespace private var ns

    var body: some View {
        VStack {
            Text("Source")
                .matchedGeometryEffect(id: "card", in: ns)
            Text("Destination")
                .matchedGeometryEffect(id: "card", in: ns)  // same id in same namespace
        }
    }
}
```

---
