# HWS AGENTS.md Rule Proposals

This document tracks rule proposals sourced from Paul Hudson's [SwiftAgents AGENTS.md](https://github.com/twostraws/SwiftAgents/blob/main/AGENTS.md), surfaced via the article ["Teach your AI to write Swift the Hacking with Swift way"](https://www.hackingwithswift.com/articles/284/teach-your-ai-to-write-swift-the-hacking-with-swift-way).

The AGENTS.md is a curated style guide for writing idiomatic, modern Swift/SwiftUI code. Many of its rules map directly to detectable AST patterns. This file records what was implemented and what remains, with enough detail for a new session to continue without re-reading the source.

---

## Status Overview

| Rule | Status | Category |
|------|--------|----------|
| `Task.sleep(nanoseconds:)` | ✅ Implemented (`taskSleepNanoseconds`) | Modernization |
| `.foregroundColor()` | ✅ Implemented (`foregroundColorDeprecated`) | Modernization |
| `.cornerRadius()` | ✅ Implemented (`cornerRadiusDeprecated`) | Modernization |
| `String(format:)` | ✅ Implemented (`legacyStringFormat`) | Modernization |
| `ScrollViewReader` | ✅ Implemented (`scrollViewReaderDeprecated`) | Modernization |
| `AnyView` usage | ✅ Implemented (`anyViewUsage`) | Performance |
| Computed property views | 🔲 Not implemented | Architecture |
| `.onTapGesture()` replacing `Button` | 🔲 Not implemented | UI Patterns |
| `.replacingOccurrences(of:with:)` | 🔲 Not implemented | Modernization |
| `tabItem()` → `Tab` API | 🔲 Not implemented | Modernization |
| `DateFormatter`/`NumberFormatter`/`MeasurementFormatter` globally | 🔲 Not implemented | Modernization |
| `fontWeight(.bold)` → `.bold()` | 🔲 Not implemented | Code Quality |
| `UIGraphicsImageRenderer` → `ImageRenderer` | 🔲 Not implemented | Modernization |
| `showsIndicators: false` → `.scrollIndicators(.hidden)` | 🔲 Not implemented | Modernization |
| `@Attribute(.unique)` with CloudKit | 🔲 Not implemented | Architecture |
| `GeometryReader` overuse | 🔲 Not implemented | Performance |

---

## Already Covered by Existing Rules (pre-session)

These rules from AGENTS.md were already handled before this work began — listed here to avoid re-implementing them.

| AGENTS.md rule | Existing `RuleIdentifier` case |
|---|---|
| Avoid `DispatchQueue.main.async()` | `dispatchMainAsync` |
| Avoid `ObservableObject`/`@StateObject`/`@ObservedObject` | `legacyObservableObject`, `observedObjectInline` |
| `@Observable` missing `@MainActor` | `observableMainActorMissing` |
| `NavigationView` deprecated | `navigationViewDeprecated` |
| Force unwrap / force try | `forceUnwrap`, `forceTry` |
| Hard-coded font sizes | `hardcodedFontSize` |
| Hard-coded padding/spacing values | `magicLayoutNumber` |
| Icon-only button missing label | `iconOnlyButtonMissingLabel` |
| `@EnvironmentObject` overuse | `tooManyEnvironmentObjects` |

---

## Remaining Proposals (not yet implemented)

### 1. Computed Property Views

**Priority: High** — Strong architectural signal, interesting AST detection.

**AGENTS.md rule:** "Avoid breaking views into computed properties; use separate `View` structs instead."

**Rationale:** Computed properties that return `some View` are a common pattern for breaking up `body`, but they defeat SwiftUI's structural identity. SwiftUI can only diff views at the `body` boundary; sub-views expressed as computed properties get re-evaluated on every parent update with no diffing. Separate `struct` views give SwiftUI a stable identity boundary and can independently hold `@State`.

