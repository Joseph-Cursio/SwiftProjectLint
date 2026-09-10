[← Back to Rules](RULES.md)

## Concrete Type Usage

**Identifier:** `Concrete Type Usage`
**Category:** Architecture
**Severity:** Info

### Rationale
A function parameter or stored property typed as a concrete service class (e.g., `func configure(service: APIService)`) cannot be substituted with a test double or alternative implementation without modifying the function signature. Protocol abstractions allow callers to pass any conforming type.

### Discussion
`ConcreteTypeUsageVisitor` checks type annotations in function parameters and stored properties (without initializers) for names ending in service-like suffixes (`Manager`, `Service`, `Store`, `Provider`, `Client`, `Repository`, `Handler`, `Controller`, `Factory`, `Adapter`, `ViewModel`, `Coordinator`, `Generator`, `Analyzer`, `Simulator`, `Engine`, `Checker`). It skips types ending in `Protocol`, `Type`, or `Interface` (which are already abstractions), types annotated with a SwiftUI property wrapper, and parameters typed with `some Protocol` (opaque types).

The following patterns are exempt because they do not represent real coupling issues:

- **DI containers** — types whose name ends in `Container`, `Dependencies`, `Composition`, or `Assembly` are composition roots where concrete types are intentional
- **System/Foundation types** — `FileManager`, `NotificationCenter`, `UserDefaults`, `URLSession`, `ProcessInfo`, `Bundle`, etc. cannot reasonably be protocol-abstracted
- **Mock/stub/fake types** — test doubles are concrete by design
- **ViewModels in SwiftUI views** — SwiftUI property wrappers (`@State`, `@ObservedObject`, `@Bindable`) require concrete types, so protocol-abstracting ViewModels in views is impractical
- **Test files** — test code and test helpers use concrete types by necessity
- **SwiftUI property wrapper properties** — `@State`, `@StateObject`, `@ObservedObject`, `@EnvironmentObject`, `@Binding`, `@Published`, `@AppStorage`, `@SceneStorage`, `@Bindable`, `@Environment`
- **Enum types** — a project-wide pre-scan identifies all declared enums; enum-typed parameters and properties are exempt because enums are value types and cannot be protocol-abstracted in the same way as a service class
- **Actor types** — a project-wide pre-scan identifies all declared actors; actor-typed parameters and properties are exempt because an actor's serial-executor isolation contract is load-bearing in Swift 6 strict concurrency. Protocol-abstracting an actor strips that contract from every call site — the caller loses the compiler-enforced `await` requirement and the guarantee of serialized access
- **Init parameters mirroring a flagged stored property** — when a stored property is flagged, its matching initializer parameter represents the same coupling point and is suppressed to avoid duplicate reports
- **AppKit and UIKit classes** — recognised by the `NS`/`UI` prefix convention rather than enumerated, and only when the project does not declare a type of that name
- **`private` / `fileprivate` types** — a protocol around one could only be conformed to in the file that declares it
- **Closure wrapper types** — a `struct` or `final class` whose only stored property is a closure is already the seam
- **`Equatable` types** — a value is substituted by constructing a different one

Replacing `APIService` with `APIServiceProtocol` — or using `some NetworkProtocol` — resolves the issue.

### Four exemptions added after one pass of applying the rule

The rule ran at 41 findings across ten repositories. Reading all of them found four shapes where
the advice has no reachable end state, and **`ConcreteTypeUsage` had reported every one of them
while its own twin already knew better about two.** Each was measured over the corpus before
shipping; together they took the rule **41 → 22**, with nothing else moving.

#### AppKit and UIKit classes (7)

The system-type list above is hand-maintained because Swift 3 dropped the `NS` prefix from
Foundation, so there is no convention left to read `FileManager` and `URLSession` off. AppKit and
UIKit kept theirs, so their classes can be recognised by the rule that generates them rather than
added one name per sweep.

`NSLayoutManager` is a system type in exactly the sense `FileManager` is; it was reported only
because nobody had hit it before. And most of the corpus's instances are worse than merely
unabstractable — they are **parameters of protocol requirements**, where the signature is not the
author's to change at all: a `UIImagePickerControllerDelegate` callback, an
`NSLayoutManagerDelegate` glyph hook, a `UIViewControllerRepresentable`'s `updateUIViewController`.

