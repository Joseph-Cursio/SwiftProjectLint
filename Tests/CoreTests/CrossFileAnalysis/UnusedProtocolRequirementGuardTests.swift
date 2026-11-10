@testable import Core
@testable import SwiftProjectLintRules
import Testing

/// Protocol extensions, escaping values, and the guards that keep the rule from reporting a
/// requirement it cannot see being used.
@Suite
struct UnusedProtocolRequirementGuardTests {

    static let store = """
    protocol Store {
        func a()
        func b()
        func c()
    }
    """

    static let client = """
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
        let caller = "func run(_ store: any Store) { store.both() }"

        #expect(UnusedRequirementHarness.reported([
            "S.swift": Self.store, "E.swift": extensionFile, "C.swift": caller
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
        let caller = "func run(_ store: any Store) { store.a(); print(store.label) }"

        #expect(UnusedRequirementHarness.reported([
            "S.swift": Self.store, "E.swift": extensionFile, "C.swift": caller
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
        let caller = """
        final class Client {
            private let store: any Store
            init(store: any Store) { self.store = store }
            func run() { process(store) }
            func process(_ value: any Store) { value.a() }
        }
        """

        let reported = UnusedRequirementHarness.reported(["S.swift": Self.store, "C.swift": caller])
        #expect(reported == ["Store.b()", "Store.c()"])
    }

    @Test
    func aMemberwiseInitializerArgumentIsFollowed() {
        let caller = """
        struct Screen {
            private let store: any Store
            func refresh() { store.a() }
        }
        func show(_ store: any Store) -> Screen { Screen(store: store) }
        """

        let reported = UnusedRequirementHarness.reported(["S.swift": Self.store, "C.swift": caller])
        #expect(reported == ["Store.b()", "Store.c()"])
    }

    /// Anywhere else the value could reach every requirement, so the protocol is not judged.
    @Test
    func anArgumentToAnUnknownFunctionUsesEverything() {
        let caller = """
        func run(_ store: any Store) {
            store.a()
            register(store)
        }
        """

        #expect(UnusedRequirementHarness.reported(["S.swift": Self.store, "C.swift": caller]).isEmpty)
    }

    @Test
    func aCollectionOfTheProtocolUsesEverything() {
        let caller = """
        final class Registry {
            var stores: [any Store] = []
            func run(_ store: any Store) { store.a() }
        }
        """

        #expect(UnusedRequirementHarness.reported(["S.swift": Self.store, "C.swift": caller]).isEmpty)
    }

    @Test
    func stringInterpolationIsAnEscape() {
        let caller = "func run(_ store: any Store) { store.a(); print(\"\\(store)\") }"

        #expect(UnusedRequirementHarness.reported(["S.swift": Self.store, "C.swift": caller]).isEmpty)
    }

    @Test
    func returningTheValueAsTheProtocolIsNotAnEscape() {
        let caller = """
        final class Holder {
            let store: any Store
            init(store: any Store) { self.store = store }
            func current() -> any Store { store }
        }
        func run(_ holder: Holder) { holder.current().a() }
        """

        let reported = UnusedRequirementHarness.reported(["S.swift": Self.store, "C.swift": caller])
        #expect(reported == ["Store.b()", "Store.c()"])
    }

    @Test
    func returningTheValueFromAClosureIsAnEscape() {
        let caller = """
        func run(_ store: any Store) {
            store.a()
            let provider = { store }
            consume(provider)
        }
        """

        #expect(UnusedRequirementHarness.reported(["S.swift": Self.store, "C.swift": caller]).isEmpty)
    }

    @Test
    func aClosureCaptureIsTheCapturedValue() {
        let caller = """
        final class Client {
            weak var store: (any Store & AnyObject)?
            func run() {
                schedule { [weak store] in store?.b() }
            }
        }
        """

        let reported = UnusedRequirementHarness.reported(["S.swift": Self.store, "C.swift": caller])
        #expect(reported == ["Store.a()", "Store.c()"])
    }

    /// `injected ?? Default()` is the default-injection idiom: the value is still the protocol's.
    @Test
    func aDefaultedInjectionIsTheInjectedValue() {
        let caller = """
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

        #expect(UnusedRequirementHarness.reported(["S.swift": Self.store, "C.swift": caller]) == ["Store.c()"])
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
        let caller = "func go(_ command: any Command) { command.run() }"

        #expect(UnusedRequirementHarness.reported(["C.swift": command, "G.swift": caller]) == ["Command.validate()"])
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
}