**Detection:** Look for `var` declarations (not named `body`) that have a `some View` return type annotation inside a struct/class that conforms to `View`. In SwiftSyntax: `VariableDeclSyntax` with `TypeAnnotationSyntax` containing `SomeOrAnyTypeSyntax` where the wrapped type is `View`. Must exclude `var body`.

**Suggested rule name:** `computedPropertyView`
**Category:** `.architecture`
**Severity:** `.warning`

```swift
// Violating
struct ContentView: View {
    var header: some View {   // ← flag this
        Text("Title").font(.largeTitle)
    }

    var body: some View {
        VStack { header }     // ← body is fine
    }
}

// Correct
struct ContentView: View {
    var body: some View {
        VStack { HeaderView() }
    }
}

struct HeaderView: View {
    var body: some View {
        Text("Title").font(.largeTitle)
    }
}
```

**Implementation notes:**
- Must scope detection to types that conform to `View` (or at least have a `body: some View` property) to avoid false positives on non-view types.
- `var body` must be excluded.
- `var preview` (for `#Preview` helpers) could be excluded or flagged at `.info`.
- Consider allowing `@ViewBuilder` computed properties — these at least get the `@ViewBuilder` diffing behaviour, though they're still not as clean as separate structs. Could flag without `@ViewBuilder` at `.warning`, with `@ViewBuilder` at `.info`.

---

### 2. `onTapGesture` Replacing Button

**Priority: High** — Accessibility regression, easy to detect.

**AGENTS.md rule:** "Avoid `onTapGesture()` unless you need tap location or count data. Prefer standard `Button` for most interactions."

**Rationale:** `.onTapGesture { }` bypasses SwiftUI's button semantics. It doesn't participate in accessibility (`Button` provides an implicit `button` accessibility trait, keyboard/pointer focus, and haptic feedback on iOS). The only legitimate use is when you specifically need `onTapGesture(count:)` for double-tap, or `onTapGesture { location in }` for tap position.

**Detection:** `FunctionCallExprSyntax` where `calledExpression` is `MemberAccessExprSyntax` with `declName.baseName.text == "onTapGesture"`. To reduce false positives, only flag the zero-argument form (or single trailing-closure form) — i.e. no `count:` label and no `coordinateSpace:` label on the arguments. Calls with `count:` > 1 or `location:` parameter should be allowed.

**Suggested rule name:** `onTapGestureInsteadOfButton`
**Category:** `.accessibility` (or `.uiPatterns`)
**Severity:** `.warning`

```swift
// Violating
Text("Tap me")
    .onTapGesture { doSomething() }

Image(systemName: "trash")
    .onTapGesture { deleteItem() }

// Allowed — needs location
Text("Tap here")
    .onTapGesture { location in
        handleTap(at: location)
    }

// Allowed — needs double tap
Text("Double tap")
    .onTapGesture(count: 2) { doubleTapped() }

// Correct replacement
Button("Tap me") { doSomething() }
Button { deleteItem() } label: {
    Image(systemName: "trash")
}
```

**Implementation notes:**
- The key false-positive cases to allow: `onTapGesture(count:)` with count > 1, and `onTapGesture { location in ... }` (location-aware form).
- Detecting the location form requires inspecting the closure signature for a parameter that receives a `CGPoint` — this is hard without type info. A simpler heuristic: allow any `onTapGesture` call that has a labelled `count:` argument or a closure with exactly one parameter named `location` or with a type annotation. Consider starting with `.info` severity to reduce noise from legitimate location uses.

---

### 3. `replacingOccurrences(of:with:)` → `.replacing(_:with:)`

**Priority: Medium** — Trivial to implement, same pattern as the batch we just added.

**AGENTS.md rule:** "Prefer `replacing("hello", with: "world")` over `replacingOccurrences(of:with:)`."

**Rationale:** `.replacingOccurrences(of:with:)` is the Foundation/Objective-C API. Swift 5.7 (iOS 16) introduced `.replacing(_:with:)` which accepts `RegexComponent` or `Collection`, is generic over the replacement type, and reads more naturally in Swift code.

