[← Back to Rules](RULES.md)

## Animation Without Reduce Motion

**Identifier:** `Animation Without Reduce Motion`
**Category:** Accessibility
**Severity:** Info
**Opt-in:** yes — enable via `enabled_only`

### Rationale
Reduce Motion is not a preference about taste. People with vestibular disorders enable it because on-screen motion causes nausea, dizziness, and headaches; for them a spring animation is not a flourish but a symptom trigger. A view that scales, slides, or springs regardless of the setting can make an app physically unpleasant to use.

Unlike most accessibility gaps, this one is invisible in every way a team normally checks. The view looks right, VoiceOver reads it correctly, contrast passes, and the layout survives Dynamic Type. Nothing surfaces the problem except testing with Reduce Motion switched on, which is rarely part of a review.

### Discussion
`AnimationWithoutReduceMotionVisitor` examines each `struct` conforming to `View` or `App` and asks one question: does this view animate, and does it ever mention Reduce Motion?

This is a **struct-level** check by design. Asking per `.animation` call would be far noisier and would misrepresent how the fix works — a single `reduceMotion` property usually governs an entire view, so one mention anywhere in the view is enough to satisfy the rule. The rule reports at most once per view, at the first animation it finds.

The scan runs over the view's member block rather than the view itself, so nested types are judged independently. A nested view's Reduce Motion check does not excuse its enclosing view, and vice versa.

**Counts as animating:** `.animation(…)`, `withAnimation(…)`, and `.transition(…)`.

**Counts as consulting the preference:** any mention of `accessibilityReduceMotion` — however it is used — or UIKit's `UIAccessibility.isReduceMotionEnabled`. The bar is deliberately low: reading the value at all means the author considered motion, and second-guessing *how* they used it would trade real signal for false positives.

**Not treated as motion:** `.animation(nil, …)`, which switches animation off rather than on, and the `.opacity` and `.identity` transitions, which change no position or size.

**Why opt-in:** most SwiftUI views animate and few consult Reduce Motion, so enabling this by default would bury a codebase in Info findings on first run. It is most valuable switched on deliberately, for a focused pass over animation-heavy views. This matches the posture of the other Info-severity heuristic rules (`flag-optional-pair-state`, `redundant-derived-property`).

### Non-Violating Examples
```swift
// Reads the environment value and softens the motion
struct MyView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isLoading = false

    var body: some View {
        Text("Loading")
            .transition(reduceMotion ? .identity : .scale)
            .animation(reduceMotion ? nil : .easeInOut, value: isLoading)
    }
}

// A transition that moves nothing
Text("Hello")
    .transition(.opacity)

// Animation explicitly disabled
Text("Loading")
    .animation(nil, value: isLoading)
```

### Violating Examples
```swift
// Scales and eases regardless of the user's setting
struct MyView: View {
    @State private var isLoading = false

    var body: some View {
        Text("Loading")
            .transition(.scale)
            .animation(.easeInOut, value: isLoading)
    }
}

// A spring the user cannot turn off
struct MyView: View {
    @State private var expanded = false

    var body: some View {
        Button("Toggle") {
            withAnimation(.spring()) { expanded.toggle() }
        }
    }
}
```

---
