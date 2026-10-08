[← Back to Rules](RULES.md)

## Concrete Type Usage

**Identifier:** `Concrete Type Usage`
**Category:** Architecture
**Severity:** Info
**Principle:** Dependency Inversion (SOLID)

### Rationale
A function parameter or stored property typed as a concrete service class (e.g., `func configure(service: APIService)`) cannot be substituted with a test double or alternative implementation without modifying the function signature. Protocol abstractions allow callers to pass any conforming type.

### Discussion
`ConcreteTypeUsageVisitor` checks type annotations in function parameters and stored properties (without initializers) — members of a class, struct, enum, actor, protocol or extension, not variables in a code block — for names ending in service-like suffixes (`Manager`, `Service`, `Store`, `Provider`, `Client`, `Repository`, `Handler`, `Controller`, `Factory`, `Adapter`, `ViewModel`, `Coordinator`, `Generator`, `Analyzer`, `Simulator`, `Engine`, `Checker`). It skips types ending in `Protocol`, `Type`, or `Interface` (which are already abstractions), any other protocol the project declares (a project-wide pre-scan, so a role-noun protocol like `OrderStore` needs no suffix), types annotated with a SwiftUI property wrapper, and parameters typed with `some Protocol` (opaque types).

The following patterns are exempt because they do not represent real coupling issues:

- **DI containers** — types whose name ends in `Container`, `Dependencies`, `Composition`, or `Assembly` are composition roots where concrete types are intentional
- **System/Foundation types** — `FileManager`, `NotificationCenter`, `UserDefaults`, `URLSession`, `ProcessInfo`, `Bundle`, etc. cannot reasonably be protocol-abstracted
- **Mock/stub/fake types** — test doubles are concrete by design
- **ViewModels in SwiftUI views** — SwiftUI property wrappers (`@State`, `@ObservedObject`, `@Bindable`) require concrete types, so protocol-abstracting ViewModels in views is impractical
- **Test files** — test code and test helpers use concrete types by necessity
- **SwiftUI property wrapper properties** — `@State`, `@StateObject`, `@ObservedObject`, `@EnvironmentObject`, `@Binding`, `@Published`, `@AppStorage`, `@SceneStorage`, `@Bindable`, `@Environment`
- **Enum types** — a project-wide pre-scan identifies all declared enums; enum-typed parameters and properties are exempt because enums are value types and cannot be protocol-abstracted in the same way as a service class
- **Actor types with no all-`async` protocol** — a project-wide pre-scan identifies every declared actor and the project protocols it conforms to. An actor's serial-executor isolation contract is load-bearing in Swift 6 strict concurrency, and a protocol *can* strip it: a synchronous requirement is satisfiable only by a `nonisolated` member or a `@preconcurrency` conformance, and either way a caller reaches it without `await`. So an actor that conforms to no project protocol, or only to protocols with a synchronous requirement, stays exempt. One that conforms to a project protocol whose every instance requirement is `async` is reported, and the suggestion names that protocol — see [the section below](#actors-that-already-have-an-all-async-protocol)
- **Init parameters mirroring a flagged stored property** — when a stored property is flagged, its matching initializer parameter represents the same coupling point and is suppressed to avoid duplicate reports. A local never counts as that property
- **AppKit and UIKit classes** — recognised by the `NS`/`UI` prefix convention rather than enumerated, and only when the project does not declare a type of that name
- **`private` / `fileprivate` types** — a protocol around one could only be conformed to in the file that declares it
- **Closure wrapper types** — a `struct` or `final class` whose only stored property is a closure is already the seam
- **`Equatable` types** — a value is substituted by constructing a different one
- **Protocols, and the `typealias`es that stand for them** — a project-wide pre-scan identifies every declared protocol, plus every `typealias` that composes protocols (`typealias OrderStore = OrderSaving & OrderHistory`) or renames one. `let store: OrderStore` is already an abstraction; read by its `Store` suffix alone, it was reported as a concrete service
- **A type named inside its own declaration** — a parameter or property typed with `T` inside `T`'s own `class`, `struct`, `enum` or `actor` declaration, an `extension T`, or a type nested in either is `T`'s implementation, not a caller depending on it — see [the section below](#a-type-named-inside-its-own-declaration)
- **A generic parameter in scope** — a parameter or property typed with a generic parameter of an enclosing type, function, initializer or subscript, or with an associated type inside the protocol that declares it, is a placeholder rather than a concrete type — see [the section below](#a-generic-parameter-in-scope)
- **Local and file-scope variables** — a `var` or `let` declared in a function, initializer, accessor or closure body is not a property and not a dependency of anything, and neither is one at file scope; only a member of a type is read — see [the section below](#a-local-variable-is-not-a-property)

Depending on a protocol resolves the issue, whatever the protocol is called. One option is to name the protocol for the role, `protocol APIService`, and rename the class for what it is, such as `URLSessionAPIService`; parameters keep the type name `APIService` (written `any APIService` under `ExistentialAny`), and only construction sites change. A suffixed `APIServiceProtocol` or an opaque `some NetworkProtocol` works too, but a suffixed protocol that copies `APIService` member for member is what [Mirror Protocol](mirror-protocol.md) reports.

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

### Actors that already have an all-`async` protocol

The actor exemption used to cover every actor, on the reasoning that a protocol strips the
isolation contract from every call site. **That holds for some protocols and not others, and the
compiler already tells them apart.**

A protocol *can* strip it. A synchronous requirement is satisfiable only by a `nonisolated` member
or a `@preconcurrency` conformance — Swift 6 rejects an actor-isolated member there, because the
conformance *"crosses into actor-isolated code and can cause data races"* — and either way a caller
reaches that member without `await`. So the exemption stays for an actor that conforms to no project
protocol, or only to protocols with a synchronous requirement.

A protocol whose every instance requirement is `async` cannot. Callers going through it still
`await`, and the conformance cannot quietly weaken that, for the same compiler reason. When the
actor conforms to one, it has already been abstracted with nothing lost, and naming the actor
instead is exactly the coupling this rule is for:

```swift
protocol OrderStore: Sendable {
    func save(_ order: Order) async throws
    func recentOrders() async throws -> [Order]
}
actor CoreDataOrderStore: OrderStore { … }

@MainActor @Observable
final class CheckoutViewModel {
    private let store: CoreDataOrderStore   // ← reported
    init(store: CoreDataOrderStore) { … }   // same coupling point, folded into the line above
}
```

This is Checkout's `solid/d-concrete-dependency` branch, built as a dependency-inversion example,
where the rule stayed silent. It now reports the property, and the suggestion names the protocol
rather than asking for a new one: *"Use 'OrderStore' as the property type — 'CoreDataOrderStore'
already conforms, and every requirement is async, so callers still await"*.

Swift 6.2's isolated conformances (SE-0470) do not change this: a conformance can be isolated to a
*global* actor, not to an `actor` instance, so a synchronous requirement still needs `nonisolated`.

**What counts as all-`async`.** The pre-scan (`ActorTypeCatalog`) joins three facts that are rarely
in one file: the actor, the protocol, and the conformance, which is as often an
`extension CoreDataOrderStore: OrderStore {}` elsewhere. The protocol must be declared in the
analysed sources and not be `private` or `fileprivate`, and it must have at least one `async`
instance requirement and no synchronous one — a `{ get async }` property counts as `async`, and a
`{ get }` one does not. Requirements inherited from other project protocols count, and so does a
`where Self: …` clause. A conformance or refinement written through a composition `typealias`
counts for each protocol it composes: `actor CoreDataOrderStore: OrderStore`, with
`typealias OrderStore = OrderSaving & OrderHistory`, conforms to both roles. Read by the alias's
name, it conformed to nothing the pre-scan knew, and kept its exemption. A parent outside the project counts as synchronous, because its
requirements are not visible here, unless it is a marker that carries none (`Sendable`, `Actor`,
`AnyObject`, and so on). `init`, `static` members and associated types are never isolated to an
instance, so they neither qualify a protocol nor disqualify one; a protocol with nothing else is a
marker, and `any` of it would give a caller nothing to call. An actor conforming to
`CountingOrderStore: OrderStore`, where the child adds a synchronous `count`, still conforms to
`OrderStore` and is reported against it.

**Not inside the actor itself.** An actor named inside its own declaration or one of its
extensions — by its own methods, or by a type nested in it — stays exempt. The protocol exists for
callers, and code inside the actor is its implementation. The corpus showed why:
`swift-aws-lambda-runtime`'s `LambdaRuntimeClient.Writer` holds its owning actor and calls `write`
and `writeAndFinish` on it, while `LambdaRuntimeClientProtocol` offers only `nextInvocation()`.
That was the only finding the narrowing produced besides Checkout's, and nobody could fix it by
abstracting. Classes have the same shape — four Hummingbird findings, a copy initialiser and nested
types holding their owner — which was older than this change and left to its own; that change
[gave every type the guard](#a-type-named-inside-its-own-declaration).

**Measured** with debug CLIs built from `main` and from this change, JSON output,
`--categories architecture`, over the repository root of every sibling Swift repository (35, the
two `_mutated` mutation-testing copies left out). Each repository ran with its own config, plus
three runs with the rule switched on where that config leaves it off: Checkout `main` and the
`solid/d-concrete-dependency` branch under `.swiftprojectlint-solid.yml`, and
SwiftCompilerFlagStudio with the default rules.

| | Concrete Type Usage | other architecture findings |
|---|---|---|
| before | 73 | 286 |
| narrowed | 75 | 286 |
| + not inside the actor itself | **74** | 286 |

The one finding the change adds is Checkout's, and none is removed.

### A type named inside its own declaration

The advice is for a caller, which could name a protocol instead. **Code inside a type's own
declaration is not a caller.** Its methods, its extensions and the types nested in it are the
type's implementation, and they reach members no protocol would carry. A protocol in front of the
type would be conformed to by that one type, for the benefit of that type's own code, so the
finding had no end state to reach.

The guard began with actors, when their exemption was narrowed (above), and stopped there on
purpose: the findings of the same shape for other types were older than that change. All four are
Hummingbird's:

```swift
extension Parser {
    private init(_ parser: Parser, range: Range<Int>) { … }   // a sub-parser over a slice
}
extension Parser: Sequence {
    public struct Iterator: IteratorProtocol {
        var parser: Parser                                    // the parser it walks
    }
}
extension HTTP2ServerConnectionManager {
    struct LoopBoundHandler: @unchecked Sendable {
        let handler: HTTP2ServerConnectionManager             // its owner, to call back into
    }
}
```

The fourth is `HTTP2StreamDelegate`, nested in another extension of the manager and holding its
`handler` the same way. The guard now reads every enclosing `class`, `struct`, `enum` and `actor`
declaration and every `extension`, and skips a parameter or property typed with any of them. The
actor-only version is gone rather than kept beside it.

**An extension of a nested type is read by every component of its name.** `extension
Parser.Iterator` is inside `Parser` exactly as `struct Iterator` written in `Parser`'s body is;
reading only `Iterator` would exempt the property written inline and report it once moved into the
extension. The corpus has no instance of that spelling, so it moved nothing, and a test pins it.

**Only enclosing types count.** Hummingbird's `URI` stores a `Parser` too and is still reported: it
is a caller. So is a type naming a type nested in it — that is the outer type depending on a
helper, not the helper's own implementation.

**Measured** the same way as the actor narrowing above, over the same 38 runs, with debug CLIs
built from `main` and from this change:

| | Concrete Type Usage | other architecture findings |
|---|---|---|
| before | 74 | 284 |
| + every type, not inside itself | **70** | 284 |

The four removed are the four above, and nothing else moved. The other column reads 284 rather than
the actor table's 286 because Direct Instantiation's app-root exemption landed between the two
measurements and took one finding from each Checkout `solid` run; Concrete Type Usage stood at 74 on
both sides of it.

### A generic parameter in scope

The suffix list reads a type's *name*, and a generic parameter has one. Two of the findings that
produced, both Hummingbird's:

```swift
public struct FileMiddleware<Context: RequestContext, Provider: FileProvider>: RouterMiddleware {
    let fileProvider: Provider                // "declares concrete type 'Provider'"
}
public struct EditedResponse<Generator: ResponseGenerator>: ResponseGenerator {
    public var responseGenerator: Generator   // "declares concrete type 'Generator'"
}
```

**Neither is a concrete type.** `Provider` is a placeholder the caller fills, constrained to the
protocol `FileProvider`. That is the abstraction the advice asks for, in its static form: a test
supplies its own conformer as the generic argument, just as it would pass one to an
`any FileProvider`, and needs no existential to do it. The finding asked the author to replace a
protocol-constrained placeholder with a protocol.

The rule now skips a parameter or property whose type is named by a generic parameter in scope,
meaning one declared in the generic parameter clause of *any* enclosing type, function,
initializer or subscript. "Any" matters: a type nested in a generic type sees the outer
parameters, and a method's own clause adds to its type's. Whether the constraint is written inline
or in a `where` clause makes no difference, because the name is what is matched. The negative
controls matter as much. The same name outside that scope can be a concrete type, so
`final class StaticSite { let fileProvider: Provider }` beside `FileMiddleware` is still reported,
and so is a sibling of a generic method that names the method's parameter.

**Associated types count where the declaration is in view.** An associated type is a protocol's
generic parameter. Inside the protocol's own body, `associatedtype Client: TestClientProtocol`
followed by `var client: Client { get }` names a placeholder the conformer fills, and the same walk
reads it off the enclosing protocol. A conforming type is different and is still reported: there,
`Client` names the witness the conformer bound, which is concrete. Inside a protocol *extension*
the name is `Self.Client`, also a placeholder, but the extension does not declare it. Neither does
`extension FileMiddleware` declare `Provider`. That case is left open, and
[Known Limitations](#known-limitations) says why.

**Measured** the same way as the actor narrowing above, over the same 38 runs: debug CLIs built
from `main` and from this change, JSON output, `--categories architecture`, over the repository
root of all 35 sibling Swift repositories, plus Checkout `main` and its
`solid/d-concrete-dependency` branch under `.swiftprojectlint-solid.yml`, and
SwiftCompilerFlagStudio with the default rules. `main` moved while this was measured, so the
measurement was taken twice: once without the self-reference guard above, and once with it.

| | Concrete Type Usage | other architecture findings |
|---|---|---|
| before, without the self-reference guard | 74 | 284 |
| + a generic parameter in scope | 63 | 284 |
| before, with it | 70 | 266 |
| + a generic parameter in scope | **59** | 266 |

The second pair covers 37 runs. With the default-isolation detector, which landed alongside the
guard, the CLI traps on SwiftLint's manifest, both on `main` and on this change, so SwiftLint's 19
other findings are missing from both sides. SwiftLint has no Concrete Type Usage finding, and in
the first pair it moved nothing. The other column also gains one on its own: the SwiftProjectLint
checkout in the corpus moved forward between the pairs and brought one Law of Demeter finding with
it. Both pairs predate the protocol-`typealias` exemption, which cannot reach these eleven: none of
their names is a protocol `typealias` anywhere in the corpus.

The same eleven were removed both times. They are every generic-parameter finding in the corpus,
and nothing else moved:

- **Hummingbird, 3.** The two above, and `Application`'s `init<ResponderBuilder:
  HTTPResponderBuilder>(router: ResponderBuilder, …)`.
- **swift-aws-lambda-runtime, 8.** `LambdaManagedRuntime<Handler>` stores `handler: Handler`, and a
  static method of `LambdaRuntime<Handler>` takes one. `LambdaHandlerAdapter` and
  `LambdaCodableAdapter`, both generic over `Handler`, store one each.
  `Lambda.runLoop<RuntimeClient: LambdaRuntimeClientProtocol, Handler>` takes both, and two
  `LambdaManagedRuntime` convenience initialisers take `lambdaHandler: LHandler`, a parameter of
  their own clause.

No remaining finding is typed with a generic parameter. The corpus declares a service-named generic
parameter or associated type only in those two repositories, in a SwiftUMLStudio view the rule
already skips as SwiftUI, and in test files.

### A local variable is not a property

The rule reads stored properties, and it read every `var` and `let` with a type annotation and no
initializer, wherever one stood. **A local is not a dependency of anything.** It lives for one call,
and no protocol in its annotation would change what the type around it depends on. Hummingbird's
`URI` has both in one type:

```swift
public struct URI {
    private let _scheme: Parser?        // what URI holds — reported
    private let _host: Parser?
    …
    public init(_ string: String) {
        var scheme: Parser?             // a local the parse fills — was reported too
        var host: Parser?
        …
        self._scheme = scheme
    }
}
```

The five stored properties are the coupling and stay reported. The five locals beside them were
reported as `Property 'scheme' declares concrete type 'Parser'`. The sixth was
`swift-aws-lambda-runtime`'s `Deployer.deploy(arguments:)`, which declares
`let credentialProvider: CredentialProviderFactory`, fills it from an `if`/`else`, and passes it
straight to `AWSClient(credentialProvider:)`. Both are the one shape a local could reach the rule
in, because one with an initializer was already skipped: **declared first, filled later**.

**Only a member of a type is read now**, meaning a declaration directly in the member block of a
class, struct, enum, actor, protocol or extension. That includes a type declared inside a function,
and a property behind `#if`, whose clauses keep their declarations as members.

**A file-scope variable is not a member either.** One with no initializer compiles only in top-level
code, the `main.swift` entry point [Direct Instantiation](direct-instantiation.md) exempts because
there is nowhere further out to push construction. A computed one is an accessor, and the rule
reads no return types. **A protocol requirement still counts**: `var store: FeedStore { get }` makes
every conformer expose that service, so the dependency is in the abstraction itself. The corpus has
none of either, so neither choice moved anything.

**A local no longer folds an initializer parameter away.** The fold drops a parameter whose type the
same scope already reported as a stored property, and a reported local counted as one. So a method
declaring a local above `init(cache: CacheManager)` hid that parameter behind a finding that was
itself false. Nothing in the corpus had that shape: no finding was added.

**Measured** the same way as the sections above, over the same 38 runs, with debug CLIs built from
`main` (`f092ec4b`) and from this change:

| | Concrete Type Usage | other architecture findings |
|---|---|---|
| before | 70 | 285 |
| + type members only | **64** | 285 |

The six removed are the six above, and nothing else moved. SwiftLint's run crashes at that `main`
on both binaries, in the manifest reader that Blocking I/O On Main Actor added, before any rule
runs. Its row was taken with CLIs built from the self-reference commit (`1d30f25c`) and from that
commit plus this change, whose architecture rules match `main`'s: 0 → 0 Concrete Type Usage, 19 →
19 other. The other column reads 285 rather than the self-reference table's 284 because the corpus
includes this repository, and that rule brought a Law of Demeter chain in with it.

This predates both the generic-parameter exemption above and the protocol-`typealias` one, and
neither can reach these six: `Parser` and `CredentialProviderFactory` are concrete types, not
generic parameters or protocol aliases. The generic-parameter section's eleven are stored
properties and parameters, none of them a local, so the two changes remove disjoint sets.

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

// Generic parameter — a placeholder the caller fills, not a concrete type
struct FileMiddleware<Provider: FileProvider> {
    let fileProvider: Provider
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

// Actor with no all-async protocol — exempt; a protocol could strip its isolation
actor ImageStore {
    func image(for url: URL) async -> Image? { nil }
}
final class Gallery {
    let store: ImageStore
    init(store: ImageStore) { self.store = store }
}

// A type named inside its own declaration — its implementation, not a caller
struct RequestParser {
    init(_ parser: RequestParser) { }
}
extension RequestParser {
    struct Iterator {
        var parser: RequestParser
    }
}

// A local — declared in a code block, not a member of the type
struct Route {
    init(_ path: String) {
        var segments: SegmentParser?
        segments = SegmentParser(path)
    }
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

// Actor typed concretely beside an all-async protocol it conforms to
protocol OrderStore: Sendable {
    func save(_ order: Order) async throws
}
actor CoreDataOrderStore: OrderStore {
    func save(_ order: Order) async throws { }
}
final class CheckoutViewModel {
    private let store: CoreDataOrderStore  // use 'OrderStore' — callers still await
    init(store: CoreDataOrderStore) { self.store = store }
}
```

### Known Limitations

- **A type written with generic arguments is never reported.** `Generator<[Element], Shrinker>`
  is already parameterised by its use site, and the advice is not available to it in any useful
  form — `any GeneratorProtocol` erases the element type and the shrinker, which is the whole of
  what the type carries. A bare foreign service is different and is still reported: it takes no
  parameters, and wrapping it behind your own protocol is the canonical advice.
- **A type that links to its own kind is not reported.** `final class RequestHandler { var next:
  RequestHandler? }` is a chain of responsibility, and there a protocol *would* have an end state:
  links of different kinds. The self-reference guard cannot tell that from `Parser.Iterator`
  holding the parser it walks — both name the enclosing type from inside it. The corpus has no
  instance; the guard's measurement removed the four Hummingbird findings and nothing else.
- **A `typealias` for a function type is never reported.** `typealias CommandRunner = @Sendable
  ([String]) async throws -> Data` names a closure, and a property typed with it is already
  injected — a test substitutes another closure. Asking for a protocol around it would replace a
  working seam with a heavier one.
- **~~…but only when the alias is declared in the analyzed sources.~~** This was recorded for two
  sweeps as a package boundary — `CLIToolCommandRunner` exempt inside LintStudioUI, which declares
  it, and flagged in SwiftLintRuleStudio and SwiftFormatRuleStudio, which import it.

  It did not have to be a boundary, because **the evidence is local**:

  ```swift
  var bridgedRunner: CLIToolCommandRunner?
  if let commandRunner {
      bridgedRunner = { arguments, _ in … }        // ← only a function type accepts this
  }
  ```

  Assigning a closure literal to a binding *proves* its declared type is a function type — the
  compiler rejects it otherwise. That is a fact rather than a heuristic, and it holds whoever
  declares the alias and wherever. The prescan now records both shapes: a declaration initialised
  with a closure, and a declaration filled by a later assignment in the same body. Measured:
  SwiftLintRuleStudio 2 → 1 and SwiftFormatRuleStudio 3 → 2, and nothing else moved.

  Scoped to one function or initializer body, so an unrelated `runner` elsewhere in the file cannot
  lend its name to a type it has nothing to do with. A nested shadow inside the same body could
  still mislead; that residual is worth less than the boundary it removes. **The test that matters
  is the negative one** — `client = OllamaHTTPClient(baseURL: url)` is an assignment too, and
  keying on the assignment rather than on the assigned *value* would have exempted every service
  built in an initializer.
- **~~A value type used as a seam still reads as concrete.~~** Closed by the closure-wrapper
  exemption above. The limitation was recorded as *"advice worth refusing rather than a defect the
  rule can detect"* — which was wrong on the second half. It is detectable, by the same prescan
  shape the function-`typealias` exemption already used, and the entry stood for two sweeps because
  nobody asked whether the nominal form of an exempt shape was also exempt.

- **~~A stateless, effect-free type is still reported.~~** Closed by the pure-kernel exemption,
  which is SwiftProjectLint#163 and is shared with `DirectInstantiation` — see
  `CleanInstanceMethodCatalog.isPureKernel(_:)`. It removed four: `PromptBuilder` at three sites
  and `ThinkingAnalyzer` at one. Its purity test now sees what constructing a package type runs, so
  a type whose method builds an identity-minting value stops qualifying; on the seven repositories
  re-measured when that was wired, no finding moved. So enabling this rule builds the construction
  universe, the facts and the clean-method catalog, even in a run narrowed to it.

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

- **A generic parameter or associated type named inside an extension is still reported.**
  `extension FileMiddleware { func serve(from provider: Provider) }` has the type's `Provider` in
  scope, and `extension ApplicationTester { func reset(_ client: Client) }` has the protocol's
  `Client`. Neither extension declares the name. The declaration that does is usually in another
  file, so recognising it would take a project-wide catalog of every type's generic parameters and
  every protocol's associated types, threaded through the pre-scan like the others. A protocol
  extension is no exception: only the protocol's own body is covered.

  **The corpus has no instance.** None of the eleven generic-parameter findings was in an
  extension, and no remaining finding is typed with a generic parameter, so the catalog would move
  nothing today. Its one associated type with a service name, Hummingbird's `associatedtype Client`
  in `ApplicationTester`, is in a test target the rule skips. A test pins the current behaviour, so
  the change that adds the catalog updates it on purpose.

---