**Detection:** `FunctionCallExprSyntax` where `calledExpression` is `MemberAccessExprSyntax` with `declName.baseName.text == "replacingOccurrences"` and the first argument label is `"of"`.

**Suggested rule name:** `legacyReplacingOccurrences`
**Category:** `.modernization`
**Severity:** `.info`

```swift
// Violating
let result = str.replacingOccurrences(of: "hello", with: "world")

// Correct
let result = str.replacing("hello", with: "world")
```

**Implementation notes:**
- Straightforward method name + first-argument label check. Same visitor pattern as `TaskSleepNanosecondsVisitor`.
- Note: `.replacing(_:with:)` requires iOS 16+. If the project targets iOS 15 or earlier this would be a false positive. Consider documenting this in the rule's suggestion text rather than attempting to detect deployment target (which would require reading the project file).

---

### 4. `tabItem()` → `Tab` API

**Priority: Medium** — iOS 18+ modernization.

**AGENTS.md rule:** "Prefer `Tab` API over `tabItem()`."

**Rationale:** iOS 18 introduced a new `TabView` API using `Tab` views directly as content, replacing the `tabItem { }` modifier pattern. The new API is declarative and composable, and supports sidebar-style navigation on iPadOS without extra work.

**Detection:** `FunctionCallExprSyntax` where `calledExpression` is `MemberAccessExprSyntax` with `declName.baseName.text == "tabItem"`.

**Suggested rule name:** `tabItemDeprecated`
**Category:** `.modernization`
**Severity:** `.info` (iOS 18+ requirement makes `.warning` premature)

```swift
// Violating (old API)
TabView {
    ContentView()
        .tabItem {
            Label("Home", systemImage: "house")
        }
    SettingsView()
        .tabItem {
            Label("Settings", systemImage: "gear")
        }
}

// Correct (iOS 18+)
TabView {
    Tab("Home", systemImage: "house") {
        ContentView()
    }
    Tab("Settings", systemImage: "gear") {
        SettingsView()
    }
}
```

---

### 5. `DateFormatter`/`NumberFormatter`/`MeasurementFormatter` — Global Detection

**Priority: Medium** — Extends existing `formatterInViewBody` rule.

**Context:** The existing `formatterInViewBodyVisitor` already catches `DateFormatter`, `NumberFormatter`, and `MeasurementFormatter` instantiated *inside a view body*. This proposal extends that to catch them anywhere in source code — they're expensive to create and should always be cached as static/class-level properties or replaced with `FormatStyle`.

**Detection:** `FunctionCallExprSyntax` where `calledExpression` is `DeclReferenceExprSyntax` with `baseName.text` in `["DateFormatter", "NumberFormatter", "MeasurementFormatter"]`. The existing rule already has this logic — a global version just removes the "are we inside a view body" guard.

**Suggested rule name:** `legacyFormatter`
**Category:** `.modernization` (or `.performance`)
**Severity:** `.info`

```swift
// Violating — anywhere in code
let formatter = DateFormatter()
formatter.dateStyle = .medium

// Correct — use FormatStyle
let formatted = date.formatted(.dateTime.month().day().year())

// Correct — or cache it statically
extension DateFormatter {
    static let medium: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()
}
```

**Implementation notes:**
- Need to avoid double-flagging with `formatterInViewBody` (which fires at `.warning`). Either consolidate the two rules or make this one only fire *outside* view bodies (and let the existing rule handle the view body case). The simplest approach is a separate rule with a check to skip view body contexts.
- Could also just deprecate `formatterInViewBody` and replace it with this broader rule.

---

### 6. `fontWeight(.bold)` → `.bold()`

**Priority: Low** — Minor style preference, easy false positive surface.

**AGENTS.md rule:** "Prefer `bold()` over `fontWeight(.bold)` for emphasis."

