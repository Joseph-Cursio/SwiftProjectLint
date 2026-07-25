import SwiftParser
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// Candidacy for **computed properties** — the shape the seeding path could not
/// see at all until now.
///
/// A get-only computed property is a nullary function of `self`:
/// `allCases.map(\.suppressionKey)` is exactly what a property test wants, and
/// this project's own `RuleIdentifier` carries two of them. The seeding path was
/// `FunctionDeclSyntax`-only, so every computed property in every scanned project
/// was dropped *before* candidacy was asked, however testable it was. The purity
/// oracle had answered for accessors all along; nothing above it ever asked.
///
/// ## Two refuters sat behind the missing overload
///
/// Wiring the visitor alone would have reached neither of the two motivating
/// properties, which is why they are pinned here explicitly:
///
/// - `category` is `switch self` — and the getter path hard-coded bare `self` as
///   disqualifying, even though `instanceShape` already treats it as a read for a
///   value type. `self` IS the value a test constructs.
/// - `suppressionKey` reads `rawValue`, which is `RawRepresentable`'s synthesised
///   accessor rather than a declared stored property, so it fell through to the
///   assume-the-dangerous-one branch.
@Suite
struct ComputedPropertyCandidacyTests {

    /// Every computed property declared in `source`, in source order.
    private func properties(in source: String) -> [(name: String, decl: VariableDeclSyntax)] {
        var found: [(String, VariableDeclSyntax)] = []
        func walk(_ node: Syntax) {
            if let declaration = node.as(VariableDeclSyntax.self),
               let binding = declaration.bindings.first,
               binding.accessorBlock != nil {
                found.append((binding.pattern.trimmedDescription, declaration))
            }
            for child in node.children(viewMode: .sourceAccurate) { walk(child) }
        }
        walk(Syntax(Parser.parse(source: source)))
        return found.map { (name: $0.0, decl: $0.1) }
    }

    private func candidate(
        _ source: String,
        named name: String,
        equatable: Set<String> = ["PatternCategory"],
        valueTypes: Set<String> = ["RuleIdentifier"]
    ) -> PropertyTestCandidate? {
        guard let match = properties(in: source).first(where: { $0.name == name }) else { return nil }
        return PropertyTestCandidacy.candidate(
            of: match.decl,
            knownEquatableTypes: equatable,
            knownValueTypes: valueTypes
        )
    }

    /// The two real shapes from `RuleIdentifier`, verbatim in structure.
    private static let ruleIdentifier = """
    enum RuleIdentifier: String {
        case forceTry = "Force Try"
        var suppressionKey: String {
            rawValue.components(separatedBy: .whitespaces).map { $0.lowercased() }.joined(separator: "-")
        }
        var category: PatternCategory {
            switch self {
            case .forceTry: return .codeQuality
            }
        }
    }
    """

    // MARK: - The motivating cases

    /// Reads `rawValue` — the synthesised accessor, not a stored property.
    @Test
    func rawValueReadingPropertyIsACandidate() throws {
        let result = try #require(candidate(Self.ruleIdentifier, named: "suppressionKey"))
        #expect(result.shape == .ofSelfAndInputs)
        #expect(result.isPartial == false)
    }

    /// `switch self` on a value type — `self` is the input, not hidden state.
    @Test
    func bareSelfSwitchOnAValueTypeIsACandidate() throws {
        let result = try #require(candidate(Self.ruleIdentifier, named: "category"))
        #expect(result.shape == .ofSelfAndInputs)
    }

    /// The shape is always `.ofSelfAndInputs` — a test must build the enclosing
    /// value first, and the argument list is simply empty.
    @Test
    func propertyReadingImmutableStoredStateIsACandidate() throws {
        let source = """
        struct Plan {
            let total: Int
            let done: Int
            var remaining: Int { total - done }
        }
        """
        let result = try #require(
            candidate(source, named: "remaining", equatable: [], valueTypes: ["Plan"])
        )
        #expect(result.shape == .ofSelfAndInputs)
    }

    // MARK: - Boundary

    /// A setter means mutable state wearing a getter: a law over it quantifies
    /// over something a test can change underneath it.
    @Test
    func aPropertyWithASetterIsNotACandidate() {
        let source = """
        struct Box {
            let base: Int
            var value: Int {
                get { base }
                set { print(newValue) }
            }
        }
        """
        #expect(candidate(source, named: "value", equatable: [], valueTypes: ["Box"]) == nil)
    }

    /// A `static` computed property takes no input at all — it is a constant,
    /// the same reasoning the nullary free-function gate already applies.
    @Test
    func aStaticComputedPropertyIsNotACandidate() {
        let source = "enum Config { static var name: String { \"fixed\" } }"
        #expect(candidate(source, named: "name", equatable: [], valueTypes: ["Config"]) == nil)
    }

    /// Impurity is refused by the shared oracle, exactly as for a function.
    @Test
    func anImpurePropertyIsNotACandidate() {
        let source = "struct Clock { var now: String { Date().description } }"
        #expect(candidate(source, named: "now", equatable: [], valueTypes: ["Clock"]) == nil)
    }

    /// A return type nothing can assert on is refused, matching the function path.
    @Test
    func anUnassertableReturnTypeIsNotACandidate() {
        let source = """
        struct Holder {
            let stored: Int
            var opaque: SomeUnknownType { SomeUnknownType(stored) }
        }
        """
        #expect(candidate(source, named: "opaque", equatable: [], valueTypes: ["Holder"]) == nil)
    }

    /// Reading *mutable* stored state is not a function of the value.
    @Test
    func aPropertyReadingMutableStateIsNotACandidate() {
        let source = """
        struct Counter {
            var count: Int
            var doubled: Int { count * 2 }
        }
        """
        #expect(candidate(source, named: "doubled", equatable: [], valueTypes: ["Counter"]) == nil)
    }

    /// A stored property with observers is not this shape at all.
    @Test
    func aStoredPropertyWithObserversIsNotACandidate() {
        let source = """
        struct Watched {
            var value: Int = 0 {
                didSet { print(value) }
            }
        }
        """
        #expect(candidate(source, named: "value", equatable: [], valueTypes: ["Watched"]) == nil)
    }

    /// Bare `self` on a **reference** type still disqualifies: copying it aliases
    /// one shared object, so the read is not a function of a value.
    @Test
    func bareSelfOnAClassIsStillDisqualifying() {
        let source = """
        class Node {
            let tag: Int
            var mirrored: Node { self }
        }
        """
        #expect(candidate(source, named: "mirrored", equatable: ["Node"], valueTypes: []) == nil)
    }

    /// `rawValue` is admitted only as the *synthesised* accessor. A type that
    /// declares its own mutable `rawValue` resolves through the normal stored
    /// property path and is refused.
    @Test
    func aDeclaredMutableRawValueIsStillDisqualifying() {
        let source = """
        struct Wrapper {
            var rawValue: String
            var normalized: String { rawValue.lowercased() }
        }
        """
        #expect(candidate(source, named: "normalized", equatable: [], valueTypes: ["Wrapper"]) == nil)
    }

    /// A `get throws` accessor is transparent where it returns and undefined
    /// elsewhere — reported as partial rather than refused, exactly as a throwing
    /// function is.
    @Test
    func aThrowingGetterIsAPartialCandidate() throws {
        let source = """
        struct Parser {
            let text: String
            var parsed: Int {
                get throws { Int(text) ?? 0 }
            }
        }
        """
        let result = try #require(
            candidate(source, named: "parsed", equatable: [], valueTypes: ["Parser"])
        )
        #expect(result.isPartial)
    }
}
