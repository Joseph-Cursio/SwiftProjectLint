# SwiftUI Animation Analyzer

> **Status**: Proposal / Not Yet Implemented
>
> This document outlines a comprehensive analyzer for detecting SwiftUI animation anti-patterns, performance issues, and incorrect usage patterns.

## 1. Overview

The SwiftUI Animation Analyzer extends the existing animation detection infrastructure (which currently only has the `deprecatedAnimation` rule) to provide thorough animation quality analysis. This feature will help developers write performant, correct SwiftUI animations.

## 2. Rationale

SwiftUI animations are a common source of:
- **Performance issues**: Animations in high-frequency update contexts, excessive spring animations
- **Incorrect behavior**: Using deprecated APIs, animations without state changes
- **Layout problems**: `withAnimation` in `onAppear`, conflicting animations
- **Best practice violations**: Using `.default` curve, hardcoded values

---

## 3. Animation Issues to Detect

### 3.1 High Priority (Performance Impact)

| Rule | Description | Severity |
|------|-------------|----------|
| `animationInHighFrequencyUpdate` | Animation modifiers inside `onReceive`, `onChange`, or timer callbacks | Warning |
| `excessiveSpringAnimations` | More than 3 spring animations in a single view | Warning |
| `longAnimationDuration` | Animation duration > 2 seconds | Info |
| `withAnimationInOnAppear` | `withAnimation` inside `onAppear` closure | Warning |
| `animationWithoutStateChange` | `withAnimation` block without state mutations | Info |

### 3.2 Medium Priority (Correctness)

| Rule | Description | Severity |
|------|-------------|----------|
| `deprecatedAnimation` | `.animation()` without `value:` parameter | Warning (EXISTS) |
| `conflictingAnimations` | Multiple `.animation()` modifiers targeting same property | Warning |
| `matchedGeometryEffectMisuse` | Missing namespace or incorrect ID usage | Warning |

### 3.3 Low Priority (Best Practices)

| Rule | Description | Severity |
|------|-------------|----------|
| `defaultAnimationCurve` | Using `.animation(.default)` without specifying curve | Info |
| `hardcodedAnimationValues` | Magic numbers in animation parameters | Info |

---

## 4. Detection Heuristics

### 4.1 Animation in High-Frequency Context

```swift
// BAD: Animation modifier near high-frequency callbacks
.onReceive(timer) { _ in value += 1 }
.animation(.spring())

// GOOD: Move animation to explicit state change
.onChange(of: value) { withAnimation(.spring()) { ... } }
```

**Detection Logic:**
- Track when inside `onReceive`, `onChange`, or `task` closures
- Flag any `.animation()` modifier applied within these contexts
- Consider modifier chains where animation follows high-frequency callback

### 4.2 Excessive Spring Animations

```swift
// BAD: Too many spring animations in one view
VStack {
    Text("1").animation(.spring())
    Text("2").animation(.spring())
    Text("3").animation(.spring())
    Text("4").animation(.spring())  // Warning triggered
}

// GOOD: Consolidate or use simpler curves
VStack { ... }
    .animation(.spring(), value: isVisible)
```

**Detection Logic:**
- Count `.spring()` animation calls within a single struct/class body
- Threshold: More than 3 spring animations triggers warning
- Consider allowing configuration of threshold

### 4.3 withAnimation in onAppear

```swift
// BAD: Can cause layout issues
.onAppear {
    withAnimation { isVisible = true }
}

// GOOD: Use animation modifier with value
.animation(.default, value: isVisible)
.onAppear { isVisible = true }
```

**Detection Logic:**
- Detect `withAnimation` calls inside `onAppear` closure bodies
- Flag as warning with suggestion to use animation modifier instead

### 4.4 Animation Without State Change

```swift
// BAD: withAnimation with no effect
withAnimation {
    print("Hello")  // No state mutation
}

// GOOD: Actually mutate state
withAnimation {
    isVisible.toggle()
}
```