**Detection:** `FunctionCallExprSyntax` where callee is `MemberAccessExprSyntax` with `declName.baseName.text == "fontWeight"` AND the single argument's expression is a `MemberAccessExprSyntax` with `declName.baseName.text == "bold"`.

**Suggested rule name:** `fontWeightBold`
**Category:** `.codeQuality`
**Severity:** `.info`

```swift
// Violating
Text("Hello").fontWeight(.bold)

// Correct
Text("Hello").bold()
```

**Implementation notes:**
- Only flag `.fontWeight(.bold)` specifically — other `fontWeight` calls (`.semibold`, `.heavy`, etc.) have no shorthand and should not be flagged.
- Very low priority; mostly stylistic.

---

### 7. `UIGraphicsImageRenderer` → `ImageRenderer`

**Priority: Low** — Niche use case.

**AGENTS.md rule:** "Prefer `ImageRenderer` over `UIGraphicsImageRenderer` for rendering."

**Rationale:** `ImageRenderer` (SwiftUI, iOS 16+) renders SwiftUI views directly to images without UIKit. `UIGraphicsImageRenderer` is UIKit-only and doesn't understand SwiftUI views.

**Detection:** `FunctionCallExprSyntax` or `DeclReferenceExprSyntax` (for type references) with `baseName.text == "UIGraphicsImageRenderer"`.

**Suggested rule name:** `legacyImageRenderer`
**Category:** `.modernization`
**Severity:** `.info`

---

### 8. `showsIndicators: false` → `.scrollIndicators(.hidden)`

**Priority: Low** — Deprecated initializer parameter.

**AGENTS.md rule:** "Prefer `.scrollIndicators(.hidden)` modifier over `showsIndicators: false`."

**Rationale:** The `ScrollView(showsIndicators:)` initializer parameter was the old way. The `.scrollIndicators(.hidden)` modifier is the iOS 16+ replacement and is more composable.

**Detection:** `FunctionCallExprSyntax` where callee is `DeclReferenceExprSyntax("ScrollView")` AND one argument has `label.text == "showsIndicators"`.

**Suggested rule name:** `scrollViewShowsIndicators`
**Category:** `.modernization`
**Severity:** `.info`

```swift
// Violating
ScrollView(.vertical, showsIndicators: false) {
    content
}

// Correct
ScrollView(.vertical) {
    content
}
.scrollIndicators(.hidden)
```

---

### 9. `@Attribute(.unique)` with CloudKit

**Priority: Medium** — Rare but high-value catch; silent data loss risk.

**AGENTS.md rule:** "Avoid `@Attribute(.unique)` when using CloudKit."

**Rationale:** `@Attribute(.unique)` on a SwiftData `@Model` property silently breaks CloudKit sync. CloudKit doesn't support uniqueness constraints at the server level, and the combination causes sync conflicts or data loss. Apple's documentation warns against this but it's easy to miss.

**Detection:** Two-part check:
1. The file contains a `@Model` class (look for `@Model` attribute on a `ClassDeclSyntax`).
2. Within that class, a stored property has `@Attribute(.unique)` (look for `AttributeSyntax` with name "Attribute" and argument `.unique`).

**Suggested rule name:** `swiftDataUniqueAttributeCloudKit`
**Category:** `.architecture`
**Severity:** `.error` (data loss risk)

```swift
// Violating
@Model
class User {
    @Attribute(.unique) var email: String  // ← breaks CloudKit sync
    var name: String
}

// Correct — remove @Attribute(.unique) when using CloudKit
@Model
class User {
    var email: String
    var name: String
}
```

**Implementation notes:**
- Detecting "is this project using CloudKit" from source alone is hard. The safest approach is to always flag `@Attribute(.unique)` inside `@Model` classes and add a note in the suggestion: "If this model is not synced via CloudKit, suppress this rule."
- This is a file-local check (both `@Model` and `@Attribute(.unique)` are in the same class), so no cross-file analysis needed.
- Consider `.warning` instead of `.error` given we can't confirm CloudKit is in use.

