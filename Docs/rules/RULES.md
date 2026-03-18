# SwiftProjectLint Rules Reference

SwiftProjectLint is a static analysis tool for SwiftUI projects. It parses Swift source files using SwiftSyntax AST visitors to detect anti-patterns spanning state management, performance, animations, architecture, code quality, security, accessibility, memory management, networking, and UI patterns. This reference documents all 57 lint rules, organized by category, with their identifiers, severity levels, rationale, and concrete code examples drawn directly from the visitor implementations and test suite.

---

## Table of Contents

### State Management
- [Related Duplicate State Variable](#related-duplicate-state-variable)
- [Unrelated Duplicate State Variable](#unrelated-duplicate-state-variable)
- [Uninitialized State Variable](#uninitialized-state-variable)
- [Missing StateObject](#missing-stateobject)
- [Unused State Variable](#unused-state-variable)
- [Fat View](#fat-view)

### Performance
- [Expensive Operation in View Body](#expensive-operation-in-view-body)
- [ForEach Without ID](#foreach-without-id)
- [Large View Body](#large-view-body)
- [ForEach Self ID](#foreach-self-id)
- [Unnecessary View Update](#unnecessary-view-update)

### Animation
- [Deprecated Animation](#deprecated-animation)
- [Animation in High Frequency Update](#animation-in-high-frequency-update)
- [Excessive Spring Animations](#excessive-spring-animations)
- [Long Animation Duration](#long-animation-duration)
- [withAnimation in onAppear](#withanimation-in-onappear)
- [Animation Without State Change](#animation-without-state-change)
- [Conflicting Animations](#conflicting-animations)
- [matchedGeometryEffect Misuse](#matchedgeometryeffect-misuse)
- [Default Animation Curve](#default-animation-curve)
- [Hardcoded Animation Values](#hardcoded-animation-values)

### Architecture
- [Missing Dependency Injection](#missing-dependency-injection)
- [Fat View Detection](#fat-view-detection)
- [Direct Instantiation](#direct-instantiation)
- [Concrete Type Usage](#concrete-type-usage)
- [Accessing Implementation Details](#accessing-implementation-details)
- [Singleton Usage](#singleton-usage)
- [Law of Demeter](#law-of-demeter)

### Code Quality
- [Magic Number](#magic-number)
- [Long Function](#long-function)
- [Hardcoded Strings](#hardcoded-strings)
- [Missing Documentation](#missing-documentation)
- [Protocol Naming Suffix](#protocol-naming-suffix)
- [Actor Naming Suffix](#actor-naming-suffix)
- [Property Wrapper Naming Suffix](#property-wrapper-naming-suffix)
- [Expect Negation](#expect-negation)

### Security
- [Hardcoded Secret](#hardcoded-secret)
- [Unsafe URL](#unsafe-url)

### Accessibility
- [Missing Accessibility Label](#missing-accessibility-label)
- [Missing Accessibility Hint](#missing-accessibility-hint)
- [Inaccessible Color Usage](#inaccessible-color-usage)

### Memory Management
- [Potential Retain Cycle](#potential-retain-cycle)
- [Large Object in State](#large-object-in-state)

### Networking
- [Missing Error Handling](#missing-error-handling)
- [Synchronous Network Call](#synchronous-network-call)

### UI Patterns
- [Nested Navigation View](#nested-navigation-view)
- [Missing Preview](#missing-preview)
- [ForEach With Self ID (UI)](#foreach-with-self-id-ui)
- [ForEach Without ID (UI)](#foreach-without-id-ui)
- [Inconsistent Styling](#inconsistent-styling)
- [Basic Error Handling](#basic-error-handling)

### Other
- [File Parsing Error](#file-parsing-error)
- [Unknown](#unknown)

---

## State Management

---

## Related Duplicate State Variable

**Identifier:** `Related Duplicate State Variable`
**Category:** State Management
**Severity:** Warning

### Rationale
When the same state variable name appears in views that are part of the same hierarchy, SwiftUI will separately track the value in each view. Changes in one view do not automatically propagate to the other. The intended solution is a shared `ObservableObject` injected via `.environmentObject()`.

### Discussion
This rule is a cross-file analysis that operates after all files in a project have been parsed. The `SwiftUIManagementVisitor` collects all `@State` and `@StateObject` variable names per view, and the `CrossFileAnalysisEngine` then correlates duplicates across views that share a parent-child relationship in the view hierarchy. A duplicate found in related views is a stronger signal than one found in unrelated views, and therefore carries a warning severity rather than the info severity used by the unrelated-duplicate rule.

Suppress this rule when different views in the hierarchy intentionally track independent copies of the same local UI state (for example, each row cell in a list tracking its own expansion state under the same variable name).

### Non-Violating Examples
```swift
// Shared state lifted into an ObservableObject injected at the root
class AppState: ObservableObject {
    @Published var isLoggedIn = false
}

struct RootView: View {
    @StateObject private var appState = AppState()
    var body: some View {
        ChildView().environmentObject(appState)
    }
}

struct ChildView: View {
    @EnvironmentObject var appState: AppState
    var body: some View {
        Text(appState.isLoggedIn ? "Logged in" : "Logged out")
    }
}
```

### Violating Examples
```swift
// isLoggedIn tracked independently in both a parent and a child view
struct ParentView: View {
    @State private var isLoggedIn = false
    var body: some View { ChildView() }
}

struct ChildView: View {
    @State private var isLoggedIn = false  // duplicate in related view
    var body: some View { Text("Child") }
}
```

---

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

## Uninitialized State Variable

**Identifier:** `Uninitialized State Variable`
**Category:** State Management
**Severity:** Error

### Rationale
`@State` variables must have an initial value because SwiftUI manages their storage. Declaring a `@State` property without an initial value compiles in some configurations but produces undefined behavior — the property storage is never initialized by SwiftUI, leading to crashes or incorrect UI at runtime.

### Discussion
The error severity reflects that this is a correctness issue, not a style concern. The rule is detected by `SwiftUIManagementVisitor` during single-file analysis when it finds a `@State`-annotated binding that has neither a type-annotated initializer nor an inferred value.

### Non-Violating Examples
```swift
struct MyView: View {
    @State private var count = 0          // initialized with 0
    @State private var name: String = ""  // initialized with ""
    var body: some View { Text("\(count)") }
}
```

### Violating Examples
```swift
struct MyView: View {
    @State private var count: Int  // no initial value — error
    var body: some View { Text("\(count)") }
}
```

---

## Missing StateObject

**Identifier:** `Missing StateObject`
**Category:** State Management
**Severity:** Warning

### Rationale
`@ObservedObject` tells SwiftUI that you do not own the object — the object's lifetime is managed elsewhere. When a view creates an `ObservableObject` that it also owns, `@StateObject` must be used instead. Using `@ObservedObject` for an owned object causes SwiftUI to recreate the object on every redraw, losing all accumulated state.

### Discussion
This rule detects the pattern where a view declares an `@ObservedObject` and there is evidence (in the same file or hierarchy) that the view is responsible for creating that object's instance. The fix is straightforward: replace `@ObservedObject` with `@StateObject` so SwiftUI manages the object's lifetime correctly.

### Non-Violating Examples
```swift
struct ParentView: View {
    // Parent owns the model — correct use of @StateObject
    @StateObject private var viewModel = UserViewModel()
    var body: some View {
        ChildView(viewModel: viewModel)
    }
}

struct ChildView: View {
    // Child receives and observes — correct use of @ObservedObject
    @ObservedObject var viewModel: UserViewModel
    var body: some View { Text(viewModel.name) }
}
```

### Violating Examples
```swift
struct MyView: View {
    // View creates the object but uses @ObservedObject — incorrect
    @ObservedObject private var viewModel = UserViewModel()
    var body: some View { Text(viewModel.name) }
}
```

---

## Unused State Variable

**Identifier:** `Unused State Variable`
**Category:** State Management
**Severity:** Warning

### Rationale
A `@State`, `@StateObject`, or related property wrapper variable that is declared but never referenced in the view body or in functions called from the view adds unnecessary overhead. SwiftUI allocates and tracks storage for every `@State` property; unused ones waste memory and complicate the view's mental model.

### Discussion
`SwiftUIManagementVisitor` compares declared state variables against variable references found in the view's body and child functions. A variable is considered unused if its identifier never appears in any expression within the view scope. Remove unused state variables or replace them with the logic that should use them.

### Non-Violating Examples
```swift
struct CounterView: View {
    @State private var count = 0
    var body: some View {
        Button("Tap") { count += 1 }
        Text("\(count)")
    }
}
```

### Violating Examples
```swift
struct MyView: View {
    @State private var count = 0   // declared but never used
    @State private var name = ""   // declared but never used
    var body: some View {
        Text("Hello")
    }
}
```

---

## Fat View

**Identifier:** `Fat View`
**Category:** State Management
**Severity:** Warning

### Rationale
A view with more than five `@State` or `@StateObject` properties is doing too much work. It is managing business logic and data transformation that should live in a ViewModel. This makes the view hard to test, hard to read, and fragile when requirements change.

### Discussion
The threshold of five state variables is intentionally conservative. Even moderate views rarely need more than a few pieces of local UI state (e.g., a `showingAlert: Bool`, a `selectedTab: Int`). When variables represent business data — user profiles, fetched lists, computed properties — they belong in an `ObservableObject`. Note that this rule uses the `ArchitectureVisitor` but is categorized under state management because the root cause is state accumulation.

### Non-Violating Examples
```swift
struct ProfileView: View {
    @StateObject private var viewModel = ProfileViewModel()
    @State private var showingEditSheet = false
    var body: some View {
        Text(viewModel.name)
    }
}
```

### Violating Examples
```swift
struct ProfileView: View {
    @State private var name = ""
    @State private var email = ""
    @State private var age = 0
    @State private var isLoading = false
    @State private var showingAlert = false
    @State private var errorMessage = ""  // exceeds the 5-variable threshold
    var body: some View { Text(name) }
}
```

---

## Performance

---

## Expensive Operation in View Body

**Identifier:** `Expensive Operation in View Body`
**Category:** Performance
**Severity:** Warning

### Rationale
SwiftUI calls the `body` computed property every time state changes. Placing operations like `sorted`, `filter`, `map`, `reduce`, `flatMap`, or `compactMap` directly in `body` runs them on every redraw. For large collections this causes visible frame drops.

### Discussion
The `PerformanceVisitor` tracks whether execution is inside a `body` getter, then flags calls to any of the listed expensive operations when they appear there. The fix is to move the transformation into the ViewModel or into a `@State`/`@StateObject` property that is updated only when the underlying data changes. Alternatively, `Lazy` collection wrappers can defer evaluation.

### Non-Violating Examples
```swift
class ItemViewModel: ObservableObject {
    @Published var sortedItems: [Item] = []

    func loadItems(_ raw: [Item]) {
        sortedItems = raw.sorted { $0.name < $1.name }
    }
}

struct ItemListView: View {
    @StateObject private var vm = ItemViewModel()
    var body: some View {
        List(vm.sortedItems) { Text($0.name) }
    }
}
```

### Violating Examples
```swift
struct ItemListView: View {
    let items: [Item]
    var body: some View {
        // sorted runs on every redraw
        List(items.sorted { $0.name < $1.name }) { Text($0.name) }
    }
}
```

---

## ForEach Without ID

**Identifier:** `ForEach Without ID`
**Category:** Performance
**Severity:** Warning

### Rationale
`ForEach` uses the `id` parameter to perform efficient diffing when the collection changes. Without an explicit `id`, SwiftUI falls back to index-based identity, which defeats structural diffing and forces full redraws of unchanged elements.

### Discussion
This performance-category rule is detected by `PerformanceVisitor`. A companion UI-category rule (`forEachWithoutIDUI`) detects the same pattern from the UI visitor. The two rules exist because the same issue is independently flagged by both the performance and UI analysis passes. If a `ForEach` item type conforms to `Identifiable`, the `ForEach(_:content:)` form implicitly uses the `id` property and does not trigger this rule.

### Non-Violating Examples
```swift
struct ItemListView: View {
    let items: [Item]
    var body: some View {
        ForEach(items, id: \.id) { item in
            Text(item.name)
        }
    }
}

// Also fine: using Identifiable conformance
struct Item: Identifiable {
    let id: UUID
    let name: String
}

struct ItemListView: View {
    let items: [Item]
    var body: some View {
        ForEach(items) { item in Text(item.name) }  // implicit id from Identifiable
    }
}
```

### Violating Examples
```swift
struct ItemListView: View {
    let items: [String]
    var body: some View {
        // No id: parameter — index-based diffing
        ForEach(items) { item in
            Text(item)
        }
    }
}
```

---

## Large View Body

**Identifier:** `Large View Body`
**Category:** Performance
**Severity:** Warning

### Rationale
A view body with more than 20 statements or a view struct exceeding 50 lines is difficult to comprehend and slows Xcode's type-checker. SwiftUI's type inference is applied to the entire `body` expression at once; very large bodies can cause compilation timeouts and degraded editor responsiveness.

### Discussion
`PerformanceVisitor` counts statements inside the body getter. When it exceeds 20 statements, or when the overall struct text exceeds 50 lines, an issue is reported. The fix is to extract logical sub-sections of the body into dedicated child view structs. This also improves SwiftUI's incremental recomputation because smaller views have narrower dependency graphs.

### Non-Violating Examples
```swift
struct DashboardView: View {
    var body: some View {
        VStack {
            HeaderSection()
            ContentSection()
            FooterSection()
        }
    }
}

struct HeaderSection: View {
    var body: some View { Text("Header") }
}
```

### Violating Examples
```swift
struct DashboardView: View {
    var body: some View {
        VStack {
            Text("Line 1")
            Text("Line 2")
            Text("Line 3")
            // ... 20+ statements in the body
            Text("Line 25")
        }
    }
}
```

---

## ForEach Self ID

**Identifier:** `ForEach Self ID`
**Category:** Performance
**Severity:** Warning

### Rationale
Using `\.self` as the `id` in `ForEach` makes every value its own identity. For non-trivially equatable types, this forces SwiftUI to hash the entire value on every redraw, which is slower than comparing a stable identifier. It also breaks animations when values are mutated, because the old and new values hash differently and SwiftUI treats them as unrelated items.

### Discussion
`PerformanceDetectionHelpers.detectForEachSelfID` inspects the `id:` argument of a `ForEach` call. If the argument expression evaluates to `\.self` (a key path rooted at `Self`), the rule fires. The fix is to introduce a stable `id` property — either by conforming to `Identifiable` or by explicitly specifying `id: \.stableProperty`.

### Non-Violating Examples
```swift
ForEach(items, id: \.id) { item in
    Text(item.name)
}
```

### Violating Examples
```swift
ForEach(items, id: \.self) { item in
    Text(item.name)
}
```

---

## Unnecessary View Update

**Identifier:** `Unnecessary View Update`
**Category:** Performance
**Severity:** Warning

### Rationale
When a state variable is assigned the value it already holds, SwiftUI still schedules a redraw because it observes the assignment, not whether the value changed. Unnecessary reassignments cause spurious re-renders that degrade scrolling performance and battery life.

### Discussion
`PerformanceVisitor` tracks state variable reads and writes. When it detects an assignment to a state variable where the right-hand side could be the same value (e.g., assigning a constant or immediately overwriting), it reports this as a potential unnecessary update. In practice, guarding assignments with an equality check (`if newValue != stateVar { stateVar = newValue }`) eliminates the unnecessary redraw.

### Non-Violating Examples
```swift
struct ToggleView: View {
    @State private var isOn = false
    var body: some View {
        Button("Toggle") {
            isOn.toggle()  // only mutates when the logical value changes
        }
    }
}
```

### Violating Examples
```swift
struct MyView: View {
    @State private var label = "Hello"
    var body: some View {
        Button("Reset") {
            label = "Hello"  // potentially the same value — causes unnecessary redraw
        }
    }
}
```

---

## Animation

---

## Deprecated Animation

**Identifier:** `Deprecated Animation`
**Category:** Animation
**Severity:** Warning

### Rationale
The single-argument form `.animation(.easeIn)` was deprecated in iOS 15 / macOS 12 because it animates all changes to the view indiscriminately, including changes that should not be animated. The two-argument form `.animation(.easeIn, value: someState)` is precise: it animates only when `someState` changes.

### Discussion
`DeprecatedAnimationVisitor` detects `.animation()` modifier calls that have exactly one argument and whose base expression is not a `Binding` (since `Binding.animation()` is a different, still-current API). The fix is always to add a `value:` parameter that identifies the state driving the animation.

### Non-Violating Examples
```swift
struct MyView: View {
    @State private var isVisible = false

    var body: some View {
        Text("Hello")
            .animation(.default, value: isVisible)  // explicit value parameter
    }
}

// Binding.animation() is not deprecated — no issue
struct MyView: View {
    @State private var text = ""
    var body: some View {
        TextField("Input", text: $text.animation())
    }
}
```

### Violating Examples
```swift
struct MyView: View {
    @State private var isAnimating = false

    var body: some View {
        Text("Hello, World!")
            .animation(.default)  // deprecated single-argument form
    }
}
```

---

## Animation in High Frequency Update

**Identifier:** `Animation in High Frequency Update`
**Category:** Animation
**Severity:** Warning

### Rationale
Attaching a `.animation()` modifier immediately after a high-frequency modifier — `onReceive`, `onChange`, or `task` — causes the animation system to run on every event emission. For a timer firing at 60 Hz or a text field's `onChange`, this can create hundreds of simultaneous animations per second, degrading performance and producing visual chaos.

### Discussion
`AnimationPerformanceVisitor` walks the modifier chain inward from an `.animation()` call. If any modifier within the chain is one of the high-frequency callbacks, it flags the pattern. The fix is to move the `.animation()` to a more narrowly scoped view or to use `withAnimation` inside the callback only when a specific condition is met.

### Non-Violating Examples
```swift
struct NormalView: View {
    @State private var isVisible = false

    var body: some View {
        Text("Hello")
            .opacity(isVisible ? 1 : 0)
            .animation(.spring(), value: isVisible)
    }
}
```

### Violating Examples
```swift
struct TimerView: View {
    let timer = Timer.publish(every: 1, on: .main, in: .common)
    @State private var count = 0

    var body: some View {
        Text("\(count)")
            .onReceive(timer) { _ in count += 1 }
            .animation(.spring(), value: count)  // animation chained after onReceive
    }
}

struct ChangeView: View {
    @State private var value = ""
    @State private var isEditing = false

    var body: some View {
        TextField("Input", text: $value)
            .onChange(of: value) { isEditing = true }
            .animation(.easeIn, value: isEditing)  // animation chained after onChange
    }
}
```

---

## Excessive Spring Animations

**Identifier:** `Excessive Spring Animations`
**Category:** Animation
**Severity:** Warning

### Rationale
Spring animations are computationally heavier than linear or ease animations because they simulate a physical spring system with continuous integration. More than three spring animations active simultaneously in a single struct puts measurable load on the animation engine and can cause dropped frames on older devices.

### Discussion
`AnimationPerformanceVisitor` counts `.spring()` call-sites within a `struct` declaration. The count resets at each new struct so that separate, independently animating views are not penalized together. The threshold is four or more — three springs in a struct are acceptable. The fix is to consolidate animations into a single `withAnimation(.spring())` block that animates all related state changes together.

### Non-Violating Examples
```swift
struct ModerateView: View {
    @State private var a = false
    @State private var b = false
    @State private var c = false

    var body: some View {
        VStack {
            Text("1").animation(.spring(), value: a)
            Text("2").animation(.spring(), value: b)
            Text("3").animation(.spring(), value: c)
        }
    }
}
```

### Violating Examples
```swift
struct AnimatedView: View {
    @State private var a = false
    @State private var b = false
    @State private var c = false
    @State private var d = false

    var body: some View {
        VStack {
            Text("1").animation(.spring(), value: a)
            Text("2").animation(.spring(), value: b)
            Text("3").animation(.spring(), value: c)
            Text("4").animation(.spring(), value: d)  // fourth spring — exceeds threshold
        }
    }
}
```

---

## Long Animation Duration

**Identifier:** `Long Animation Duration`
**Category:** Animation
**Severity:** Info

### Rationale
Animations longer than two seconds feel sluggish and unresponsive to users. Human perception is particularly sensitive to delays longer than one second; an animation taking more than two seconds makes an app feel slow regardless of actual performance.

### Discussion
`AnimationPerformanceVisitor` extracts the `duration:` argument from animation factory calls (`.easeIn(duration:)`, `.easeOut(duration:)`, `.easeInOut(duration:)`, `.linear(duration:)`, `.spring(duration:)`) and compares it to the 2.0-second threshold. The boundary is exclusive: a duration of exactly 2.0 seconds does not trigger this rule. The info severity reflects that very occasionally a long animation is intentional (e.g., an ambient background transition).

### Non-Violating Examples
```swift
struct NormalView: View {
    @State private var isVisible = false

    var body: some View {
        Text("Hello")
            .animation(.easeIn(duration: 0.5), value: isVisible)
    }
}

// Exactly 2.0 is also fine
struct BoundaryView: View {
    @State private var isVisible = false

    var body: some View {
        Text("Hello")
            .animation(.easeIn(duration: 2.0), value: isVisible)
    }
}
```

### Violating Examples
```swift
struct SlowView: View {
    @State private var isVisible = false

    var body: some View {
        Text("Hello")
            .animation(.easeIn(duration: 3.0), value: isVisible)  // exceeds 2 seconds
    }
}

struct SlowSpringView: View {
    @State private var isVisible = false

    var body: some View {
        Text("Hello")
            .animation(.spring(duration: 5.0), value: isVisible)  // exceeds 2 seconds
    }
}
```

---

## withAnimation in onAppear

**Identifier:** `withAnimation in onAppear`
**Category:** Animation
**Severity:** Warning

### Rationale
Calling `withAnimation` inside `onAppear` runs immediately when the view first appears. This produces an animation that plays on every view appearance — including when returning from a pushed navigation destination or when a sheet is dismissed — which often feels jarring and unintended.

### Discussion
`WithAnimationVisitor` tracks `onAppear` closure depth and flags any `withAnimation` call found within that depth, including calls nested inside additional closures within `onAppear`. If an intro animation is genuinely desired on first appearance only, use `.task` with a `hasAppeared` guard flag, or use the `.animation(_, value:)` modifier form tied to a state variable that is set in `onAppear`.

### Non-Violating Examples
```swift
struct MyView: View {
    @State private var isVisible = false

    var body: some View {
        Button("Toggle") {
            withAnimation {
                isVisible = true  // withAnimation outside onAppear — fine
            }
        }
    }
}
```

### Violating Examples
```swift
struct MyView: View {
    @State private var isVisible = false

    var body: some View {
        Text("Hello")
            .onAppear {
                withAnimation {  // withAnimation inside onAppear
                    isVisible = true
                }
            }
    }
}
```

---

## Animation Without State Change

**Identifier:** `Animation Without State Change`
**Category:** Animation
**Severity:** Info

### Rationale
A `withAnimation` block that contains no state mutations — no assignments, no compound-assignment operators, no `.toggle()` calls — produces no visual change. The animation wrapper wraps nothing and is dead code.

### Discussion
`WithAnimationVisitor` delegates to a `StateMutationChecker` sub-visitor that walks the closure body looking for `AssignmentExprSyntax`, compound binary operators (`+=`, `-=`, etc.), and zero-argument `.toggle()` calls. If none are found, the block is flagged. The info severity acknowledges that this may be a work in progress during development. An empty `withAnimation { }` block is the clearest trigger.

### Non-Violating Examples
```swift
struct MyView: View {
    @State private var isVisible = false

    var body: some View {
        Button("Toggle") {
            withAnimation {
                isVisible = true   // state mutation present — no issue
            }
        }
    }
}

struct CounterView: View {
    @State private var count = 0

    var body: some View {
        Button("Increment") {
            withAnimation {
                count += 1  // compound assignment counts as mutation
            }
        }
    }
}
```

### Violating Examples
```swift
struct MyView: View {
    var body: some View {
        Button("Tap") {
            withAnimation {
                print("hello")  // no state mutation inside withAnimation
            }
        }
    }
}

struct EmptyView: View {
    var body: some View {
        Button("Tap") {
            withAnimation { }  // completely empty
        }
    }
}
```

---

## Conflicting Animations

**Identifier:** `Conflicting Animations`
**Category:** Animation
**Severity:** Warning

### Rationale
When two `.animation(_, value: x)` modifiers with the same `value:` argument are chained on the same view, only the outermost modifier takes effect — the inner one is silently ignored. This misleads the reader into believing two animations apply, and the unused inner animation wastes type-checker work during compilation.

### Discussion
`AnimationHierarchyVisitor` inspects each `.animation(_, value:)` call. When it finds such a call, it checks whether the immediately inner expression in the modifier chain is also an `.animation(_, value:)` call with the same `value:` text. If so, it flags the pair. Remove the redundant modifier and keep only the intended one.

### Non-Violating Examples
```swift
struct NoConflictView: View {
    @State private var isVisible = false
    @State private var isExpanded = false

    var body: some View {
        Text("Hello")
            .animation(.easeIn, value: isVisible)
            .animation(.spring(), value: isExpanded)  // different values — no conflict
    }
}
```

### Violating Examples
```swift
struct ConflictView: View {
    @State private var isVisible = false

    var body: some View {
        Text("Hello")
            .animation(.easeIn, value: isVisible)
            .animation(.spring(), value: isVisible)  // same value — inner animation ignored
    }
}
```

---

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

## Default Animation Curve

**Identifier:** `Default Animation Curve`
**Category:** Animation
**Severity:** Info

### Rationale
`.animation(.default, value:)` defers the choice of curve to the system. The system default can change between OS versions, meaning the animation behavior of your app may change without you changing any code. Explicit curves such as `.easeInOut` or `.spring()` make behavior deterministic across OS updates.

### Discussion
`AnimationHierarchyVisitor` checks whether the first unlabeled argument to `.animation()` is a `.default` member access expression. The info severity reflects that using the system default is not wrong per se — it adapts to platform conventions — but it is worth a deliberate choice.

### Non-Violating Examples
```swift
struct ExplicitCurveView: View {
    @State private var isVisible = false

    var body: some View {
        Text("Hello")
            .opacity(isVisible ? 1 : 0)
            .animation(.easeInOut, value: isVisible)  // explicit curve
    }
}
```

### Violating Examples
```swift
struct DefaultCurveView: View {
    @State private var isVisible = false

    var body: some View {
        Text("Hello")
            .opacity(isVisible ? 1 : 0)
            .animation(.default, value: isVisible)  // system default curve
    }
}
```

---

## Hardcoded Animation Values

**Identifier:** `Hardcoded Animation Values`
**Category:** Animation
**Severity:** Info

### Rationale
Numeric literals in animation factory calls — such as `.easeIn(duration: 0.3)` or `.spring(response: 0.5, dampingFraction: 0.8)` — are magic numbers. When the same animation is used in multiple places, or when designers ask to adjust the feel, you must hunt down every literal. Named constants make changes immediate and the animation semantics self-documenting.

### Discussion
`HardcodedAnimationValuesVisitor` checks calls to animation factories: `easeIn`, `easeOut`, `easeInOut`, `linear`, `spring`, `interactiveSpring`, and `interpolatingSpring`. For each recognized parameter label (`duration`, `response`, `dampingFraction`, `bounce`, `blendDuration`, `speed`, `repeatCount`) it checks whether the argument is a float or integer literal. If the argument is a named constant or variable reference, no issue is reported.

### Non-Violating Examples
```swift
let animationDuration: Double = 0.3

struct ConstantDurationView: View {
    @State private var isVisible = false

    var body: some View {
        Text("Hello")
            .animation(.easeIn(duration: animationDuration), value: isVisible)
    }
}

// No parameters at all — no issue
struct DefaultSpringView: View {
    @State private var isVisible = false

    var body: some View {
        Text("Hello")
            .animation(.spring(), value: isVisible)
    }
}
```

### Violating Examples
```swift
struct SlowEaseView: View {
    @State private var isVisible = false

    var body: some View {
        Text("Hello")
            .opacity(isVisible ? 1 : 0)
            .animation(.easeIn(duration: 0.5), value: isVisible)  // literal duration
    }
}

struct SpringView: View {
    @State private var isVisible = false

    var body: some View {
        Text("Hello")
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isVisible)  // literal response and dampingFraction
    }
}
```

---

## Architecture

---

## Missing Dependency Injection

**Identifier:** `Missing Dependency Injection`
**Category:** Architecture
**Severity:** Info

### Rationale
Views and objects that create their dependencies internally cannot be tested in isolation. A view with an empty initializer, or a view that instantiates an `ObservableObject` inline with `@StateObject var vm = MyViewModel()`, ties itself to a concrete type that cannot be swapped for a test double.

### Discussion
`ArchitectureVisitor` reports two related scenarios: a `View`-suffixed struct that declares an empty `init()`, and a view whose `@StateObject` property is initialized inline (e.g., `@StateObject var vm = SomeType()`). Both patterns suggest that the dependency could instead be passed through the initializer. The info severity acknowledges that `@StateObject` inline initialization is the correct pattern for app entry points — it is only worth reconsidering when the type needs to be mockable.

### Non-Violating Examples
```swift
struct MyView: View {
    @StateObject private var viewModel: UserViewModelProtocol

    init(viewModel: UserViewModelProtocol) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View { Text(viewModel.name) }
}
```

### Violating Examples
```swift
struct MyView: View {
    @StateObject private var viewModel = UserViewModel()  // inline instantiation

    var body: some View { Text(viewModel.name) }
}

struct MyView: View {
    init() { }  // empty init in a View — no dependencies injected
    var body: some View { Text("Hello") }
}
```

---

## Fat View Detection

**Identifier:** `Fat View Detection`
**Category:** Architecture
**Severity:** Warning

### Rationale
This is the architecture-category counterpart to the state-management `fatView` rule. A SwiftUI view with more than five `@State` or `@StateObject` declarations has accumulated business logic that belongs in a ViewModel. The architecture perspective focuses on the separation-of-concerns violation.

### Discussion
`ArchitectureVisitor` counts `@State` and `@StateObject` properties within each view struct. After visiting the entire struct, if the count exceeds five, an issue is reported pointing to MVVM as the recommended pattern. Extracting state into a `ViewModel: ObservableObject` makes the view a pure render function of the model's published properties.

### Non-Violating Examples
```swift
struct ProfileView: View {
    @StateObject private var viewModel = ProfileViewModel()
    @State private var showingSheet = false

    var body: some View {
        Text(viewModel.name)
            .sheet(isPresented: $showingSheet) { EditView() }
    }
}
```

### Violating Examples
```swift
struct ProfileView: View {
    @State private var name = ""
    @State private var email = ""
    @State private var age = 0
    @StateObject private var imageLoader = ImageLoader()
    @State private var showingAlert = false
    @State private var errorMessage = ""  // sixth property — exceeds threshold

    var body: some View { Text(name) }
}
```

---

## Direct Instantiation

**Identifier:** `Direct Instantiation`
**Category:** Architecture
**Severity:** Warning

### Rationale
Creating a service, manager, repository, or similar object directly at its point of use — rather than receiving it through an initializer or environment — makes code hard to test and creates hidden coupling between consumer and implementation.

### Discussion
`DirectInstantiationVisitor` identifies calls to constructors of types whose names end with service-like suffixes: `Manager`, `Service`, `Store`, `Provider`, `Client`, `Repository`, `Handler`, `Controller`, `Factory`, `Adapter`, `ViewModel`, or `Coordinator`. It fires for stored property initializers, default parameter values, local variable declarations, and closure bodies. It does not fire when the variable has a SwiftUI property wrapper (`@StateObject`, `@ObservedObject`, etc.), because wrapper-decorated `@StateObject var vm = SomeViewModel()` is the correct SwiftUI pattern for owned view models.

### Non-Violating Examples
```swift
// Injected through initializer
class MyViewModel {
    private let service: NetworkService
    init(service: NetworkService) {
        self.service = service
    }
}

// Property wrapper instantiation is acceptable
struct MyView: View {
    @StateObject private var vm = MyViewModel()
    var body: some View { Text("") }
}
```

### Violating Examples
```swift
// Direct instantiation in stored property
class MyView {
    private let svc = NetworkService()  // direct instantiation
}

// Direct instantiation as default parameter
class MyViewModel {
    init(svc: NetworkService = NetworkService()) { }  // default creates concrete instance
}

// Direct instantiation in function body
class Setup {
    func setup() {
        let svc = NetworkService()  // direct instantiation
        _ = svc
    }
}
```

---

## Concrete Type Usage

**Identifier:** `Concrete Type Usage`
**Category:** Architecture
**Severity:** Warning

### Rationale
A function parameter or stored property typed as a concrete service class (e.g., `func configure(service: APIService)`) cannot be substituted with a test double or alternative implementation without modifying the function signature. Protocol abstractions allow callers to pass any conforming type.

### Discussion
`ConcreteTypeUsageVisitor` checks type annotations in function parameters and stored properties (without initializers) for names ending in the same service-like suffixes used by `DirectInstantiationVisitor`. It skips types ending in `Protocol`, `Type`, or `Interface` (which are already abstractions), types annotated with a SwiftUI property wrapper, and parameters typed with `some Protocol` (opaque types). Replacing `APIService` with `APIServiceProtocol` — or using `some NetworkProtocol` — resolves the issue.

### Non-Violating Examples
```swift
// Using a protocol-named type
class Owner {
    var service: NetworkServiceProtocol
    init(service: NetworkServiceProtocol) { self.service = service }
}

// Opaque type — no issue
class Owner {
    func foo(service: some NetworkProtocol) { }
}
```

### Violating Examples
```swift
// Concrete type in function parameter
class Setup {
    func configure(service: APIService) { }  // concrete type
}

// Concrete type in stored property
class MyViewModel {
    var repo: UserRepository  // concrete type, no initializer
    init(repo: UserRepository) { self.repo = repo }
}
```

---

## Accessing Implementation Details

**Identifier:** `Accessing Implementation Details`
**Category:** Architecture
**Severity:** Warning

### Rationale
Two patterns indicate a caller is reaching into an object's implementation rather than using its public interface: accessing underscore-prefixed members on external objects, and force-casting through a protocol reference to access concrete-type-specific members. Both patterns create tight coupling to internal implementation details that may change without notice.

### Discussion
`AccessingImplementationDetailsVisitor` detects two heuristics:

1. **Underscore prefix:** A member access `obj._someProperty` where `obj` is not `self` or `super`. Underscore-prefixed names are a Swift convention for internal or implementation-detail members. `self._member` is exempt because property wrappers use underscore names for their storage.

2. **Force-cast bypass:** A member access whose base expression contains `as! ConcreteServiceType`, where `ConcreteServiceType` ends with a service-like suffix. Force-casting to a concrete type to access members that are not on the protocol is a clear violation of the interface contract.

### Non-Violating Examples
```swift
// Accessing self's own underscore property (property wrapper storage)
class MyClass {
    var _prop: Int = 0
    func read() -> Int { return self._prop }
}

// Optional cast — not flagged (only as! triggers this rule)
func safe(n: Networking) {
    _ = (n as? NetworkService)?.pool
}
```

### Violating Examples
```swift
// Accessing underscore member on another object
class Manager {
    let cache = Cache()
    func clear() { _ = cache._data }  // accessing implementation detail
}

// Force-cast to bypass protocol abstraction
func hack(n: Networking) {
    _ = (n as! NetworkService).connectionPool  // force-cast to concrete type
}
```

---

## Singleton Usage

**Identifier:** `Singleton Usage`
**Category:** Architecture
**Severity:** Warning

### Rationale
Accessing a service through a `.shared` singleton creates a global dependency that is invisible in function signatures and impossible to replace in tests. Code that calls `DataManager.shared.fetch()` is permanently coupled to the `DataManager` implementation and cannot be tested without running the real implementation.

### Discussion
`SingletonUsageVisitor` flags member accesses where the member name is `shared` and the base is a type-name reference (a `DeclReferenceExprSyntax` with an uppercase first character) ending in a service-like suffix. Standard system singletons such as `URLSession.shared`, `UserDefaults.standard`, or `NotificationCenter.default` are not flagged because their base names (`URLSession`, `UserDefaults`, `NotificationCenter`) do not match the service suffixes.

### Non-Violating Examples
```swift
// System singleton — not flagged
class Connector {
    func send() {
        URLSession.shared.dataTask(with: url!)
    }
}

// Injected service — no singleton
class Coordinator {
    private let dataManager: DataManagerProtocol
    init(dataManager: DataManagerProtocol) {
        self.dataManager = dataManager
    }
}
```

### Violating Examples
```swift
class Coordinator {
    func run() {
        DataManager.shared.fetch()  // singleton access — hard coupling
    }
}

class Setup {
    func configure() {
        DataManager.shared.setup()
        AnalyticsService.shared.initialize()  // multiple singletons
    }
}
```

---

## Law of Demeter

**Identifier:** `Law of Demeter`
**Category:** Architecture
**Severity:** Warning

### Rationale
The Law of Demeter (also called the "principle of least knowledge") states that an object should only communicate with its immediate collaborators. A chain like `manager.service.data` requires the calling code to know about `manager`, about `manager`'s `service` property, and about `service`'s `data` property — three layers of internal structure that the caller should not be aware of.

### Discussion
`LawOfDemeterVisitor` detects three-level member access chains where the root is a plain identifier (not `self`, `super`, or a function call). Chains rooted at `self` are exempt because accessing `self.manager.service` is standard within a class's own implementation. Chains rooted at function calls — such as SwiftUI modifier chains like `Text("hi").frame(width: 100).background(.red)` — are also exempt because fluent APIs intentionally chain method calls.

The fix is to add a method on `manager` that encapsulates the `service.data` access, so callers need only know about `manager`.

### Non-Violating Examples
```swift
// Two-level chain — fine
class Owner {
    func run() { let _ = manager.data }
}

// self-chain — fine
class ViewModel {
    func run() { let _ = self.manager.service }
}

// SwiftUI modifier chain — fine
struct MyView: View {
    var body: some View {
        Text("hello").frame(width: 100).background(.red)
    }
}
```

### Violating Examples
```swift
// Three-level chain — Law of Demeter violation
class Owner {
    func run() { let _ = manager.service.data }
}

class Display {
    let user = User()
    func show() -> String { return user.profile.address }  // three-level chain
}
```

---

## Code Quality

---

## Magic Number

**Identifier:** `Magic Number`
**Category:** Code Quality
**Severity:** Info

### Rationale
An integer or float literal of 10 or greater that appears without a named constant is a "magic number." Its meaning is not self-evident to future readers, and if the same value appears in multiple places, a change requires finding and updating every occurrence.

### Discussion
`CodeQualityVisitor` checks integer and float literals in variable initializers and function call arguments. Values below 10 are exempt because small numbers (0, 1, 2) are conventional in many contexts. The threshold is configurable via `CodeQualityVisitor.Configuration.magicNumberThreshold` (default: 10; strict mode: 5). The fix is to declare a named constant: `let maxRetries = 3` and then reference it by name.

### Non-Violating Examples
```swift
let maxRetries = 3
let defaultTimeout: TimeInterval = 30

func configure() {
    connection.timeout = defaultTimeout
    retry(count: maxRetries)
}
```

### Violating Examples
```swift
var count = 100  // magic number ≥ 10

func fetch() {
    URLSession.shared.dataTask(with: url).resume()
    waitFor(seconds: 30)  // literal 30 in function argument
}
```

---

## Long Function

**Identifier:** `Long Function`
**Category:** Code Quality
**Severity:** Warning

### Rationale
A function whose body exceeds 200 characters of source code (in default configuration) is doing too much. Long functions are hard to reason about, difficult to test, and resist refactoring. They accumulate responsibilities that should be separated into smaller, focused functions.

### Discussion
`CodeQualityVisitor` measures function body length in characters (the raw text of the `{ ... }` block). The default threshold is 200 characters. In strict mode the threshold is 150. This is an unconventional metric — most linters count lines — but character count provides a coarser, faster approximation without needing to track newlines. Functions that approach or exceed the threshold should be decomposed into private helper functions with clear, descriptive names.

### Non-Violating Examples
```swift
func validate(_ value: String) -> Bool {
    return !value.isEmpty
}
```

### Violating Examples
```swift
func processUser(_ user: User) {
    // ... 200+ characters of logic mixed together ...
    validateName(user.name)
    validateEmail(user.email)
    saveToDatabase(user)
    sendWelcomeEmail(user)
    logAnalytics(user)
    updateCache(user)
}
```

---

## Hardcoded Strings

**Identifier:** `Hardcoded Strings`
**Category:** Code Quality
**Severity:** Info

### Rationale
String literals of 10 or more characters that appear directly in source code and are not part of a URL, file path, or keyword are likely user-facing text that should be localized. Hardcoded strings prevent internationalization and make content updates require code changes.

### Discussion
`CodeQualityVisitor` checks single-segment string literals (no interpolation) whose content is at least 10 characters long. Strings containing common non-UI patterns — `http`, `https`, `file://`, `data:`, `base64`, and Swift keywords — are skipped. The fix is to use `String(localized: "key", defaultValue: "...")` or `NSLocalizedString("key", comment: "...")`, allowing translators to adapt the text without touching code.

### Non-Violating Examples
```swift
// Localized string
Text(String(localized: "welcome_message"))

// URL — skipped
let endpoint = "https://api.example.com/v1/users"
```

### Violating Examples
```swift
// User-facing text hardcoded
Text("Welcome to the app")

// Error message hardcoded
label.text = "Please try again later"
```

---

## Missing Documentation

**Identifier:** `Missing Documentation`
**Category:** Code Quality
**Severity:** Info

### Rationale
Public APIs without documentation comments force callers to read the implementation to understand how to use a type or function. Documentation comments attached to `public` declarations appear in Quick Help, improve searchability, and enable automated documentation generation.

### Discussion
`CodeQualityVisitor` checks for the presence of `///` doc-line-comment or `/** */` doc-block-comment trivia on the leading trivia of `public` struct, class, and function declarations. In the default configuration only `public` symbols are checked. In strict mode (`checkPublicAPIsOnly: false`) all functions are checked regardless of access level. The info severity reflects that internal documentation is valuable but not urgent.

### Non-Violating Examples
```swift
/// Fetches the user profile for the given identifier.
///
/// - Parameter id: The user's unique identifier.
/// - Returns: The user profile, or nil if not found.
public func fetchProfile(id: String) -> UserProfile? { ... }
```

### Violating Examples
```swift
public func fetchProfile(id: String) -> UserProfile? { ... }
// No documentation comment above a public function
```

---

## Protocol Naming Suffix

**Identifier:** `Protocol Naming Suffix`
**Category:** Code Quality
**Severity:** Info

### Rationale
Naming protocols with a `Protocol` suffix makes a type's role immediately visible at every usage site. When a parameter is typed as `NetworkService`, a reader cannot tell whether it is a class or a protocol. When it is typed as `NetworkServiceProtocol`, the abstraction is self-evident.

### Discussion
`NamingConventionVisitor` checks every `protocol` declaration. If the protocol's name does not end with `Protocol`, an issue is reported with a suggestion to rename it. The Swift standard library names protocols descriptively (e.g., `Equatable`, `Hashable`), but within an application codebase — especially one using dependency injection — the explicit suffix aids comprehension and LLM-based tooling.

### Non-Violating Examples
```swift
protocol NetworkServiceProtocol {
    func fetch() async throws -> Data
}

protocol RequestableProtocol {
    func perform() async throws
}
```

### Violating Examples
```swift
protocol Requestable { func perform() async throws }  // missing "Protocol" suffix

protocol DataStore { func save() }  // missing "Protocol" suffix
```

---

## Actor Naming Suffix

**Identifier:** `Actor Naming Suffix`
**Category:** Code Quality
**Severity:** Info

### Rationale
Naming actors with an `Actor` suffix makes Swift's concurrency isolation semantics visible at every call site. When a property is typed as `ImageDownloaderActor`, any `await` expressions at call sites have a clear explanation — the call crosses an actor boundary.

### Discussion
`NamingConventionVisitor` checks every `actor` declaration. If the name does not end with `Actor`, an issue is reported. Like the protocol naming rule, this is a project-specific convention that prioritizes clarity over brevity.

### Non-Violating Examples
```swift
actor ImageDownloaderActor {
    func download(url: URL) async -> Data { ... }
}
```

### Violating Examples
```swift
actor ImageDownloader {  // missing "Actor" suffix
    func download(url: URL) async -> Data { ... }
}
```

---

## Property Wrapper Naming Suffix

**Identifier:** `Property Wrapper Naming Suffix`
**Category:** Code Quality
**Severity:** Info

### Rationale
Property wrappers annotated with `@propertyWrapper` transform the behavior of the properties they decorate. A `Wrapper` suffix in the type name signals to readers that applying `@MyType` to a property will invoke the wrapper protocol rather than simply declaring a stored value of that type.

### Discussion
`NamingConventionVisitor` checks `struct` and `class` declarations that carry the `@propertyWrapper` attribute. If the type name does not end with `Wrapper`, an issue is reported. This rule applies to both struct and class property wrappers.

### Non-Violating Examples
```swift
@propertyWrapper
struct ClampedWrapper<Value: Comparable> {
    var wrappedValue: Value
}

@propertyWrapper
struct UserDefaultWrapper<Value> {
    var wrappedValue: Value
}
```

### Violating Examples
```swift
@propertyWrapper
struct Clamped<Value: Comparable> {  // missing "Wrapper" suffix
    var wrappedValue: Value
}

@propertyWrapper
class Observable<Value> {  // missing "Wrapper" suffix
    var wrappedValue: Value
    init(wrappedValue: Value) { self.wrappedValue = wrappedValue }
}
```

---

## Expect Negation

**Identifier:** `Expect Negation`
**Category:** Code Quality
**Severity:** Warning

### Rationale
`#expect(!expression)` negates inside the macro. When the assertion fails, Swift Testing captures the value of the negated prefix operator (`!`) — which is simply `false` — rather than the value of `expression`. This produces an unhelpful failure message. `#expect(expression == false)` captures `expression`'s actual value and displays it in the test report.

### Discussion
`ExpectNegationVisitor` identifies `MacroExpansionExprSyntax` nodes where the macro name is `expect` and the first unlabeled argument is a `PrefixOperatorExprSyntax` with operator text `!`. It does not flag `#require(!expr)` because `#require` is a different macro. Negation outside of a `#expect` call (in `if` conditions, `let` bindings, etc.) is also not flagged.

### Non-Violating Examples
```swift
#expect(isVisible == false)   // explicit comparison — full diagnostic context
#expect(items.isEmpty == false)
#expect(isVisible)            // positive assertion — fine
#expect(count == 3)
```

### Violating Examples
```swift
#expect(!isVisible)       // negation defeats sub-expression capture
#expect(!items.isEmpty)   // negation inside expect
```

---

## Security

---

## Hardcoded Secret

**Identifier:** `Hardcoded Secret`
**Category:** Security
**Severity:** Error

### Rationale
API keys, passwords, tokens, and other secrets embedded directly in source code are committed to version control, distributed in app binaries, and accessible to anyone who can inspect the binary. A secret leaked through source code is effectively compromised and must be rotated immediately.

### Discussion
`SecurityVisitor` checks variable declarations whose name contains one of the keywords `apiKey`, `secret`, `password`, `token`, or `key` (case-insensitive). If the initializer is a string literal, an error-severity issue is reported. The fix is to store secrets in the system Keychain, retrieve them from environment variables at build time, or fetch them from a secure remote configuration endpoint at runtime.

### Non-Violating Examples
```swift
// Read from Keychain at runtime
let apiKey = KeychainService.shared.retrieve(key: "apiKey")

// Environment variable injected at build time (Xcode configuration)
let token = ProcessInfo.processInfo.environment["API_TOKEN"] ?? ""
```

### Violating Examples
```swift
let apiKey = "12345"          // hardcoded secret
let secret = "topsecret"      // hardcoded secret
let password = "hunter2"      // hardcoded secret
let token = "abcdef"          // hardcoded secret
```

---

## Unsafe URL

**Identifier:** `Unsafe URL`
**Category:** Security
**Severity:** Warning

### Rationale
Constructing URLs with string interpolation — `URL(string: "https://example.com/\(path)")` — is unsafe for two reasons: user-controlled input may contain characters that break URL parsing, leading to unexpected behavior; and without percent-encoding, the resulting URL may be malformed or bypass server-side validation.

### Discussion
`SecurityVisitor` detects `URL(string:)` calls where the string argument contains `\(` (string interpolation) or `+` (concatenation). The safe alternative is `URLComponents`, which applies correct percent-encoding to each component independently and makes the URL structure explicit.

### Non-Violating Examples
```swift
// URLComponents with safe percent-encoding
var components = URLComponents(string: "https://api.example.com")!
components.queryItems = [URLQueryItem(name: "token", value: userToken)]
let url = components.url

// Plain string literal — no interpolation
let url = URL(string: "https://example.com/api")
```

### Violating Examples
```swift
let token = "abc123"
let userId = "user456"

let unsafeURL1 = URL(string: "https://example.com/api?token=\(token)")   // interpolation
let unsafeURL2 = URL(string: "https://example.com/api?user=\(userId)")   // interpolation
```

---

## Accessibility

---

## Missing Accessibility Label

**Identifier:** `Missing Accessibility Label`
**Category:** Accessibility
**Severity:** Warning

### Rationale
A `Button` that contains an `Image` without an `.accessibilityLabel()` modifier provides no information to VoiceOver. Screen readers will announce the image file name or nothing at all, making the button unusable for users who rely on assistive technologies.

### Discussion
`ButtonAccessibilityChecker` searches for `Image` views inside `Button` declarations (recursively, including trailing closures and labeled `label:` arguments). When an image is found and no `.accessibilityLabel()` modifier is present on the button, a warning is reported. Buttons that contain only `Text` are handled by the `missingAccessibilityHint` rule.

### Non-Violating Examples
```swift
Button {
    deleteItem()
} label: {
    Image(systemName: "trash")
}
.accessibilityLabel("Delete item")
```

### Violating Examples
```swift
Button {
    deleteItem()
} label: {
    Image(systemName: "trash")  // no accessibilityLabel
}
```

---

## Missing Accessibility Hint

**Identifier:** `Missing Accessibility Hint`
**Category:** Accessibility
**Severity:** Info

### Rationale
Accessibility hints provide additional context about what an interactive element does, beyond its label. For text buttons — where VoiceOver reads the label automatically — a hint answers "what happens when I activate this?" The info severity reflects that hints are strongly recommended but not mandatory for all buttons.

### Discussion
`ButtonAccessibilityChecker` checks buttons containing `Text` views for the presence of an `.accessibilityHint()` modifier. The check is a complementary signal to the accessibility label rule. Buttons that use `Label` views (which combine an image and text) may satisfy both rules if both a label and a hint are provided.

### Non-Violating Examples
```swift
Button("Submit") {
    submitForm()
}
.accessibilityHint("Submits the current form and navigates to the confirmation screen")
```

### Violating Examples
```swift
Button("Submit") {  // text button with no accessibilityHint
    submitForm()
}
```

---

## Inaccessible Color Usage

**Identifier:** `Inaccessible Color Usage`
**Category:** Accessibility
**Severity:** Info

### Rationale
Color alone must not be used to convey information. Users with color vision deficiencies (affecting approximately 8% of males) cannot distinguish information communicated solely through hue. WCAG 2.1 Success Criterion 1.4.1 requires that color not be the only visual means of conveying information.

### Discussion
`ColorAccessibilityChecker` flags two patterns: direct `Color.xxx` member accesses (e.g., `Color.red`), and `.foregroundColor()` modifier calls without a co-located `.accessibilityLabel()`, `.accessibilityHint()`, or `.accessibilityValue()` modifier. When a foreground color is used alongside an accessibility modifier, the flag is suppressed because the developer has consciously provided alternative context. The info severity reflects that some color usage is purely decorative and does not convey information.

### Non-Violating Examples
```swift
// Color with accompanying accessibility label
Circle()
    .foregroundColor(statusColor)
    .accessibilityLabel(statusDescription)

// Text is already accessible — color is decorative
Text("Success")
    .foregroundColor(.green)
    .accessibilityLabel("Success")
```

### Violating Examples
```swift
// Color.red used without any alternative text/icon
Circle()
    .foregroundColor(Color.red)  // color alone conveys status

// foregroundColor without accessibility modifier
Text("Error occurred")
    .foregroundColor(.red)  // color-only status indication
```

---

## Memory Management

---

## Potential Retain Cycle

**Identifier:** `Potential Retain Cycle`
**Category:** Memory Management
**Severity:** Warning

### Rationale
When a `@StateObject` property is both typed and initialized with the same concrete type — `@StateObject var viewModel: ContentViewModel = ContentViewModel()` — and that type internally holds a reference back to its owner, a retain cycle can form. SwiftUI manages `@StateObject` lifetime through strong references; a circular reference in that chain prevents deallocation.

### Discussion
`MemoryManagementVisitor` detects the specific pattern where a `@StateObject` binding has an explicit type annotation and an initializer, and both name the same type. This is a heuristic: the same-type pattern is a necessary but not sufficient condition for a retain cycle. The suggestion is to review the object's lifecycle and consider using `weak` references for callbacks or delegates, or restructuring to use dependency injection.

### Non-Violating Examples
```swift
// Initialized with a different type (e.g., a subclass or mock)
struct ContentView: View {
    @StateObject var viewModel: ContentViewModel = DifferentViewModel()
    var body: some View { Text("Hello") }
}

// No initializer — injected externally
struct ContentView: View {
    @StateObject var viewModel: ContentViewModel
    var body: some View { Text("Hello") }
}
```

### Violating Examples
```swift
// Same type in annotation and initializer — potential cycle
struct ContentView: View {
    @StateObject var viewModel: ContentViewModel = ContentViewModel()
    var body: some View { Text("Hello") }
}
```

---

## Large Object in State

**Identifier:** `Large Object in State`
**Category:** Memory Management
**Severity:** Info

### Rationale
Placing a large array — more than 100 literal elements — in a `@State` property means SwiftUI copies and manages the entire array as value-type state. Every mutation triggers a full copy of the array through the property observation chain, causing unnecessary memory allocations and potentially degrading performance.

### Discussion
`MemoryManagementVisitor` checks `@State` bindings whose type annotation is an `ArrayTypeSyntax` and whose initializer is an array literal with more than 100 elements. The threshold of 100 is configurable via `MemoryManagementVisitor.Configuration.maxArraySize`. The fix is to move the collection into an `@StateObject` view model, where mutations are controlled through `@Published` properties and SwiftUI only observes the reference, not the collection contents.

### Non-Violating Examples
```swift
struct ContentView: View {
    @State var items: [String] = ["item1", "item2", "item3"]  // small array — fine
    var body: some View { Text("Hello") }
}
```

### Violating Examples
```swift
struct ContentView: View {
    @State var items: [String] = [
        "item1", "item2", /* ... */ "item101"  // more than 100 elements
    ]
    var body: some View { Text("Hello") }
}
```

---

## Networking

---

## Missing Error Handling

**Identifier:** `Missing Error Handling`
**Category:** Networking
**Severity:** Warning

### Rationale
A `URLSession.dataTask` completion handler that ignores the `error` parameter silently drops network failures. Users see stale data or a spinning indicator with no indication that an error occurred. Proper error handling enables the UI to display meaningful feedback.

### Discussion
`NetworkingVisitor` examines the trailing closure of `URLSession.dataTask` calls. It checks whether the third parameter is named `error` (and handled with `if let`, `guard let`, `error != nil`, `error.`, or `error as` patterns), or whether the third parameter is `_` (ignored), or whether error handling patterns appear in the closure body text even without a named third parameter. If none of these patterns are found, a warning is reported. The visitor also reports a separate issue when the third parameter is explicitly `_` (discarded), because ignoring the error parameter is a distinct anti-pattern.

### Non-Violating Examples
```swift
// Named error parameter handled with if let
URLSession.shared.dataTask(with: url) { data, response, error in
    if let error = error {
        print(error)
    }
}.resume()

// Guard let pattern
URLSession.shared.dataTask(with: url) { data, response, error in
    guard let error = error else { return }
    print(error)
}.resume()

// Error != nil check
URLSession.shared.dataTask(with: url) { data, response, error in
    if error != nil {
        print("Error occurred")
    }
}.resume()
```

### Violating Examples
```swift
// No error handling — error parameter ignored
URLSession.shared.dataTask(with: url) { data, response, _ in
    // No error handling
}.resume()

// No closure at all for error
URLSession.shared.dataTask(with: url) { data, response in
    // only two params — no error handling
}.resume()
```

---

## Synchronous Network Call

**Identifier:** `Synchronous Network Call`
**Category:** Networking
**Severity:** Error

### Rationale
`Data(contentsOf: url)` performs a synchronous network request on the calling thread. When called on the main thread, this blocks the UI for the full duration of the network round trip — potentially several seconds — causing the app to become unresponsive and the system watchdog to terminate it.

### Discussion
`NetworkingVisitor` detects calls to `Data(contentsOf:)` by looking for `Data` as the called expression and `contentsOf` as a labeled argument. The error severity reflects that this is a correctness issue in production apps. The fix is to use `URLSession.shared.dataTask(with:completionHandler:)` or `URLSession.shared.data(from:)` in a `Task` for concurrent code.

### Non-Violating Examples
```swift
// Async with URLSession
Task {
    let (data, _) = try await URLSession.shared.data(from: url)
    // process data
}

// Data() without contentsOf — fine
let emptyData = Data()
let fixedData = Data([1, 2, 3])
```

### Violating Examples
```swift
let url = URL(string: "https://example.com")!
let data = try Data(contentsOf: url)  // synchronous network call — blocks main thread
```

---

## UI Patterns

---

## Nested Navigation View

**Identifier:** `Nested Navigation View`
**Category:** UI Patterns
**Severity:** Warning

### Rationale
Nesting a `NavigationView` inside another `NavigationView` in the same view hierarchy creates two independent navigation stacks that fight for control. This produces visual artifacts — two navigation bars, broken back buttons, or unexpected title behavior — that are difficult to debug.

### Discussion
`UIVisitor` maintains a navigation stack as it walks struct declarations. When a `NavigationView` call is encountered inside a view that is already in the navigation stack, the nested navigation is flagged. The recommended fix is to use `NavigationStack` (iOS 16+) instead, which handles nested navigation destinations correctly and eliminates the ambiguity.

### Non-Violating Examples
```swift
// Single NavigationView
struct ContentView: View {
    var body: some View {
        NavigationView {
            Text("Single Navigation")
        }
    }
}

// NavigationStack — modern and safe
struct ContentView: View {
    var body: some View {
        NavigationStack {
            Text("Modern Navigation")
        }
    }
}
```

### Violating Examples
```swift
struct ContentView: View {
    var body: some View {
        NavigationView {
            VStack {
                NavigationView {  // nested NavigationView
                    Text("Nested Navigation")
                }
            }
        }
    }
}
```

---

## Missing Preview

**Identifier:** `Missing Preview`
**Category:** UI Patterns
**Severity:** Info

### Rationale
SwiftUI previews accelerate the development loop. A view without a preview requires launching the simulator to see any visual change. The Xcode canvas and `#Preview` macro make it inexpensive to add a preview, and even a minimal preview catches layout issues that unit tests cannot.

### Discussion
`UIVisitor` tracks view names (from `struct` declarations conforming to `View`) and preview declarations (from `#Preview` macro expansions and `PreviewProvider` conformances). After visiting each view struct, if no preview was detected for that view name in the file, an info-severity issue is reported. Test files (paths containing `test.swift`, `Test`, or `Tests`) are exempt because preview-less test helper views are common.

### Non-Violating Examples
```swift
struct ContentView: View {
    var body: some View { Text("Hello") }
}

#Preview {
    ContentView()
}
```

### Violating Examples
```swift
// No #Preview or PreviewProvider in the file
struct ContentView: View {
    var body: some View { Text("Hello") }
}
```

---

## ForEach With Self ID (UI)

**Identifier:** `ForEach With Self ID`
**Category:** UI Patterns
**Severity:** Warning

### Rationale
This UI-category rule detects the same `ForEach(items, id: \.self)` anti-pattern as the performance-category `forEachSelfID` rule, but from the UI pass. Using `\.self` as the identity breaks smooth list animations because mutated values hash to different identities, causing SwiftUI to remove and re-add rows rather than animate them in place.

### Discussion
`ForEachSelfIDVisitor` performs the same check as `PerformanceDetectionHelpers.detectForEachSelfID`. The duplicate detection exists because the UI analysis pass and the performance analysis pass run independently. See the `ForEach Self ID` rule under Performance for detailed discussion.

### Non-Violating Examples
```swift
ForEach(items, id: \.id) { item in
    Text(item.name)
}
```

### Violating Examples
```swift
ForEach(items, id: \.self) { item in
    Text(item.name)
}
```

---

## ForEach Without ID (UI)

**Identifier:** `ForEach Without ID UI`
**Category:** UI Patterns
**Severity:** Warning

### Rationale
This UI-category counterpart to the performance-category `forEachWithoutID` rule detects `ForEach` calls with no `id:` parameter. Without explicit identity, SwiftUI uses array indices, which fails when items are inserted or removed — causing incorrect animations and stale cell content.

### Discussion
`UIVisitor` checks every `ForEach` call for the presence of an `id:` labeled argument. If none is found, a warning is reported. The UI rule and the performance rule fire independently from their respective analysis passes.

### Non-Violating Examples
```swift
struct ContentView: View {
    let items = [Item(id: "1"), Item(id: "2")]

    var body: some View {
        ForEach(items, id: \.id) { item in
            Text(item.id)
        }
    }
}
```

### Violating Examples
```swift
struct ContentView: View {
    let items = ["A", "B", "C"]

    var body: some View {
        ForEach(items) { item in  // no id: parameter
            Text(item)
        }
    }
}
```

---

## Inconsistent Styling

**Identifier:** `Inconsistent Styling`
**Category:** UI Patterns
**Severity:** Info

### Rationale
Applying more than one styling modifier (font, foregroundColor, background, padding, cornerRadius, shadow, border) directly to individual `Text` elements in the same view, rather than extracting them into a shared `ViewModifier` or style extension, leads to visual inconsistency as the number of styled elements grows.

### Discussion
`UIVisitor` collects styling modifiers applied to each `Text` call by walking the parent expression chain. If more than one recognized styling modifier is found on a single `Text`, it reports an info issue suggesting extraction into a `ViewModifier`. This rule flags the threshold at two or more styling modifiers on a single `Text`.

### Non-Violating Examples
```swift
// Style extracted to a ViewModifier
struct HeadlineStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.headline)
            .foregroundColor(.primary)
    }
}

struct MyView: View {
    var body: some View {
        Text("Title").modifier(HeadlineStyle())
    }
}
```

### Violating Examples
```swift
struct MyView: View {
    var body: some View {
        Text("Title")
            .font(.headline)
            .foregroundColor(.blue)  // two styling modifiers inline
    }
}
```

---

## Basic Error Handling

**Identifier:** `Basic Error Handling`
**Category:** UI Patterns
**Severity:** Info

### Rationale
Displaying errors with `Text("Error: ...")` in the view body is a bare-minimum pattern that is easy to miss and hard for users to act on. SwiftUI provides `.alert()` and `.sheet()` modifiers that present errors in a standardized, dismissible modal that integrates with platform conventions.

### Discussion
`UIVisitor` inspects the view body text for error-handling patterns: `if let error` bindings or `Text("Error` literals. When such a pattern is found but no `.alert()`, `.sheet()`, or `Alert(` call is present, it reports an info issue suggesting proper error presentation. This is a text-based heuristic, so it may produce false positives if the patterns appear in comments or unrelated string literals.

### Non-Violating Examples
```swift
struct MyView: View {
    @State private var errorMessage: String? = nil

    var body: some View {
        Text("Content")
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
    }
}
```

### Violating Examples
```swift
struct MyView: View {
    var error: Error?

    var body: some View {
        if let error = error {
            Text("Error: \(error.localizedDescription)")  // basic text display, no alert
        }
    }
}
```

---

## Other

---

## File Parsing Error

**Identifier:** `File Parsing Error`
**Category:** Other
**Severity:** Error

### Rationale
Indicates that SwiftProjectLint was unable to parse a Swift source file. This is typically caused by a syntax error in the file or by an unsupported Swift language feature. Issues of this type are synthetic — they are generated by the analysis pipeline, not by any lint rule visitor.

### Discussion
When a file cannot be parsed, no rules can be applied to it. The error is reported at line 1 with the file path, prompting the developer to inspect the file for syntax errors. These issues are not suppressible through the normal rule configuration mechanism.

---

## Unknown

**Identifier:** `Unknown`
**Category:** Other
**Severity:** Warning

### Rationale
A fallback rule identifier used when an issue is generated without a specific `RuleIdentifier`. This should not appear in normal operation and indicates an internal inconsistency in the analysis pipeline.

### Discussion
`RuleIdentifier.unknown` is used in placeholder `SyntaxPattern` instances created by visitor convenience initializers and in code paths that call `addIssue(ruleName: nil)`. If issues with this identifier appear in results, they point to analysis code that has not yet been assigned a proper rule identifier.

---

*Generated from visitor source code and test cases in SwiftProjectLint. To contribute a rule correction or new rule, see the [contributor guide](../CONTRIBUTING.md).*
