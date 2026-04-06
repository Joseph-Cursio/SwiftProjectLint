[<- Back to Rules](RULES.md)

## Legacy Image Renderer

**Identifier:** `Legacy Image Renderer`
**Category:** Modernization
**Severity:** Info

### Rationale
`UIGraphicsImageRenderer` is the UIKit image rendering API. SwiftUI's `ImageRenderer` (iOS 16+) renders SwiftUI views directly to images without UIKit, producing cleaner code in SwiftUI projects.

### Discussion
`LegacyImageRendererVisitor` flags both instantiation (`UIGraphicsImageRenderer(...)`) and type annotations referencing `UIGraphicsImageRenderer`.

Note: `ImageRenderer` requires iOS 16+ / macOS 13+. If your project targets earlier versions, this rule may produce false positives.

### Non-Violating Examples
```swift
// SwiftUI ImageRenderer (iOS 16+)
let renderer = ImageRenderer(content: myView)
let image = renderer.uiImage
```

### Violating Examples
```swift
// UIKit rendering API
let renderer = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100))
let image = renderer.image { context in
    // drawing code
}
```

---
