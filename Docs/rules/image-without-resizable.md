[<- Back to Rules](RULES.md)

## Image Without Resizable

**Identifier:** `Image Without Resizable`
**Category:** UI Patterns
**Severity:** Info

### Rationale
Applying `.frame()` to an `Image` without first calling `.resizable()` has no effect on the image size — the image renders at its intrinsic size and the frame just adds empty space around it. This is a very common SwiftUI mistake and a frequent source of layout bugs.

### Discussion
`ImageWithoutResizableVisitor` walks modifier chains starting from `.frame()` calls backwards to find the root expression. If the root is an `Image(...)` call and no `.resizable()` modifier appears in the chain before `.frame()`, it flags the issue.

### Non-Violating Examples
```swift
// resizable before frame — correct
Image("hero")
    .resizable()
    .frame(width: 200, height: 100)

// resizable with aspectRatio and frame
Image("hero")
    .resizable()
    .aspectRatio(contentMode: .fit)
    .frame(width: 200)

// No frame — no issue
Image("hero")
    .resizable()
```

### Violating Examples
```swift
// frame without resizable — image renders at intrinsic size
Image("hero")
    .frame(width: 200, height: 100)

// SF Symbol without resizable
Image(systemName: "star.fill")
    .frame(width: 50, height: 50)
```

---
