@testable import Core
import Testing

/// How a client reaches a requirement, and what counts as reaching it.
@Suite
struct UnusedProtocolRequirementCallTests {

    private static let store = """
    protocol Store {
        func a()
        func b()
        func c()
    }
    """

    @Test
    func selfQualifiedAccessIsCredited() {
        let client = """
        final class Client {
            let store: any Store
            init(store: any Store) { self.store = store }
            func run() { self.store.a() }
        }
        """

        let reported = UnusedRequirementHarness.reported(["S.swift": Self.store, "C.swift": client])
        #expect(reported == ["Store.b()", "Store.c()"])
    }

    @Test
    func propertyRequirementsAreCreditedForReadsAndWrites() {
        let profile = """
        protocol Profile: AnyObject {
            var title: String { get }
            var count: Int { get set }
            var unused: Bool { get }
        }
        """
        let client = """
        func render(_ profile: any Profile) -> String {
            profile.count = 1
            return profile.title
        }
        """

        #expect(UnusedRequirementHarness.reported(["P.swift": profile, "C.swift": client]) == ["Profile.unused"])
    }

    @Test
    func argumentLabelsDistinguishOverloads() {
        let loader = """
        protocol Loader {
            func load(id: Int)
            func load(name: String)
        }
        """
        let client = "func run(_ loader: any Loader) { loader.load(id: 1) }"

        #expect(UnusedRequirementHarness.reported(["L.swift": loader, "C.swift": client]) == ["Loader.load(name:)"])
    }

    @Test
    func aTrailingClosureMatchesWhateverItsLabelIs() {
        let fetcher = """
        protocol Fetcher {
            func fetch(completion: @escaping (Int) -> Void)
            func cancel()
        }
        """
        let client = "func run(_ fetcher: any Fetcher) { fetcher.fetch { print($0) } }"

        #expect(UnusedRequirementHarness.reported(["F.swift": fetcher, "C.swift": client]) == ["Fetcher.cancel()"])
    }

    @Test
    func anUnappliedMethodReferenceCountsAsAUse() {
        let client = """
        func run(_ store: any Store) {
            let action = store.a
            action()
            store.b()
        }
        """

        #expect(UnusedRequirementHarness.reported(["S.swift": Self.store, "C.swift": client]) == ["Store.c()"])
    }

    @Test
    func genericConstraintsAndWhereClausesAreClients() {
        let client = """
        func first<T: Store>(_ store: T) { store.a() }
        func second<T>(_ store: T) where T: Store { store.b() }
        """

        #expect(UnusedRequirementHarness.reported(["S.swift": Self.store, "C.swift": client]) == ["Store.c()"])
    }

    @Test
    func aGenericTypeParameterIsAClientInsideTheType() {
        let client = """
        struct Box<S: Store> {
            let store: S
            func run() { store.a() }
        }
        extension Box {
            func more() { store.b() }
        }
        """

        #expect(UnusedRequirementHarness.reported(["S.swift": Self.store, "C.swift": client]) == ["Store.c()"])
    }

    @Test
    func anOpaqueParameterIsAClient() {
        let client = "func run(_ store: some Store) { store.c() }"

        let reported = UnusedRequirementHarness.reported(["S.swift": Self.store, "C.swift": client])
        #expect(reported == ["Store.a()", "Store.b()"])
    }

    @Test
    func annotatedLocalsAndLocalsInferredFromAClientAreFollowed() {
        let client = """
        func run(_ source: any Store, factory: Factory) {
            let annotated: any Store = factory.make()
            annotated.a()
            let copy = source
            copy.b()
        }
        """

        #expect(UnusedRequirementHarness.reported(["S.swift": Self.store, "C.swift": client]) == ["Store.c()"])
    }

    @Test
    func optionalChainingAndForceUnwrappingKeepTheReceiver() {
        let delegate = """
        protocol Delegate: AnyObject {
            func didStart()
            func didFinish()
            func didFail()
        }
        """
        let client = """
        final class Worker {
            weak var delegate: (any Delegate)?
            func run() {
                delegate?.didStart()
                delegate!.didFinish()
            }
        }
        """

        #expect(UnusedRequirementHarness.reported(["D.swift": delegate, "W.swift": client]) == ["Delegate.didFail()"])
    }

    @Test
    func aCastToTheProtocolIsAClient() {
        let client = """
        func run(_ object: Any) {
            if let store = object as? any Store {
                store.a()
            }
            (object as? Store)?.b()
        }
        """

        #expect(UnusedRequirementHarness.reported(["S.swift": Self.store, "C.swift": client]) == ["Store.c()"])
    }

    @Test
    func aProducersResultIsAClient() {
        let client = """
        func makeStore() -> any Store { LiveStore() }

        func run() {
            makeStore().a()
            let store = makeStore()
            store.b()
        }
        """

        #expect(UnusedRequirementHarness.reported(["S.swift": Self.store, "C.swift": client]) == ["Store.c()"])
    }

    @Test
    func aMemberReachedThroughAnotherTypeIsCredited() {
        let client = """
        final class ViewModel {
            let store: any Store
            init(store: any Store) { self.store = store }
            func run() { store.a() }
        }
        struct Screen {
            let model: ViewModel
            func refresh() { model.store.b() }
        }
        """

        #expect(UnusedRequirementHarness.reported(["S.swift": Self.store, "C.swift": client]) == ["Store.c()"])
    }

    /// A local that shadows the protocol-typed member is a different value.
    @Test
    func aLocalShadowingAProtocolTypedMemberIsNotCredited() {
        let client = """
        final class ViewModel {
            let store: any Store
            init(store: any Store) { self.store = store }
            func run() {
                store.a()
                let store = LiveStore()
                store.b()
            }
        }
        """

        let reported = UnusedRequirementHarness.reported(["S.swift": Self.store, "C.swift": client])
        #expect(reported == ["Store.b()", "Store.c()"])
    }

    @Test
    func aClientTypedWithARefiningProtocolCreditsTheProtocolItRefines() {
        let protocols = """
        protocol Base {
            func a()
            func b()
        }
        protocol Refined: Base {
            func c()
        }
        """
        let client = "func run(_ value: any Refined) { value.a(); value.c() }"

        #expect(UnusedRequirementHarness.reported(["P.swift": protocols, "C.swift": client]) == ["Base.b()"])
    }

    @Test
    func aClientTypedWithAnAliasedCompositionCreditsEachProtocol() {
        let protocols = """
        protocol Saving { func save(); func flush() }
        protocol Reading { func read(); func peek() }
        typealias Storage = Saving & Reading
        """
        let client = "func run(_ storage: any Storage) { storage.save(); storage.read() }"

        #expect(UnusedRequirementHarness.reported(["P.swift": protocols, "C.swift": client]) == [
            "Reading.peek()", "Saving.flush()"
        ])
    }

    /// Tests that call a requirement through a protocol-typed double depend on the protocol too.
    @Test
    func testFilesAreClients() {
        let production = """
        final class Client {
            let store: any Store
            init(store: any Store) { self.store = store }
            func run() { store.a() }
        }
        """
        let test = """
        @Test func storeContract() {
            let store: any Store = FakeStore()
            store.b()
        }
        """

        #expect(UnusedRequirementHarness.reported([
            "Sources/S.swift": Self.store, "Sources/C.swift": production, "Tests/StoreTests.swift": test
        ]) == ["Store.c()"])
    }
}