**Restricted to `NS` and `UI` deliberately.** The obvious generalisation — every Apple two-letter
prefix — is refuted by this corpus: `CLIToolCommandRunner` begins with `CL` followed by an
uppercase letter, so a CoreLocation prefix would have silenced it for a reason that has nothing to
do with why it should be silent. That case is pinned as a test. The gate is also paired with
`knownLocalTypeNames`, so a project declaring its own `UIStateManager` keeps the finding: **the
declaration decides, not the spelling.**

#### `private` and `fileprivate` types (1)

No caller outside the declaring file can name the type, so a protocol around it could only ever be
conformed to there and no test could supply an alternative conformer. Taking the advice means
*widening* the access level in order to abstract it.

**`DirectInstantiation` has had this exemption for two sweeps.** The two rules fire on the same
seam from opposite ends — the construction site and the declared type — and this was the third
vocabulary one had and the other did not, after `ServiceTypeSuffix` and `MockTypeName`. The walk
now lives in `FileLocalTypeCollector`, shared, which is the only thing that stops a fourth.

The shape it reaches is the single-use accumulator: `ToolInvocation`'s `private struct Builder`,
eight optional fields and no methods, filled by a parsing loop and read once by the initializer
that owns it.

#### Closure wrapper types (8)

A `typealias` for a function type has been exempt for a while, on the reasoning that a property
typed with it is injected by handing in another closure. The same argument holds for the nominal
form, and the corpus prefers the nominal form:

```swift
public struct DateProvider: Sendable {
    private let make: @Sendable () -> Date
    public static let system = Self { Date() }
    public var now: Date { make() }
}
```

A test substitutes it by writing `DateProvider { fixedInstant }` — the same substitution the alias
offers, plus a named production default the alias cannot carry.

**These are seams this sweep itself asked for.** `DateProvider` and `IDProvider` exist because
*Non-Injected Nondeterminism* reported the inline clock and id reads they replaced; its own header
says *"this one is the seam they were moved to"*. Reporting them asked a reader to undo a repair
the same sweep had requested, one rule over.

Exactly one stored property, and it must be function-typed. `static` members are factories over the
type rather than its content, and computed properties are not storage — `var now: Date { make() }`
is the wrapper's whole point and must not disqualify it. Two closures is a small protocol wearing a
struct, and the advice starts being worth hearing again.

#### `Equatable` types (2)

A value is substituted by constructing a different one. Nothing in this corpus that is genuinely a
dependency conforms — a service is identified, not compared — so what the suffix list catches
instead are records that merely *end* in a service word:
`struct EnumCaseGenerator: Sendable, Equatable { let caseName: String }` describes an enum case and
generates nothing. `Hashable` and `Comparable` both refine `Equatable`, so the existing prescan
covers all three spellings and the inline and `extension` forms alike.