**Detection Logic:**
- Analyze `withAnimation` closure body
- Check for assignment expressions to `@State`, `@Binding`, or `@Published` variables
- Flag if no state mutations found

### 4.5 Conflicting Animations

```swift
// BAD: Multiple animation modifiers
Text("Hello")
    .animation(.easeIn, value: x)
    .animation(.spring(), value: x)  // Conflict on same value

// GOOD: Single animation
Text("Hello")
    .animation(.spring(), value: x)
```

**Detection Logic:**
- Track modifier chains for multiple `.animation()` calls
- Check if they target the same `value:` parameter
- Flag conflicts

### 4.6 matchedGeometryEffect Misuse

```swift
// BAD: Missing or incorrect namespace
Text("Hello")
    .matchedGeometryEffect(id: "text", in: someNamespace)
// Warning if someNamespace is not declared with @Namespace

// GOOD: Proper namespace usage
@Namespace private var namespace
Text("Hello")
    .matchedGeometryEffect(id: "text", in: namespace)
```

**Detection Logic:**
- Track `@Namespace` declarations in scope
- Verify `matchedGeometryEffect` uses declared namespaces
- Check for duplicate IDs within the same namespace

---

## 5. Model Changes

### 5.1 New RuleIdentifier Cases

Add to `Sources/SwiftProjectLintCore/Models/RuleIdentifier.swift`:

```swift
// Animation Rules (expand existing)
case animationInHighFrequencyUpdate = "Animation in High Frequency Update"
case excessiveSpringAnimations = "Excessive Spring Animations"
case longAnimationDuration = "Long Animation Duration"
case withAnimationInOnAppear = "withAnimation in onAppear"
case animationWithoutStateChange = "Animation Without State Change"
case conflictingAnimations = "Conflicting Animations"
case matchedGeometryEffectMisuse = "matchedGeometryEffect Misuse"
case defaultAnimationCurve = "Default Animation Curve"
case hardcodedAnimationValues = "Hardcoded Animation Values"
```

### 5.2 Category Mapping

Update the `category` computed property to map all new cases to `.animation`:

```swift
case .animationInHighFrequencyUpdate,
     .excessiveSpringAnimations,
     .longAnimationDuration,
     .withAnimationInOnAppear,
     .animationWithoutStateChange,
     .conflictingAnimations,
     .matchedGeometryEffectMisuse,
     .defaultAnimationCurve,
     .hardcodedAnimationValues:
    return .animation
```

---

## 6. New Visitor Classes

### 6.1 Directory Structure

```
Sources/SwiftProjectLintCore/Animation/
├── AnimationPatternRegistrar.swift (UPDATE)
├── DeprecatedAnimationPatternRegistrar.swift (EXISTS)
├── DeprecatedAnimationVisitor.swift (EXISTS)
├── Visitors/
│   ├── AnimationPerformanceVisitor.swift (NEW)
│   ├── WithAnimationVisitor.swift (NEW)
│   ├── AnimationHierarchyVisitor.swift (NEW)
│   └── MatchedGeometryVisitor.swift (NEW)
└── PatternRegistrars/
    ├── AnimationPerformancePatternRegistrar.swift (NEW)
    ├── WithAnimationPatternRegistrar.swift (NEW)
    ├── AnimationHierarchyPatternRegistrar.swift (NEW)
    └── MatchedGeometryPatternRegistrar.swift (NEW)
```

### 6.2 AnimationPerformanceVisitor

**Detects:** `animationInHighFrequencyUpdate`, `excessiveSpringAnimations`, `longAnimationDuration`

**Key Logic:**
- Track context (inside `onReceive`/`onChange`/`task` closures)
- Count spring animations per view
- Extract duration from Animation initializers

