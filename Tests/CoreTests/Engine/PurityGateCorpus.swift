import Foundation
import SwiftProjectLintConfig
@testable import SwiftProjectLintEngine
import SwiftProjectLintModels
import SwiftProjectLintRegistry

/// A package that moves every purity consumer: the refuting `Item` and its callers, closures over
/// it and over a nested package's minting type, a kernel, a trapped kernel and a concrete
/// dependency. The nested package is compiled through a local path dependency, so a run that
/// builds the universe walks and parses it, and one that does not, does not.
enum PurityGateCorpus {

    static let files: [String: String] = [
        "Package.swift": """
        // swift-tools-version:5.9
        import PackageDescription
        let package = Package(
            name: "Corpus",
            dependencies: [.package(path: "Packages/Kit")],
            targets: [.target(name: "Lib", dependencies: [.product(name: "Kit", package: "Kit")])]
        )
        """,
        "Packages/Kit/Package.swift": """
        // swift-tools-version:5.9
        import PackageDescription
        let package = Package(
            name: "Kit",
            products: [.library(name: "Kit", targets: ["Kit"])],
            targets: [.target(name: "Kit")]
        )
        """,
        "Packages/Kit/Sources/Kit/Stamp.swift": """
        import Foundation

        public struct Stamp {
            public let id = UUID()
            public let n: Int
            public init(n: Int) { self.n = n }
        }
        """,
        "Sources/Lib/Callers.swift": PackagePurityFixtures.callers,
        "Sources/Lib/Closures.swift": """
        func tally(_ values: [Int]) -> [Int] {
            values.map { value in
                let item = Item(n: value)
                return item.n * 2 + 1
            }
        }

        func stamps(_ values: [Int]) -> [Int] {
            values.map { Stamp(n: $0).n + 1 }
        }

        func evens(_ values: [Int]) -> [Int] {
            values.filter { $0 % 2 == 0 }
        }

        func runningTotal(_ values: [Int]) -> Int {
            var total = 0
            values.forEach { total += $0 }
            return total
        }
        """,
        "Sources/Lib/Builder.swift": """
        struct TallyBuilder {
            func build(_ n: Int) -> Int { Item(n: n).n }
        }

        func runTally(_ n: Int) -> Int {
            let builder = TallyBuilder()
            return builder.build(n)
        }

        final class Report {
            let builder: TallyBuilder
            init(builder: TallyBuilder) { self.builder = builder }
            func total(_ n: Int) -> Int { builder.build(n) }
        }
        """,
        // A near miss for `missingEquatableOnPureResult`: `Plan` is one synthesized conformance away
        // from comparable. An instance method, so the clean-method catalog is read; and found, so the
        // one-hop join is read after it.
        "Sources/Lib/Plans.swift": """
        struct Plan {
            let steps: [Int]
        }

        struct Planner {
            let base: Int
            func plan(_ n: Int) -> Plan { Plan(steps: [n * base]) }
        }

        // A pure mutator for `pureMutatorCandidate`, read the same way: an instance method, found.
        struct Tally: Equatable {
            var n: Int
        }

        struct Adder {
            let step: Int
            func add(to tally: inout Tally) { tally.n += step }
        }
        """,
        "Sources/Lib/Engine.swift": """
        func appendWarnings(from names: [String], to items: inout [Item]) {
            if !names.isEmpty {
                let shown = names.prefix(3).joined(separator: ", ")
                let extra = names.count > 3 ? " and \\(names.count - 3) more" : ""
                items.append(Item(n: shown.count + extra.count))
            }
        }
        """,
    ]

    static func makeProject(item: String = PackagePurityFixtures.refutingItem) throws -> String {
        var files = files
        files["Sources/Lib/Item.swift"] = item
        return try PackagePurityFixtures.makeProject(files)
    }

    static func lint(
        rules: [RuleIdentifier]?,
        demand: ProjectLinter.PurityDemand? = nil
    ) async throws -> ProjectLinter.LintRun {
        let path = try makeProject()
        defer { try? FileManager.default.removeItem(atPath: path) }
        return await lint(at: path, rules: rules, demand: demand)
    }

    static func lint(
        at path: String,
        rules: [RuleIdentifier]?,
        detector: SourcePatternDetector = PatternRegistryFactory.createConfiguredSystem().detector,
        demand: ProjectLinter.PurityDemand? = nil
    ) async -> ProjectLinter.LintRun {
        await ProjectLinter().lint(
            at: path,
            targetType: .auto,
            categories: nil,
            ruleIdentifiers: rules,
            detector: detector,
            configuration: .default,
            demand: demand
        )
    }

    /// A finding as everything but its per-instance `id`, in reporting order.
    static func rendered(_ issues: [LintIssue]) -> [String] {
        issues.map {
            "\($0.ruleName.rawValue)|\($0.locations.map { "\($0.filePath):\($0.lineNumber)" })|"
                + "\($0.severity)|\($0.message)|\($0.suggestion ?? "")|\($0.symbol ?? "")|"
                + "\(String(describing: $0.role))|\(String(describing: $0.effect))|\($0.testReachability)"
        }
    }

    /// This repository's own visitors package: real code, over sixty files, every purity helper.
    static var visitorsSources: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Engine
            .deletingLastPathComponent()   // CoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repository root
            .appendingPathComponent("Packages/SwiftProjectLintVisitors/Sources")
            .path
    }
}
