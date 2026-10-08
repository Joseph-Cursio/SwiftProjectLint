import Foundation
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects type annotations using concrete service-like types
/// where a protocol abstraction would improve testability and reduce coupling.
class ConcreteTypeUsageVisitor: BasePatternVisitor {
    private var currentFilePath: String = ""

    /// Whether the current struct/class looks like a DI container.
    private var isInsideDIContainer: Bool = false

    /// Concrete type names already flagged as stored properties in the current type scope.
    /// Used to suppress the matching init parameter hit — the property and its init
    /// parameter are the same coupling point and should only be reported once.
    private var flaggedPropertyTypes: Set<String> = []

    /// Whether the visitor is currently inside an initializer body.
    private var isInsideInitializer: Bool = false

    /// Names of the types this file declares `private` or `fileprivate`, gathered in one pass
    /// before any finding is reported. No project-wide prescan is needed and none would help:
    /// a file-local type is unreachable outside its own file, so the declaration is always here
    /// if it is anywhere.
    private var fileLocalTypes: Set<String> = []

    /// Foundation / system types that are concrete by design and cannot
    /// reasonably be protocol-abstracted.
    ///
    /// Hand-maintained because Swift 3 dropped the `NS` prefix from Foundation, so there is no
    /// convention left to read these off. `appKitOrUIKitPrefixes` covers the two frameworks that
    /// kept theirs.
    private static let systemConcreteTypes: Set<String> = [
        "FileManager", "NotificationCenter", "UserDefaults",
        "URLSession", "ProcessInfo", "Bundle",
        "UNUserNotificationCenter", "NSWorkspace"
    ]

    /// AppKit and UIKit kept their prefixes, so their class names can be recognised by
    /// convention rather than enumerated.
    ///
    /// This is the list above, expressed as the rule that generates it. `NSLayoutManager` is a
    /// system type of exactly the kind `FileManager` is; it was reported only because nobody had
    /// hit it before and added it by hand. Growing a list one name per sweep is the arbitrary
    /// half of the choice this rule already refuses elsewhere.
    ///
    /// **Restricted to `NS` and `UI` deliberately.** The obvious generalisation — every Apple
    /// two-letter prefix — is refuted by this corpus: `CLIToolCommandRunner` begins with `CL`
    /// followed by an uppercase letter, so a `CoreLocation` prefix would have silenced it for a
    /// reason that has nothing to do with why it should be silent. Two prefixes cover every
    /// instance the corpus has; the rest can be added when something needs them.
    ///
    /// Paired with `knownLocalTypeNames`, so a project that declares its own `UIStateManager`
    /// keeps the finding. The declaration is what decides, not the spelling.
    private static let appKitOrUIKitPrefixes = ["NS", "UI"]

    func isPlatformFrameworkType(_ name: String) -> Bool {
        guard !knownLocalTypeNames.contains(name) else { return false }
        return Self.appKitOrUIKitPrefixes.contains { prefix in
            name.count > prefix.count
                && name.hasPrefix(prefix)
                && name[name.index(name.startIndex, offsetBy: prefix.count)].isUppercase
        }
    }

    /// Type-name suffixes that indicate a DI container or composition root,
    /// where holding concrete types is the whole point.
    private static let diContainerSuffixes = [
        "Container", "Dependencies", "Composition", "Assembly"
    ]