```swift
final class AnimationPerformanceVisitor: BasePatternVisitor {
    private var springAnimationCount = 0
    private var isInHighFrequencyContext = false

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        // Check for high-frequency callbacks
        if isHighFrequencyCallback(node) {
            isInHighFrequencyContext = true
        }

        // Check for animation calls
        if isAnimationCall(node) {
            if isInHighFrequencyContext {
                addIssue(node: Syntax(node)) // animationInHighFrequencyUpdate
            }
            if isSpringAnimation(node) {
                springAnimationCount += 1
                if springAnimationCount > 3 {
                    addIssue(node: Syntax(node)) // excessiveSpringAnimations
                }
            }
            if let duration = extractDuration(node), duration > 2.0 {
                addIssue(node: Syntax(node)) // longAnimationDuration
            }
        }

        return .visitChildren
    }
}
```

### 6.3 WithAnimationVisitor

**Detects:** `withAnimationInOnAppear`, `animationWithoutStateChange`

**Key Logic:**
- Track closure context (`onAppear`, `onChange`, etc.)
- Trace state variable mutations inside `withAnimation` blocks

```swift
final class WithAnimationVisitor: BasePatternVisitor {
    private var isInOnAppear = false

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        // Track onAppear context
        if isOnAppearCall(node) {
            isInOnAppear = true
        }

        // Check for withAnimation
        if isWithAnimationCall(node) {
            if isInOnAppear {
                addIssue(node: Syntax(node)) // withAnimationInOnAppear
            }
            if !containsStateMutation(node.trailingClosure) {
                addIssue(node: Syntax(node)) // animationWithoutStateChange
            }
        }

        return .visitChildren
    }
}
```

### 6.4 AnimationHierarchyVisitor

**Detects:** `conflictingAnimations`, `defaultAnimationCurve`

**Key Logic:**
- Analyze modifier chains for multiple animation modifiers
- Check animation curve parameters

```swift
final class AnimationHierarchyVisitor: BasePatternVisitor {
    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        // Check modifier chain for multiple animations
        let animationModifiers = extractAnimationModifiers(from: node)

        if hasConflictingAnimations(animationModifiers) {
            addIssue(node: Syntax(node)) // conflictingAnimations
        }

        if usesDefaultCurve(node) {
            addIssue(node: Syntax(node)) // defaultAnimationCurve
        }

        return .visitChildren
    }
}
```

### 6.5 MatchedGeometryVisitor

**Detects:** `matchedGeometryEffectMisuse`

**Key Logic:**
- Track `@Namespace` declarations
- Validate `matchedGeometryEffect` namespace/ID usage

```swift
final class MatchedGeometryVisitor: BasePatternVisitor {
    private var declaredNamespaces: Set<String> = []
    private var usedGeometryIds: [String: Set<String>] = [:] // namespace -> ids

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        // Track @Namespace declarations
        if hasNamespaceAttribute(node) {
            if let name = extractVariableName(node) {
                declaredNamespaces.insert(name)
            }
        }
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if isMatchedGeometryEffect(node) {
            let (namespace, id) = extractNamespaceAndId(node)

            if !declaredNamespaces.contains(namespace) {
                addIssue(node: Syntax(node)) // undeclared namespace
            }

            if usedGeometryIds[namespace]?.contains(id) == true {
                addIssue(node: Syntax(node)) // duplicate ID
            }
            usedGeometryIds[namespace, default: []].insert(id)
        }
        return .visitChildren
    }
}
```

---

## 7. Pattern Registration

### 7.1 Update AnimationPatternRegistrar

```swift
struct AnimationPatternRegistrar {
    static func registerPatterns() {
        let registry = SwiftSyntaxPatternRegistry.shared

        // Existing
        registry.register(deprecatedAnimationPattern())

        // New patterns
        registry.register(animationPerformancePattern())
        registry.register(withAnimationPattern())
        registry.register(animationHierarchyPattern())
        registry.register(matchedGeometryPattern())
    }
}
```

---

## 8. Testing Strategy

### 8.1 Test File Structure

Create tests under `Tests/CoreTests/Animation/`:

