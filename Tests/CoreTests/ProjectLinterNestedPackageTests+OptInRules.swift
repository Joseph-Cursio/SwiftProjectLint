import Foundation
import SwiftProjectLintConfig
import SwiftProjectLintEngine
import SwiftProjectLintModels
import Testing

extension ProjectLinterNestedPackageTests {
    /// End-to-end wiring for the opt-in Shared Domain-Enum Field rule: it is silent by
    /// default (opt-in) and fires only when explicitly enabled, proving the registrar is
    /// registered and the opt-in membership is correct.
    @Test func testSharedDomainEnumFieldIsOptInAndFiresWhenEnabled() async {
        let root = makeProjectWithSharedEnumFieldCluster()
        let linter = ProjectLinter()
        let system = PatternRegistryFactory.createConfiguredSystem()

        let byDefault = await linter.analyzeProject(at: root, detector: system.detector)
        let whenEnabled = await linter.analyzeProject(
            at: root,
            detector: system.detector,
            configuration: LintConfiguration(enabledOnlyRules: [.sharedDomainEnumField])
        )

        // Opt-in: not run unless explicitly enabled.
        #expect(byDefault.contains { $0.ruleName == .sharedDomainEnumField } == false)
        // Enabled: the three-type IssueSeverity cluster is flagged.
        let flagged = whenEnabled.filter { $0.ruleName == .sharedDomainEnumField }
        #expect(flagged.count == 3)
        #expect(flagged.allSatisfy { $0.message.contains("IssueSeverity") })
    }

    /// A package with three unrelated types each carrying `severity: IssueSeverity` and
    /// no shared protocol — the Shared Domain-Enum Field cluster.
    private func makeProjectWithSharedEnumFieldCluster() -> String {
        let root = makeTempPackageRoot(named: "SharedEnumField")
        writeFile(at: "\(root)/Sources/Root/Severity.swift", "enum IssueSeverity { case error, warning, info }")
        writeFile(at: "\(root)/Sources/Root/Conflict.swift", """
        struct SettingConflict {
            let severity: IssueSeverity
            let title: String
        }
        """)
        writeFile(at: "\(root)/Sources/Root/Simulation.swift", """
        struct SimulationIssue {
            let severity: IssueSeverity
            let message: String
        }
        """)
        writeFile(at: "\(root)/Sources/Root/Validation.swift", """
        struct ValidationIssue {
            let severity: IssueSeverity
            let detail: String
        }
        """)
        return root
    }

    /// End-to-end wiring for the opt-in Hoistable Conformer Member rule: silent by
    /// default, fires only when enabled — proving the registrar and opt-in membership.
    @Test func testHoistableConformerMemberIsOptInAndFiresWhenEnabled() async {
        let root = makeProjectWithHoistableConformerMember()
        let linter = ProjectLinter()
        let system = PatternRegistryFactory.createConfiguredSystem()

        let byDefault = await linter.analyzeProject(at: root, detector: system.detector)
        let whenEnabled = await linter.analyzeProject(
            at: root,
            detector: system.detector,
            configuration: LintConfiguration(enabledOnlyRules: [.hoistableConformerMember])
        )

        #expect(byDefault.contains { $0.ruleName == .hoistableConformerMember } == false)
        let flagged = whenEnabled.filter { $0.ruleName == .hoistableConformerMember }
        #expect(flagged.count == 3)
        #expect(flagged.allSatisfy { $0.message.contains("Named") })
    }

    /// A package with three `Named` conformers that each implement `matches` identically
    /// using only `Named`'s requirements — the hoist-to-`extension Named` case.
    private func makeProjectWithHoistableConformerMember() -> String {
        let root = makeTempPackageRoot(named: "HoistableMember")
        writeFile(at: "\(root)/Sources/Root/Named.swift", """
        protocol Named {
            var rawKey: String { get }
            var name: String { get }
        }
        """)
        for typeName in ["Alpha", "Beta", "Gamma"] {
            writeFile(at: "\(root)/Sources/Root/\(typeName).swift", """
            struct \(typeName): Named {
                let rawKey: String
                let name: String
                func matches(_ query: String) -> Bool { rawKey.contains(query) || name.contains(query) }
            }
            """)
        }
        return root
    }

    /// End-to-end wiring for the opt-in Hoistable Sequence Operation rule: silent by
    /// default, fires only when enabled — proving the registrar and opt-in membership.
    @Test func testHoistableSequenceOperationIsOptInAndFiresWhenEnabled() async {
        let root = makeProjectWithRepeatedSequenceClosure()
        let linter = ProjectLinter()
        let system = PatternRegistryFactory.createConfiguredSystem()

        let byDefault = await linter.analyzeProject(at: root, detector: system.detector)
        let whenEnabled = await linter.analyzeProject(
            at: root,
            detector: system.detector,
            configuration: LintConfiguration(enabledOnlyRules: [.hoistableSequenceOperation])
        )

        #expect(byDefault.contains { $0.ruleName == .hoistableSequenceOperation } == false)
        let flagged = whenEnabled.filter { $0.ruleName == .hoistableSequenceOperation }
        #expect(flagged.count == 2)
        #expect(flagged.allSatisfy { $0.message.contains("Ranked") })
    }

    /// A package where the same two-key sort closure (`{category,name}` ⊆ Ranked) appears at
    /// two call sites — the Hoistable Sequence Operation case.
    private func makeProjectWithRepeatedSequenceClosure() -> String {
        let root = makeTempPackageRoot(named: "HoistableSequence")
        writeFile(at: "\(root)/Sources/Root/Ranked.swift", """
        protocol Ranked {
            var category: String { get }
            var name: String { get }
        }
        """)
        writeFile(at: "\(root)/Sources/Root/SortA.swift", """
        func sortA(_ items: [Ranked]) -> [Ranked] {
            items.sorted { ($0.category, $0.name) < ($1.category, $1.name) }
        }
        """)
        writeFile(at: "\(root)/Sources/Root/SortB.swift", """
        func sortB(_ items: [Ranked]) -> [Ranked] {
            items.sorted { ($0.category, $0.name) < ($1.category, $1.name) }
        }
        """)
        return root
    }
}