    /// Type-name suffixes indicating a mock/stub/fake, which are concrete by design.
    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        self.currentFilePath = filePath
    }

    // MARK: - File-local access-level pre-pass

    override func visit(_ node: SourceFileSyntax) -> SyntaxVisitorContinueKind {
        let collector = FileLocalTypeCollector(viewMode: .sourceAccurate)
        collector.walk(node)
        fileLocalTypes = collector.names
        return .visitChildren
    }

    // MARK: - Scope tracking

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        isInsideDIContainer = Self.diContainerSuffixes.contains { node.name.text.hasSuffix($0) }
        flaggedPropertyTypes = []
        return .visitChildren
    }

    override func visitPost(_ _: StructDeclSyntax) {
        isInsideDIContainer = false
        flaggedPropertyTypes = []
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        isInsideDIContainer = Self.diContainerSuffixes.contains { node.name.text.hasSuffix($0) }
        flaggedPropertyTypes = []
        return .visitChildren
    }

    override func visitPost(_ _: ClassDeclSyntax) {
        isInsideDIContainer = false
        flaggedPropertyTypes = []
    }

    override func visit(_ _: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        isInsideDIContainer = false
        flaggedPropertyTypes = []
        return .visitChildren
    }

    override func visitPost(_ _: ActorDeclSyntax) {
        flaggedPropertyTypes = []
    }

    override func visit(_ _: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        isInsideInitializer = true
        return .visitChildren
    }

    override func visitPost(_ _: InitializerDeclSyntax) {
        isInsideInitializer = false
    }

    // MARK: - Service-like type heuristic

    private func extractServiceTypeName(from type: TypeSyntax) -> String? {
        // Direct: NetworkService
        if let identifier = type.as(IdentifierTypeSyntax.self) {
            return qualifying(identifier)
        }
        // Optional: NetworkService?
        if let opt = type.as(OptionalTypeSyntax.self),
           let identifier = opt.wrappedType.as(IdentifierTypeSyntax.self) {
            return qualifying(identifier)
        }
        // Implicitly unwrapped: NetworkService!
        if let iuo = type.as(ImplicitlyUnwrappedOptionalTypeSyntax.self),
           let identifier = iuo.wrappedType.as(IdentifierTypeSyntax.self) {
            return qualifying(identifier)
        }
        return nil
    }

    /// A type written with generic arguments is already parameterised by its use site, and
    /// "prefer a protocol abstraction" is not available to it in any useful form: replacing
    /// `Generator<[Element], Shrinker>` with `any GeneratorProtocol` erases the element type and
    /// the shrinker, which is the whole of what the type was carrying. That is a loss, not an
    /// abstraction.
    ///
    /// This is what a bare foreign service does not have. `Alamofire.Session` takes no
    /// parameters and wrapping it behind your own protocol is the canonical advice; the rule
    /// still gives it.
    ///
    /// Measured on SwiftPropertyLaws, whose every law takes a generator: 215 of its 218
    /// findings named `Generator`, and 263 of the 267 uses in that package carry generic
    /// arguments.
    func qualifying(_ identifier: IdentifierTypeSyntax) -> String? {
        guard identifier.genericArgumentClause == nil else { return nil }
        return qualifying(identifier.name.text)
    }

    /// Returns the name if it's service-like and not a protocol indicator, else nil.
    ///
    /// The exemptions are a table rather than a ladder of `if`s. They grew past
    /// `cyclomatic_complexity` when the seam gates were added, and a ladder of nine independent
    /// early returns has no ordering to read anyway — every one of them is "this is not a
    /// concrete dependency", and none depends on another having run first. Each reason carries
    /// the argument for it, because the argument is the part worth keeping.
    private func qualifying(_ name: String) -> String? {
        guard name.first?.isUppercase == true,
              ServiceTypeSuffix.matches(name),
              !name.hasSuffix("Protocol"),
              !name.hasSuffix("Type"),
              !name.hasSuffix("Interface")
        else { return nil }

        let exempt = exemptions.contains { $0.applies(name) }
        return exempt ? nil : name
    }

    /// One reason a service-like name is not a concrete dependency.
    private struct Exemption {
        let applies: (String) -> Bool
    }

    private var exemptions: [Exemption] {
        [
            // A `typealias` for a function type is already the seam. `CLIToolCommandRunner =
            // @Sendable ([String], Data?) async throws -> (Data, Data, Int32)` is a closure: a
            // property typed with it is injected by handing in another closure, which is what a
            // test does. Asking for a protocol around it replaces a working seam with a heavier
            // one. Requires the project-wide typealias prescan.
            Exemption { self.knownFunctionTypeAliases.contains($0) },

            // Foundation types that are concrete by design.
            Exemption { Self.systemConcreteTypes.contains($0) },

            // AppKit / UIKit classes, recognised by the prefix convention rather than by name.
            // `NSLayoutManager` and `UIImagePickerController` are system types in exactly the
            // sense the list above means, and most of the corpus's instances are worse than
            // merely unabstractable: they are parameters of protocol requirements — a
            // `UIImagePickerControllerDelegate` callback, a `UIViewControllerRepresentable`'s
            // `updateUIViewController` — where the signature is not the author's to change.
            Exemption { self.isPlatformFrameworkType($0) },

            // Mock/stub/fake types. Shared with `DirectInstantiation` via `MockTypeName`.
            Exemption { MockTypeName.matches($0) },

            // Enum types — value types that cannot meaningfully be protocol-abstracted in the
            // same way as a service class. Requires the project-wide enum prescan.
            Exemption { self.knownEnumTypes.contains($0) },

            // Actor types, until the project has already abstracted one without losing anything.
            // An actor's isolation contract is load-bearing in Swift 6 strict concurrency, and a
            // protocol *can* strip it: a synchronous requirement is satisfiable only by a
            // `nonisolated` member or a `@preconcurrency` conformance, and either way a caller
            // reaches it without `await`.
            //
            // A project protocol whose every instance requirement is `async` cannot. Callers
            // through it still `await`, and Swift 6 rejects an actor-isolated member satisfying a
            // synchronous requirement, so the conformance cannot quietly weaken that. When the
            // actor conforms to one, naming the actor instead is the coupling this rule reports —
            // and the suggestion names the protocol. Reported against Checkout's
            // `CheckoutViewModel`, which stored `CoreDataOrderStore` beside an `OrderStore` whose
            // two requirements are both `async`. Requires the project-wide actor prescan.
            Exemption {
                self.knownActorTypes.contains($0)
                    && self.knownActorTypes.asyncProtocols(conformedToBy: $0).isEmpty
            },

            // @Observable / ObservableObject types — protocol-abstracting a SwiftUI observation
            // model severs change tracking: through `any SomeProtocol` the view can no longer see
            // the concrete observable storage and stops re-rendering. The concrete type is
            // load-bearing. Requires the project-wide observable prescan.
            Exemption { self.knownObservableTypes.contains($0) },

            // A `private` or `fileprivate` type cannot be substituted: no caller outside the file
            // that declares it can name the type, so a protocol around it could only ever be
            // conformed to there, and no test could supply an alternative conformer. Taking the
            // advice would mean *widening* the access level in order to abstract it — exporting
            // an implementation detail to make it substitutable, which is the opposite trade from
            // the one the rule offers.
            //
            // `DirectInstantiation` — this rule's twin, firing on the same seam from the
            // construction site rather than the declared type — has had this exemption since the
            // shape was found there. The two share `ServiceTypeSuffix` and `MockTypeName` for the
            // same reason and after the same kind of mistake; this was the third vocabulary one
            // of them had and the other did not, which is why the walk now lives in
            // `FileLocalTypeCollector` rather than in either.
            //
            // The shape it reaches is the single-use accumulator: `ToolInvocation`'s
            // `private struct Builder`, eight optional fields and no methods, filled by a parsing
            // loop and read once by the initializer that owns it.
            Exemption { self.fileLocalTypes.contains($0) },

            // A value type whose whole content is one closure is already the seam, exactly as a
            // `typealias` for a function type is. `struct DateProvider { let make: () -> Date }`
            // is substituted by handing in another closure — `DateProvider { fixedInstant }` —
            // and its own header says so: *"this one is the seam they were moved to"*. Asking for
            // a protocol around it replaces a working seam with a heavier one, and would undo the
            // repair `Non-Injected Nondeterminism` asked for in the first place.
            //
            // The nominal form is if anything better than the alias: it can carry named
            // factories, and `DateProvider.system` is the one place in its package allowed to
            // read a clock. Requires the project-wide closure-wrapper prescan.
            Exemption { self.knownClosureWrapperTypes.contains($0) },

            // An `Equatable` type is a value, and a value is substituted by constructing a
            // different one. Nothing in this corpus that is genuinely a dependency conforms:
            // a service is identified, not compared. What the suffix list catches instead are
            // records that merely *end* in a service word —
            // `struct EnumCaseGenerator: Sendable, Equatable { let caseName: String }` describes
            // an enum case and generates nothing; `ComposedGenerator` wraps a plan value.
            //
            // `Hashable` and `Comparable` both refine `Equatable`, so the prescan's set already
            // covers all three spellings and the inline and `extension` forms alike.
            Exemption { self.knownEquatableTypes.contains($0) },

            // A type that holds nothing a test could not supply. `PromptBuilder` has no stored
            // properties and one pure method; `EffectAnnotationParser` stores a single value
            // struct of attribute-name sets its own documentation says to reconfigure. A protocol
            // in front of either is a seam around a pure function — the opposite of what this
            // sweep is for.
            //
            // The oracle that decides this was already running project-wide with no rule
            // consulting it (SwiftProjectLint#163). It is shared with `DirectInstantiation`,
            // which asks the same question from the construction site.
            Exemption { self.knownCleanInstanceMethods.isPureKernel($0) },

            // Protocol types — already an abstraction. A protocol used as a bare existential
            // (`let provider: ResourceMetricsProvider`) is not a concrete dependency, but the
            // name-based check above only recognises the `Protocol`/`Type`/`Interface` naming
            // conventions. The project-wide protocol prescan catches the rest, so we don't tell
            // users to "prefer a protocol abstraction" for something that already is one.
            // The prescan includes the `typealias`es standing for protocols, so
            // `let store: OrderStore` with `typealias OrderStore = OrderSaving & OrderHistory`
            // is not reported either: `Store` is a service suffix, and the alias read as one.
            Exemption { self.knownProtocolTypes.contains($0) }
        ]
    }

    /// The fix to offer. An actor reaching this point already conforms to an all-`async`
    /// project protocol — otherwise it would have been exempt — so the abstraction exists and the
    /// suggestion is to use it rather than to define one.
    private func suggestion(for typeName: String, asThe position: String) -> String {
        let existing = knownActorTypes.asyncProtocols(conformedToBy: typeName)
        guard !existing.isEmpty else {
            return "Define a protocol for '\(typeName)' and use the protocol as the \(position) type"
        }
        let names = existing.map { "'\($0)'" }.joined(separator: " or ")
        return "Use \(names) as the \(position) type — '\(typeName)' already conforms, and every "
            + "requirement is async, so callers still await"
    }

    // MARK: - Property wrapper detection

    // The shared state-storage set plus two this rule also treats as wrapped
    // properties: `@Environment` (a typed `PropertyWrapper` case) and `@Bindable`
    // (Observation's wrapper, with no SwiftUI-state enum case of its own).
    private static let propertyWrapperNames: Set<String> =
        PropertyWrapper.stateStorageAttributeNames
            .union([PropertyWrapper.environment.rawValue, "Bindable"])

    func hasPropertyWrapper(_ node: VariableDeclSyntax) -> Bool {
        for attribute in node.attributes {
            if let attr = attribute.as(AttributeSyntax.self),
               let name = attr.attributeName.as(IdentifierTypeSyntax.self)?.name.text,
               Self.propertyWrapperNames.contains(name) {
                return true
            }
        }
        return false
    }

    // MARK: - Common exemptions

    private func shouldSkipFile() -> Bool {
        // Test files and test helpers use concrete types by necessity
        currentFilePath.contains("Test")
    }

    private func isInsideSwiftUIView(_ node: some SyntaxProtocol) -> Bool {
        // Walk up to find the enclosing struct and check for View conformance
        var current = Syntax(node)
        while let parent = current.parent {
            if let structDecl = parent.as(StructDeclSyntax.self) {
                return isSwiftUIView(structDecl)
            }
            current = parent
        }
        return false
    }

    /// Whether `typeName` is named from inside its own declaration or one of its extensions — by
    /// its own methods, or by a type nested in it.
    ///
    /// The advice is for a *caller*, which could name an abstraction instead. Code inside the type
    /// is not a caller: it is the type's own implementation, and it reaches members a protocol
    /// would never carry. Hummingbird's `Parser` takes another `Parser` in a sub-parser
    /// initialiser and its nested `Iterator` holds the parser it walks;
    /// `HTTP2ServerConnectionManager`'s nested `LoopBoundHandler` and `HTTP2StreamDelegate` hold
    /// their owner to call back into it. A protocol in front of any of them would be conformed to
    /// by the one type, for the benefit of that type's own code.
    ///
    /// This began as an actor-only guard, when the actor exemption was narrowed to report an actor
    /// beside an all-`async` protocol: `swift-aws-lambda-runtime`'s `LambdaRuntimeClient.Writer`
    /// holds its owning actor and calls `write` and `writeAndFinish` on it, which
    /// `LambdaRuntimeClientProtocol` does not offer. The four Hummingbird findings were the same
    /// shape, older, and the reason holds for every kind of type.
    private func isNamedInsideItself(_ typeName: String, _ node: some SyntaxProtocol) -> Bool {
        var current = Syntax(node)
        while let parent = current.parent {
            if implementedTypeNames(of: parent).contains(typeName) { return true }
            current = parent
        }
        return false
    }

    /// The types whose implementation the body of `node` is: the type it declares, or the type it
    /// extends together with every type that one is nested in. Empty for any other node.
    private func implementedTypeNames(of node: Syntax) -> [String] {
        if let decl = node.as(ClassDeclSyntax.self) { return [decl.name.text] }
        if let decl = node.as(StructDeclSyntax.self) { return [decl.name.text] }
        if let decl = node.as(EnumDeclSyntax.self) { return [decl.name.text] }
        if let decl = node.as(ActorDeclSyntax.self) { return [decl.name.text] }
        if let decl = node.as(ExtensionDeclSyntax.self) {
            return qualifiedNameComponents(of: decl.extendedType)
        }
        return []
    }

    /// `Parser.Iterator` as `["Parser", "Iterator"]`. An extension of a nested type is inside the
    /// type it is nested in, exactly as the nested declaration is; reading only the last component
    /// would exempt `struct Iterator { var parser: Parser }` written inside `Parser` and report
    /// the same property moved to `extension Parser.Iterator`.
    private func qualifiedNameComponents(of type: TypeSyntax) -> [String] {
        if let identifier = type.as(IdentifierTypeSyntax.self) { return [identifier.name.text] }
        if let member = type.as(MemberTypeSyntax.self) {
            return qualifiedNameComponents(of: member.baseType) + [member.name.text]
        }
        return []
    }

    /// Whether `typeName` names a generic parameter or an associated type that an enclosing
    /// declaration introduces: the generic parameter clause of a type, function, initializer or
    /// subscript, or the body of the protocol that declares the associated type.
    ///
    /// Such a name is not a concrete type at all. In `struct FileMiddleware<Context:
    /// RequestContext, Provider: FileProvider>`, `Provider` is a placeholder the caller fills,
    /// constrained to the protocol `FileProvider`. So `let fileProvider: Provider` is already the
    /// abstraction the advice asks for, and a test substitutes its own conformer as the generic
    /// argument. The suffix list read the placeholder's name as if it were a class's: Hummingbird's
    /// `FileMiddleware.fileProvider` and `EditedResponse<Generator:
    /// ResponseGenerator>.responseGenerator` were both reported.
    ///
    /// Every enclosing declaration counts, not only the nearest. A type nested in a generic type
    /// sees its outer parameters, and a method's own clause adds to its type's. An extension is not
    /// read: it has no clause of its own, and the declaration that introduces the names in scope
    /// there — the extended type's clause, or the extended protocol's associated types — is in
    /// whichever file declares it. `isNamedInsideItself` can read extensions because the name it
    /// needs is in the extension's own header; the names needed here are not.
    private func isGenericParameterInScope(_ typeName: String, _ node: some SyntaxProtocol) -> Bool {
        var current = Syntax(node)
        while let parent = current.parent {
            if abstractTypeNames(introducedBy: parent).contains(typeName) { return true }
            current = parent
        }
        return false
    }

    /// The generic parameters `node` declares, or the associated types of a protocol. Empty for
    /// any other node.
    private func abstractTypeNames(introducedBy node: Syntax) -> [String] {
        if let decl = node.asProtocol(WithGenericParametersSyntax.self) {
            return decl.genericParameterClause?.parameters.map(\.name.text) ?? []
        }
        if let decl = node.as(ProtocolDeclSyntax.self) {
            return decl.memberBlock.members.compactMap {
                $0.decl.as(AssociatedTypeDeclSyntax.self)?.name.text
            }
        }
        return []
    }

    // MARK: - Function/initializer parameters

    override func visit(_ node: FunctionParameterSyntax) -> SyntaxVisitorContinueKind {
        if shouldSkipFile() || isInsideDIContainer { return .visitChildren }
        // Skip opaque types (some Protocol)
        if node.type.is(SomeOrAnyTypeSyntax.self) {
            return .visitChildren
        }
        // A generic parameter is the abstraction the advice asks for, not a concrete type.
        guard let typeName = extractServiceTypeName(from: node.type),
              !isGenericParameterInScope(typeName, node)
        else {
            return .visitChildren
        }
        // Skip all concrete types in SwiftUI views — @Observable requires
        // concrete types for SwiftUI's observation tracking to work — and a type named
        // inside its own declaration.
        if isInsideSwiftUIView(node) || isNamedInsideItself(typeName, node) {
            return .visitChildren
        }
        // Suppress init parameters whose type was already flagged as a stored property
        // in this type scope — the property and its init parameter are the same coupling
        // point and should only be reported once.
        if isInsideInitializer, flaggedPropertyTypes.contains(typeName) {
            return .visitChildren
        }
        let paramName = node.firstName.text
        addIssue(
            severity: .info,
            message: "Parameter '\(paramName)' uses concrete type '\(typeName)' — prefer a protocol abstraction",
            filePath: currentFilePath,
            lineNumber: getLineNumber(for: Syntax(node)),
            suggestion: suggestion(for: typeName, asThe: "parameter"),
            ruleName: .concreteTypeUsage
        )
        return .visitChildren
    }

    // MARK: - Stored properties with type annotations

    /// Whether `node` is a member of a type — a class, struct, enum, actor, protocol or extension,
    /// including one declared inside a function — rather than a variable in a code block.
    ///
    /// A local is not a dependency of anything. Hummingbird's `URI.init(_:)` fills
    /// `var scheme: Parser?` and four siblings while it parses, then copies them into the stored
    /// `_scheme` and its siblings. The stored five are the coupling, and are reported; the five
    /// locals were reported beside them, and no protocol changes what a local is. Counting one
    /// also let it fold away a later initializer parameter of its type, as though it were the
    /// stored property that parameter fills.
    ///
    /// A file-scope variable is not a member either. One without an initializer compiles only in
    /// top-level code — `main.swift`, the entry point `DirectInstantiation` exempts — and a
    /// computed one is an accessor, whose return type this rule does not read anywhere else.
    ///
    /// A protocol's member block counts: a requirement typed with a concrete service makes every
    /// conformer expose that service, which is a dependency of the abstraction itself. And `#if`
    /// inside a member block keeps its clauses' declarations wrapped as members, so a property
    /// behind a platform check is still read.
    private func isTypeMember(_ node: VariableDeclSyntax) -> Bool {
        node.parent?.is(MemberBlockItemSyntax.self) == true
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        if shouldSkipFile() || isInsideDIContainer || !isTypeMember(node) { return .visitChildren }
        // Skip if property has a reactive/injection wrapper
        if hasPropertyWrapper(node) {
            return .visitChildren
        }

        for binding in node.bindings {
            guard let typeAnnotation = binding.typeAnnotation else { continue }
            // Skip if there's also a service-like initializer (caught by DirectInstantiationVisitor)
            if binding.initializer != nil { continue }

            // A generic parameter is the abstraction the advice asks for, not a concrete type.
            guard let typeName = extractServiceTypeName(from: typeAnnotation.type),
                  !isGenericParameterInScope(typeName, node)
            else { continue }
            // Skip all concrete types in SwiftUI views — @Observable requires
            // concrete types for SwiftUI's observation tracking to work — and a type named
            // inside its own declaration.
            if isInsideSwiftUIView(node) || isNamedInsideItself(typeName, node) {
                continue
            }
            let propName: String
            if let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                propName = pattern.identifier.text
            } else {
                propName = "property"
            }
            flaggedPropertyTypes.insert(typeName)
            addIssue(
                severity: .info,
                message: "Property '\(propName)' declares concrete type '\(typeName)' — prefer a protocol abstraction",
                filePath: currentFilePath,
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: suggestion(for: typeName, asThe: "property"),
                ruleName: .concreteTypeUsage
            )
        }
        return .visitChildren
    }
}
