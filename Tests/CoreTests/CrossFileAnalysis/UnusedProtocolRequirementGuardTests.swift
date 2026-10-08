@testable import Core
@testable import SwiftProjectLintRules
import Testing

/// Protocol extensions, escaping values, and the guards that keep the rule from reporting a
/// requirement it cannot see being used.
@Suite
struct UnusedProtocolRequirementGuardTests {

    private static let store = """
    protocol Store {
        func a()
        func b()
        func c()
    }
    """

    private static let client = """
    final class Client {
        private let store: any Store
        init(store: any Store) { self.store = store }
        func run() { store.a() }
    }
    """

    // MARK: - Protocol extensions

    /// An extension method a client calls counts every requirement it reaches, transitively.
    @Test
    func anExtensionMethodCreditsTheRequirementsItCalls() {
        let extensionFile = """
        extension Store {
            func both() {
                a()
                helper()
            }
            func helper() { self.b() }
        }
        """
        let client = "func run(_ store: any Store) { store.both() }"

        #expect(UnusedRequirementHarness.reported([
            "S.swift": Self.store, "E.swift": extensionFile, "C.swift": client
        ]) == ["Store.c()"])
    }

    /// An extension is code written against the protocol: calling it on a concrete conformer
    /// still runs the requirements it calls, and removing one would break it.
    @Test
    func anExtensionMethodCalledOnAConformerStillCredits() {
        let extensionFile = "extension Store { func pair() { a(); b() } }"
        let conformer = "struct Live: Store { func a() {}; func b() {}; func c() {}; func go() { pair() } }"

        #expect(UnusedRequirementHarness.reported([
            "S.swift": Self.store, "E.swift": extensionFile, "L.swift": conformer, "C.swift": Self.client
        ]) == ["Store.c()"])
    }

    /// `Self.self` names the conforming type; handing it to `String(describing:)` sends no
    /// value of the protocol anywhere.
    @Test
    func aMetatypeIsNotAnEscapingValue() {
        let extensionFile = """
        extension Store {
            var label: String { String(describing: Self.self) }
        }
        """
        let client = "func run(_ store: any Store) { store.a(); print(store.label) }"

        #expect(UnusedRequirementHarness.reported([
            "S.swift": Self.store, "E.swift": extensionFile, "C.swift": client
        ]) == ["Store.b()", "Store.c()"])
    }

    @Test
    func anExtensionMethodNothingCallsCreditsNothing() {
        let extensionFile = "extension Store { func neverCalled() { b() } }"

        #expect(UnusedRequirementHarness.reported([
            "S.swift": Self.store, "E.swift": extensionFile, "C.swift": Self.client
        ]) == ["Store.b()", "Store.c()"])
    }

    // MARK: - Escapes

    /// Handing the value to a parameter typed with the protocol is followed one hop: that
    /// parameter is a client of its own.
    @Test
    func anArgumentToAProtocolTypedParameterIsFollowed() {
        let client = """
        final class Client {
            private let store: any Store
            init(store: any Store) { self.store = store }
            func run() { process(store) }
            func process(_ value: any Store) { value.a() }
        }
        """

        let reported = UnusedRequirementHarness.reported(["S.swift": Self.store, "C.swift": client])
        #expect(reported == ["Store.b()", "Store.c()"])
    }

    @Test
    func aMemberwiseInitializerArgumentIsFollowed() {
        let client = """
        struct Screen {
            let store: any Store
            func refresh() { store.a() }
        }
        func show(_ store: any Store) -> Screen { Screen(store: store) }
        """

        let reported = UnusedRequirementHarness.reported(["S.swift": Self.store, "C.swift": client])
        #expect(reported == ["Store.b()", "Store.c()"])
    }

    /// Anywhere else the value could reach every requirement, so the protocol is not judged.
    @Test
    func anArgumentToAnUnknownFunctionUsesEverything() {
        let client = """
        func run(_ store: any Store) {
            store.a()
            register(store)
        }
        """

        #expect(UnusedRequirementHarness.reported(["S.swift": Self.store, "C.swift": client]).isEmpty)
    }

    @Test
    func aCollectionOfTheProtocolUsesEverything() {
        let client = """
        final class Registry {
            var stores: [any Store] = []
            func run(_ store: any Store) { store.a() }
        }
        """

        #expect(UnusedRequirementHarness.reported(["S.swift": Self.store, "C.swift": client]).isEmpty)
    }

    @Test
    func stringInterpolationIsAnEscape() {
        let client = "func run(_ store: any Store) { store.a(); print(\"\\(store)\") }"

        #expect(UnusedRequirementHarness.reported(["S.swift": Self.store, "C.swift": client]).isEmpty)
    }

    @Test
    func returningTheValueAsTheProtocolIsNotAnEscape() {
        let client = """
        final class Holder {
            private let store: any Store
            init(store: any Store) { self.store = store }
            func current() -> any Store { store }
        }
        func run(_ holder: Holder) { holder.current().a() }
        """

        let reported = UnusedRequirementHarness.reported(["S.swift": Self.store, "C.swift": client])
        #expect(reported == ["Store.b()", "Store.c()"])
    }

    @Test
    func returningTheValueFromAClosureIsAnEscape() {
        let client = """
        func run(_ store: any Store) {
            store.a()
            let provider = { store }
            consume(provider)
        }
        """

        #expect(UnusedRequirementHarness.reported(["S.swift": Self.store, "C.swift": client]).isEmpty)
    }

    @Test
    func aClosureCaptureIsTheCapturedValue() {
        let client = """
        final class Client {
            weak var store: (any Store & AnyObject)?
            func run() {
                schedule { [weak store] in store?.b() }
            }
        }
        """

        let reported = UnusedRequirementHarness.reported(["S.swift": Self.store, "C.swift": client])
        #expect(reported == ["Store.a()", "Store.c()"])
    }

    /// `injected ?? Default()` is the default-injection idiom: the value is still the protocol's.
    @Test
    func aDefaultedInjectionIsTheInjectedValue() {
        let client = """
        final class Manager {
            let store: any Store
            init(store: (any Store)? = nil) {
                let resolved = store ?? LiveStore()
                self.store = resolved
            }
            func run(_ flag: Bool, backup: any Store) {
                store.a()
                let chosen = flag ? store : backup
                chosen.b()
            }
        }
        """

        #expect(UnusedRequirementHarness.reported(["S.swift": Self.store, "C.swift": client]) == ["Store.c()"])
    }

    /// `Self.message(…)` calls a static function the run declares, which returns no protocol
    /// value, so nothing is constructed and nothing escapes.
    @Test
    func aStaticCallOnSelfIsNotAConstruction() {
        let command = """
        protocol Command {
            func run()
            func validate()
            static func message(_ text: String) -> String
        }
        extension Command {
            func run() { print(Self.message("done")) }
        }
        """
        let client = "func go(_ command: any Command) { command.run() }"

        #expect(UnusedRequirementHarness.reported(["C.swift": command, "G.swift": client]) == ["Command.validate()"])
    }

    @Test
    func anEnvironmentKeyPathPropertyIsTheEnvironmentValue() {
        let environment = """
        extension EnvironmentValues {
            @Entry var store: any Store = LiveStore()
        }
        struct StoreView: View {
            @Environment(\\.store) private var store
            var body: some View { Button("Go") { store.a() } }
        }
        """

        #expect(UnusedRequirementHarness.reported(["S.swift": Self.store, "V.swift": environment]) == [
            "Store.b()", "Store.c()"
        ])
    }

    // MARK: - What the rule does not judge

    @Test(arguments: ["public", "open", "package"])
    func apiProtocolsAreSkipped(modifier: String) {
        let api = "\(modifier) protocol Store { func a(); func b() }"

        #expect(UnusedRequirementHarness.reported(["S.swift": api, "C.swift": Self.client]).isEmpty)
    }

    @Test
    func aProtocolDeclaredInTestCodeIsNotReported() {
        let double = "protocol Recording { func record(); func reset() }"
        let test = "@Test func records() { let spy: any Recording = Spy(); spy.record() }"

        #expect(UnusedRequirementHarness.reported([
            "Tests/Support/Recording.swift": double, "Tests/RecordingTests.swift": test
        ]).isEmpty)
    }

    @Test
    func aProtocolWithoutClientsIsLeftToUnusedProtocolAbstraction() {
        let conformer = "struct Live: Store { func a() {}; func b() {}; func c() {} }"

        #expect(UnusedRequirementHarness.reported(["S.swift": Self.store, "L.swift": conformer]).isEmpty)
    }

    @Test
    func frameworkConventionRequirementsAreNotReported() {
        let row = """
        protocol Row: Identifiable, CustomStringConvertible {
            var id: UUID { get }
            var description: String { get }
            func hash(into hasher: inout Hasher)
            var title: String { get }
            var subtitle: String { get }
        }
        """
        let client = "func render(_ row: any Row) -> String { row.title }"

        #expect(UnusedRequirementHarness.reported(["R.swift": row, "C.swift": client]) == ["Row.subtitle"])
    }

    @Test
    func staticRequirementsAndInitializersAreNotReported() {
        let factory = """
        protocol Factory {
            init(seed: Int)
            static func make() -> Self
            static var name: String { get }
            associatedtype Output
            func build() -> Output
            func reset()
        }
        """
        let client = "func run<F: Factory>(_ factory: F) { _ = factory.build() }"

        #expect(UnusedRequirementHarness.reported(["F.swift": factory, "C.swift": client]) == ["Factory.reset()"])
    }

    @Test
    func objectiveCProtocolsAreSkipped() {
        let delegates = """
        @objc protocol PickerDelegate { func didPick(); func didCancel() }
        protocol LegacyDelegate: NSObjectProtocol { func didPick(); func didCancel() }
        """
        let client = """
        func run(_ picker: any PickerDelegate, _ legacy: any LegacyDelegate) {
            picker.didPick()
            legacy.didPick()
        }
        """

        #expect(UnusedRequirementHarness.reported(["D.swift": delegates, "C.swift": client]).isEmpty)
    }

    /// A framework calls the requirements of its own protocols — ArgumentParser runs
    /// `validate()` on every command — so a protocol refining one, directly or through another
    /// project protocol, is not judged. The framework protocols whose requirements are known are.
    @Test
    func aProtocolRefiningAnUnknownFrameworkProtocolIsSkipped() {
        let commands = """
        protocol RunCommand: AsyncParsableCommand {
            func run(with options: Options) async throws
            func validate() throws
        }
        protocol Subcommand: RunCommand { func describe() }
        protocol Plain: Sendable, Hashable { func a(); func b() }
        """
        let client = """
        func go(_ command: any RunCommand, _ sub: any Subcommand, _ plain: any Plain) async throws {
            try await command.run(with: .init())
            sub.describe()
            plain.a()
        }
        """

        #expect(UnusedRequirementHarness.reported(["C.swift": commands, "G.swift": client]) == ["Plain.b()"])
    }

    /// A macro on a protocol can generate callers the run cannot see — a type eraser forwarding
    /// every requirement — so the protocol is not judged. Global actors are not macros.
    @Test
    func protocolsCarryingAMacroAreSkippedButGlobalActorsAreNot() {
        let protocols = """
        @Forwarding protocol Erased { func a(); func b() }
        @MainActor protocol Isolated { func a(); func b() }
        """
        let client = "func run(_ erased: any Erased, _ isolated: any Isolated) { erased.a(); isolated.a() }"

        #expect(UnusedRequirementHarness.reported(["P.swift": protocols, "C.swift": client]) == ["Isolated.b()"])
    }

    @Test
    func theRuleIsOptInInfoArchitecture() {
        #expect(LintConfiguration.optInRules.contains(.unusedProtocolRequirement))
        #expect(RuleIdentifier.unusedProtocolRequirement.category == .architecture)
        #expect(UnusedProtocolRequirement().pattern.severity == .info)
    }
}
