import SwiftSyntax

/// Collects value types whose entire content is a single closure — the nominal spelling of a
/// function `typealias`, and an injection seam already.
///
/// ## Why this exists
///
/// `ConcreteTypeUsage` already exempts a property typed with a function `typealias`:
/// `CLIToolCommandRunner = @Sendable ([String]) async throws -> Data` names a closure, so a
/// property typed with it is injected by handing in another closure, and asking for a protocol
/// around it replaces a working seam with a heavier one.
///
/// The same argument holds for the nominal form, and the corpus prefers the nominal form:
///
/// ```swift
/// public struct DateProvider: Sendable {
///     private let make: @Sendable () -> Date
///     public static let system = Self { Date() }
/// }
/// ```
///
/// A test substitutes it by writing `DateProvider { fixedInstant }`. That is the same
/// substitution the alias offers, plus something the alias cannot do: a named production
/// default, which is why `DateProvider.system` can be *the one place in its package allowed to
/// read a clock*.
///
/// **These are seams the sweep itself asked for.** `DateProvider` and `IDProvider` exist because
/// `Non-Injected Nondeterminism` reported the inline clock and id reads they replaced. Reporting
/// the replacement as a concrete dependency asks a reader to undo the repair — the two rules
/// disagreeing about the same line, one run apart.
///
/// ## What counts
///
/// A `struct` or `final class` with **exactly one stored property**, whose declared type is a
/// function type. Computed properties are not stored and do not count; neither do `static`
/// members, which is what lets a type carry `.system` and `.random` factories and still qualify.
///
/// Deliberately strict. Two closures is a small protocol wearing a struct, and the advice starts
/// being worth hearing again; one is a named closure.
public struct ClosureWrapperTypeCatalog: Sendable, Equatable {

    private let names: Set<String>

    /// The catalog a caller with no pre-scan gets: nothing is a closure wrapper, so behaviour
    /// matches the rule as it was before the catalog existed.
    public static let empty = Self(names: [])

    public init(names: Set<String>) {
        self.names = names
    }

    /// Whether `name` is one of them.
    ///
    /// **Named `wraps` rather than `contains` on purpose, and the reason is measured.** While it
    /// was `contains(_:)`, that labelled name entered `knownProjectFunctions` — and
    /// `PureClosureCandidateVisitor`'s forwarding check suppresses any single-expression closure
    /// calling a project-declared name, keying on the *member* name plus labels. So a one-line
    /// method here silenced every closure in the package that calls `.contains(…)`:
    /// `{ stylingModifierNames.contains($0) }`, `{ $0.description.contains("#Preview") }`, and 47
    /// others. **The closure census went 249 → 200 because of this method's name**, measured both
    /// ways.
    ///
    /// The rename is a workaround and is recorded as one — the defect is that the forwarding check
    /// resolves a callee by bare name through a member access, which `PackagePurityJoin` in this
    /// same package already refuses to do and documents at length. Filed as SwiftProjectLint#185.
    public func wraps(_ name: String) -> Bool { names.contains(name) }

    public var isEmpty: Bool { names.isEmpty }

    /// Builds the catalog over every parsed source in the project.
    public static func build(from sources: [SourceFileSyntax]) -> Self {
        var found: Set<String> = []
        for source in sources {
            let collector = ClosureWrapperTypeCollector(viewMode: .sourceAccurate)
            collector.walk(source)
            found.formUnion(collector.names)
        }
        return Self(names: found)
    }
}

/// Walks one file for the shape ``ClosureWrapperTypeCatalog`` describes.
public final class ClosureWrapperTypeCollector: SyntaxVisitor {

    private(set) var names: Set<String> = []

    override public func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        record(node.name.text, node.memberBlock)
        return .visitChildren
    }

    override public func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        // A non-final class can be subclassed, which is a substitution route of its own; the
        // exemption is about types that offer no route but the closure.
        let isFinal = node.modifiers.contains { $0.name.tokenKind == .keyword(.final) }
        if isFinal { record(node.name.text, node.memberBlock) }
        return .visitChildren
    }

    private func record(_ name: String, _ memberBlock: MemberBlockSyntax) {
        var storedTypes: [TypeSyntax] = []
        for member in memberBlock.members {
            guard let variable = member.decl.as(VariableDeclSyntax.self) else { continue }
            // A `static` member is not the type's content — it is a factory over it, and
            // `DateProvider.system` is exactly why one has to be allowed.
            if variable.modifiers.contains(where: { $0.name.tokenKind == .keyword(.static) }) {
                continue
            }
            for binding in variable.bindings {
                // Computed properties are not storage. `var now: Date { make() }` is the
                // wrapper's whole point and must not disqualify it.
                guard binding.accessorBlock == nil,
                      let type = binding.typeAnnotation?.type else { continue }
                storedTypes.append(type)
            }
        }
        guard storedTypes.count == 1, Self.isFunctionType(storedTypes[0]) else { return }
        names.insert(name)
    }

    /// Whether `type` is a function type, seeing through the wrappers a closure is declared
    /// with. An optional wraps a *parenthesised* function type, which parses as a one-element
    /// tuple, so the tuple case is what makes the optional spelling work.
    static func isFunctionType(_ type: TypeSyntax) -> Bool {
        if type.is(FunctionTypeSyntax.self) { return true }
        if let attributed = type.as(AttributedTypeSyntax.self) {
            return isFunctionType(attributed.baseType)
        }
        if let optional = type.as(OptionalTypeSyntax.self) {
            return isFunctionType(optional.wrappedType)
        }
        if let tuple = type.as(TupleTypeSyntax.self), tuple.elements.count == 1,
           let only = tuple.elements.first {
            return isFunctionType(only.type)
        }
        return false
    }
}
