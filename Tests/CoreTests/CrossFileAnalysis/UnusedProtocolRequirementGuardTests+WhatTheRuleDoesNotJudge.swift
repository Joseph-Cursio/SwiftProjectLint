@testable import Core
@testable import SwiftProjectLintRules
import Testing

extension UnusedProtocolRequirementGuardTests {
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
        let caller = "func render(_ row: any Row) -> String { row.title }"

        #expect(UnusedRequirementHarness.reported(["R.swift": row, "C.swift": caller]) == ["Row.subtitle"])
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
        let caller = "func run<F: Factory>(_ factory: F) { _ = factory.build() }"

        #expect(UnusedRequirementHarness.reported(["F.swift": factory, "C.swift": caller]) == ["Factory.reset()"])
    }

    @Test
    func objectiveCProtocolsAreSkipped() {
        let delegates = """
        @objc protocol PickerDelegate { func didPick(); func didCancel() }
        protocol LegacyDelegate: NSObjectProtocol { func didPick(); func didCancel() }
        """
        let caller = """
        func run(_ picker: any PickerDelegate, _ legacy: any LegacyDelegate) {
            picker.didPick()
            legacy.didPick()
        }
        """

        #expect(UnusedRequirementHarness.reported(["D.swift": delegates, "C.swift": caller]).isEmpty)
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
        let caller = """
        func go(_ command: any RunCommand, _ sub: any Subcommand, _ plain: any Plain) async throws {
            try await command.run(with: .init())
            sub.describe()
            plain.a()
        }
        """

        #expect(UnusedRequirementHarness.reported(["C.swift": commands, "G.swift": caller]) == ["Plain.b()"])
    }

    /// A macro on a protocol can generate callers the run cannot see — a type eraser forwarding
    /// every requirement — so the protocol is not judged. Global actors are not macros.
    @Test
    func protocolsCarryingAMacroAreSkippedButGlobalActorsAreNot() {
        let protocols = """
        @Forwarding protocol Erased { func a(); func b() }
        @MainActor protocol Isolated { func a(); func b() }
        """
        let caller = "func run(_ erased: any Erased, _ isolated: any Isolated) { erased.a(); isolated.a() }"

        #expect(UnusedRequirementHarness.reported(["P.swift": protocols, "C.swift": caller]) == ["Isolated.b()"])
    }

    @Test
    func theRuleIsOptInInfoArchitecture() {
        #expect(LintConfiguration.optInRules.contains(.unusedProtocolRequirement))
        #expect(RuleIdentifier.unusedProtocolRequirement.category == .architecture)
        #expect(UnusedProtocolRequirement().pattern.severity == .info)
    }
}