```
Tests/CoreTests/Animation/
├── DeprecatedAnimationVisitorTests.swift (EXISTS)
├── AnimationVisitorTests.swift (EXISTS)
├── AnimationPerformanceVisitorTests.swift (NEW)
├── WithAnimationVisitorTests.swift (NEW)
├── AnimationHierarchyVisitorTests.swift (NEW)
├── MatchedGeometryVisitorTests.swift (NEW)
└── AnimationIntegrationTests.swift (NEW)
```

### 8.2 Test Cases per Visitor

Each test file should include:
- **Positive cases**: Issue detected correctly
- **Negative cases**: Clean code not flagged
- **Edge cases**: Boundary conditions

#### AnimationPerformanceVisitorTests

```swift
@Suite
struct AnimationPerformanceVisitorTests {
    @Test
    func testDetectsAnimationInOnReceive() {
        let code = """
        struct MyView: View {
            var body: some View {
                Text("Hi")
                    .onReceive(timer) { _ in count += 1 }
                    .animation(.spring())
            }
        }
        """
        // Assert issue detected
    }

    @Test
    func testAllowsAnimationOutsideHighFrequencyContext() {
        let code = """
        struct MyView: View {
            var body: some View {
                Text("Hi")
                    .animation(.spring(), value: isVisible)
            }
        }
        """
        // Assert no issue
    }

    @Test
    func testDetectsExcessiveSpringAnimations() {
        // Test with 4+ spring animations
    }

    @Test
    func testDetectsLongAnimationDuration() {
        // Test with duration > 2 seconds
    }
}
```

#### WithAnimationVisitorTests

```swift
@Suite
struct WithAnimationVisitorTests {
    @Test
    func testDetectsWithAnimationInOnAppear() {
        let code = """
        .onAppear {
            withAnimation { isVisible = true }
        }
        """
        // Assert issue detected
    }

    @Test
    func testDetectsAnimationWithoutStateChange() {
        let code = """
        withAnimation {
            print("No state change")
        }
        """
        // Assert issue detected
    }
}
```

---

## 9. Implementation Phases

### Phase 1: Foundation
- [ ] Add new `RuleIdentifier` cases
- [ ] Create directory structure for new visitors
- [ ] Implement `AnimationPerformanceVisitor` (spring counting only)
- [ ] Write initial tests for spring animation detection

### Phase 2: Core Performance Detection
- [ ] Extend `AnimationPerformanceVisitor` (high-frequency context, duration)
- [ ] Implement `WithAnimationVisitor`
- [ ] Comprehensive test coverage for performance rules

### Phase 3: Hierarchy and Conflicts
- [ ] Implement `AnimationHierarchyVisitor`
- [ ] Implement `MatchedGeometryVisitor`
- [ ] Edge case testing

### Phase 4: Polish
- [ ] Integration tests across all animation visitors
- [ ] Real-world code validation
- [ ] Documentation updates
- [ ] SwiftLint compliance check

---

## 10. Configuration Options

Consider adding configurable thresholds:

```swift
struct AnimationAnalyzerConfiguration {
    /// Maximum spring animations before warning (default: 3)
    var maxSpringAnimations: Int = 3

    /// Maximum animation duration in seconds before warning (default: 2.0)
    var maxAnimationDuration: Double = 2.0

    /// Whether to warn about default animation curve (default: true)
    var warnOnDefaultCurve: Bool = true
}
```

---

## 11. References

- [SwiftUI Animation Best Practices](https://developer.apple.com/documentation/swiftui/animation) - Apple Documentation
- [Deprecated animation modifier](https://developer.apple.com/documentation/swiftui/view/animation(_:)) - Apple Documentation
- [matchedGeometryEffect](https://developer.apple.com/documentation/swiftui/view/matchedgeometryeffect(id:in:properties:anchor:issource:)) - Apple Documentation
- Existing implementation: `Sources/SwiftProjectLintCore/Animation/DeprecatedAnimationVisitor.swift`