### Non-Violating Examples
```swift
// Using a protocol-named type
class Owner {
    var service: NetworkServiceProtocol
    init(service: NetworkServiceProtocol) { self.service = service }
}

// Opaque type
class Owner {
    func foo(service: some NetworkProtocol) { }
}

// DI container — concrete types are correct here
class DependencyContainer {
    var workspaceManager: WorkspaceManager
    var onboardingManager: OnboardingManager
}

// System type — cannot be protocol-abstracted
class Analyzer {
    var fileManager: FileManager
}

// ViewModel in SwiftUI view — concrete type required by property wrappers
struct RuleBrowserView: View {
    var viewModel: RuleBrowserViewModel
    var body: some View { Text("") }
}

// Property wrapper — exempt
struct MyView: View {
    @ObservedObject var viewModel: MyViewModel
    var body: some View { Text("") }
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

### Known Limitations

- **A type written with generic arguments is never reported.** `Generator<[Element], Shrinker>`
  is already parameterised by its use site, and the advice is not available to it in any useful
  form — `any GeneratorProtocol` erases the element type and the shrinker, which is the whole of
  what the type carries. A bare foreign service is different and is still reported: it takes no
  parameters, and wrapping it behind your own protocol is the canonical advice.
- **A `typealias` for a function type is never reported.** `typealias CommandRunner = @Sendable
  ([String]) async throws -> Data` names a closure, and a property typed with it is already
  injected — a test substitutes another closure. Asking for a protocol around it would replace a
  working seam with a heavier one.
- **…but only when the alias is declared in the analyzed sources.** The exemption comes from a
  project-wide prescan, so a property typed with an alias published by *another* package is still
  reported: the declaration that would exempt it is out of scope. Measured — `CLIToolCommandRunner`
  is exempt inside LintStudioUI, which declares it, and still flagged in SwiftLintRuleStudio, which
  imports it. Same boundary as `unused-protocol-abstraction`'s, for the same reason.
- **~~A value type used as a seam still reads as concrete.~~** Closed by the closure-wrapper
  exemption above. The limitation was recorded as *"advice worth refusing rather than a defect the
  rule can detect"* — which was wrong on the second half. It is detectable, by the same prescan
  shape the function-`typealias` exemption already used, and the entry stood for two sweeps because
  nobody asked whether the nominal form of an exempt shape was also exempt.

- **~~A stateless, effect-free type is still reported.~~** Closed by the pure-kernel exemption,
  which is SwiftProjectLint#163 and is shared with `DirectInstantiation` — see
  `CleanInstanceMethodCatalog.isPureKernel(_:)`. It removed four: `PromptBuilder` at three sites
  and `ThinkingAnalyzer` at one.

  **It removed two more that it should not have, and that is the part worth keeping.** The first
  implementation asked whether any stored property was a closure or an existential — a denylist —
  and exempted `PluginPermissionGrantsStore`, which stores a `UserDefaults`, and
  `PersistenceController`, which stores a SwiftData `ModelContainer`. Neither is a closure, an
  existential, or service-suffixed, so no denylist available here would have caught either.

  The method-cleanliness clause did not catch them either. `UserDefaults` *is* one of the purity
  oracle's side-effect markers, but `PluginPermissionGrantsStore.load()` reads
  `defaults.data(forKey: key)` — the stored property's **name**, never its type. **A dependency
  held as storage does not spell its own type in the method that uses it**, so a body-scanning
  oracle cannot see it. The storage test is positive for that reason: a kernel may hold only
  values, and an unrecognised stored type disqualifies.

- **~~`EffectAnnotationParser` is still reported, and the exemption was expected to reach it.~~**
  Checked, and the refusal was wrong **twice over**. The two causes are independent, and neither
  fix alone exempts the type — which is why the first shipped measured at zero.

  **It held a kernel.** Condition (3) accepted a stdlib value type or a project enum as storage
  and refused a project *struct* that is itself a bag of values. `AttributeRecognition` is five
  `Set<String>`; it was admitted, and the parser holding it was not. Storage now resolves to a
  fixpoint, for the reason `SendableProtocols` already gives about refinement chains: one extra
  pass reaches depth two and stops.

  **And four of its methods were recursive.** `resolve` promoted a method only once every method
  it calls was *already* known clean, so a cycle could never start: `combinedDocTrivia`'s
  two-argument overloads call its four-argument one — overloads share a name key, so the name
  calls itself — and `parseEffect` and `resolveDeclEffect` call each other. The loop's comment
  said those *"stay out, correctly"*. **Recursion is not an effect**, and the four refused methods
  are the purest in the file: the deepest one appends `TriviaPiece`s to a local array and returns
  a `Trivia`.

  So the loop runs the other way now — assume every method clean, demote on evidence that owes
  nothing to the assumption — and the old test that pinned the limitation as a requirement is
  replaced by four that pin what actually matters, including that a cycle with an impure member
  still fails.

  **The scope of that fix is much wider than three findings, and the corpus says how much wider.**
  The same catalog decides the property-test census, so every recursive helper had been
  suppressing its callers too. Measured across all 26 repositories, with the two changes swept
  separately so the attribution is not a guess:

  | | Concrete Type Usage | census |
  |---|---|---|
  | run 31 | 18 | 4,572 |
  | + storage fixpoint | 18 | 4,572 |
  | + recursion fix | **15** | **4,661** |

  **89 pure functions this project had never been able to see**, and the storage half contributes
  exactly zero to that column — which is what makes the split measured rather than asserted.
  `Extractable Total Kernel` and `Direct Instantiation` share the machinery and were checked
  rather than assumed: both unmoved.

---
