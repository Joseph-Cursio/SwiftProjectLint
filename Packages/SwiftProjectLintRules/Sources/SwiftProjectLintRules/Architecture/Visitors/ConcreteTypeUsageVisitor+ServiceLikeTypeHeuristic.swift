import Foundation
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

extension ConcreteTypeUsageVisitor {
    // MARK: - Service-like type heuristic

    func extractServiceTypeName(from type: TypeSyntax) -> String? {
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
    struct Exemption {
        let applies: (String) -> Bool
    }

    var exemptions: [Exemption] {
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
            Exemption { self.knownProtocolTypes.contains($0) },
        ]
    }

    /// The fix to offer. An actor reaching this point already conforms to an all-`async`
    /// project protocol — otherwise it would have been exempt — so the abstraction exists and the
    /// suggestion is to use it rather than to define one.
    func suggestion(for typeName: String, asThe position: String) -> String {
        let existing = knownActorTypes.asyncProtocols(conformedToBy: typeName)
        guard !existing.isEmpty else {
            return "Define a protocol for '\(typeName)' and use the protocol as the \(position) type"
        }
        let names = existing.map { "'\($0)'" }.joined(separator: " or ")
        return "Use \(names) as the \(position) type — '\(typeName)' already conforms, and every "
            + "requirement is async, so callers still await"
    }
}