---

### 10. `GeometryReader` Overuse

**Priority: Low** — High false positive risk; needs careful scoping.

**AGENTS.md rule:** "Avoid `GeometryReader` when `containerRelativeFrame()` or `visualEffect()` suffice."

**Rationale:** `GeometryReader` is a sledgehammer — it eagerly consumes all available space and passes geometry to a closure, making the layout inflexible. iOS 17 introduced `containerRelativeFrame()` for proportional sizing and `visualEffect()` for geometry-dependent effects, both of which are more composable.

**Detection:** `FunctionCallExprSyntax` where `calledExpression` is `DeclReferenceExprSyntax("GeometryReader")`.

**Suggested rule name:** `geometryReaderOveruse`
**Category:** `.performance`
**Severity:** `.info` (can't know if it's truly avoidable without semantic understanding)

**Implementation notes:**
- This is the hardest rule to get right because `GeometryReader` is sometimes legitimately necessary (e.g. reading size for a custom layout, or complex scroll effects that `visualEffect` can't express). Flagging it at `.info` with a suggestion to "consider `containerRelativeFrame()` or `visualEffect()`" is the safest approach.
- Marking it as opt-in (disabled by default) may be appropriate given the false positive surface.

---

## Implementation Order Recommendation

For the next session, suggested order based on value vs. implementation complexity:

1. **`computedPropertyView`** — High value, interesting AST (needs conformance check), medium complexity
2. **`onTapGestureInsteadOfButton`** — High accessibility value, straightforward detection with a couple of allow-list cases
3. **`legacyReplacingOccurrences`** — Trivial, same pattern as the existing modernization batch
4. **`scrollViewShowsIndicators`** — Trivial, call + argument label check
5. **`swiftDataUniqueAttributeCloudKit`** — Medium complexity, high value, good test story
6. **`tabItemDeprecated`** — Trivial
7. **`legacyFormatter`** — Consider consolidating with existing `formatterInViewBody` first
8. **`geometryReaderOveruse`** — Lowest priority, opt-in candidate

---

## Implementation Pattern Reference

All new rules follow this 4-file pattern (plus one doc file):

```
Packages/SwiftProjectLintRules/Sources/SwiftProjectLintRules/
  {Category}/Visitors/{RuleName}Visitor.swift       ← detection logic
  {Category}/PatternRegistrars/{RuleName}.swift     ← SyntaxPattern definition
  {Category}/PatternRegistrars/{Category}.swift     ← add to registerPatterns()

Packages/SwiftProjectLintModels/Sources/SwiftProjectLintModels/
  RuleIdentifier.swift                               ← add case + category switch arm

Tests/CoreTests/{Category}/{RuleName}VisitorTests.swift

Docs/rules/{rule-kebab-case}.md
Docs/rules/RULES.md                                 ← add row + update count
```

Visitor skeleton (for simple call-site detection):
```swift
final class FooVisitor: BasePatternVisitor {
    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let memberAccess = node.calledExpression.as(MemberAccessExprSyntax.self),
              memberAccess.declName.baseName.text == "targetMethod" else { return .visitChildren }
        addIssue(severity: .warning, message: "...", filePath: getFilePath(for: Syntax(node)),
                 lineNumber: getLineNumber(for: Syntax(node)), suggestion: "...", ruleName: .fooRule)
        return .visitChildren
    }
}
```

For detecting a method call by name on any receiver (modifier pattern):
- `node.calledExpression.as(MemberAccessExprSyntax.self)` — method on a receiver (e.g. `.foregroundColor()`)

For detecting a free function or type initializer:
- `node.calledExpression.as(DeclReferenceExprSyntax.self)` — bare name call (e.g. `AnyView(...)`, `ScrollViewReader { }`)

For detecting a method with a specific argument label:
- `node.arguments.contains { $0.label?.text == "format" }`
