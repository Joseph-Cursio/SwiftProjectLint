import Foundation
import SwiftParser
import SwiftSyntax
import Testing

extension PurityOracleEntryTests {
    // MARK: - The scan

    @Test("the scan reads repository-relative paths, wherever the checkout lives")
    func scannedPathsAreRepositoryRelative() {
        // Every rule above matches on these paths; one spelled wrong makes each of them fail for
        // a reason that has nothing to do with the rule. This names the actual fault once.
        let misread = Self.sources.map(\.path).filter { !($0.hasPrefix("Sources/") || $0.hasPrefix("Packages/")) }
        #expect(misread.isEmpty, "paths not relative to the repository root: \(misread.prefix(3))")
        #expect(Self.sources.contains { $0.path == Self.projectLinter }, "the scan did not see ProjectLinter.swift")
    }

    static let visitorsSources = "Packages/SwiftProjectLintVisitors/Sources/"
    static let wrapper = visitorsSources + "SwiftProjectLintVisitors/PurityInferrer.swift"
    static let packagePurity = visitorsSources + "SwiftProjectLintVisitors/PackagePurity.swift"
    static let engineSources = "Packages/SwiftProjectLintEngine/Sources/SwiftProjectLintEngine/"
    static let projectLinter = engineSources + "ProjectLinter.swift"
    static let purityParse = engineSources + "ProjectLinter+Purity.swift"
    static let largeStackWorkers = engineSources + "LargeStackWorkers.swift"
    static let preScan = engineSources + "ProjectLinter+PreScan.swift"
    static let withholdable = visitorsSources + "SwiftProjectLintVisitors/Withholdable.swift"
    static let rulePackages = [
        "Packages/SwiftProjectLintRules/Sources/",
        "Packages/SwiftProjectLintIdempotencyRules/Sources/",
        "Sources/",
    ]

    /// Where the per-run analysis executes. Config and the App are left out: their detached work
    /// (the directory-tree scan, registry setup) is off the analysis path.
    static let analysisPackages = [
        "Packages/SwiftProjectLintEngine/Sources/",
        "Packages/SwiftProjectLintRegistry/Sources/",
        "Packages/SwiftProjectLintVisitors/Sources/",
        "Packages/SwiftProjectLintRules/Sources/",
        "Packages/SwiftProjectLintIdempotencyRules/Sources/",
    ]

    struct SourceFile: Sendable {
        let path: String
        let tree: SourceFileSyntax
        /// Every token's text, punctuation included.
        let tokens: [String]
        /// Identifier and keyword tokens only, in order — `.` and the like dropped, so
        /// `SwiftEffectInference.PurityInferrer` reads as two adjacent names.
        let identifierSequence: [String]
        let imports: Set<String>
    }

    /// Every Swift file under `Sources/` and `Packages/*/Sources/`, parsed once for the suite.
    ///
    /// Each path is built from a prefix this scan names (`Sources`, `Packages/<name>/Sources`) and
    /// the path the walker reports **relative to the directory it walks** — never by slicing one
    /// spelling of the root off another. That slicing broke in any checkout under a symlinked
    /// directory: `#filePath` resolved to `/tmp/…` while the walker spelled `/private/tmp/…`, every
    /// path came out as `/branch/Packages/…`, and all five tests failed.
    static let sources: [SourceFile] = {
        let root = repositoryRoot
        var roots = [(relative: "Sources", directory: root.appendingPathComponent("Sources"))]
        let packages = root.appendingPathComponent("Packages")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: packages.path)) ?? []
        roots += names.sorted().map { name in
            (relative: "Packages/\(name)/Sources",
             directory: packages.appendingPathComponent(name).appendingPathComponent("Sources"))
        }

        var files: [SourceFile] = []
        for (relative, directory) in roots {
            guard let walker = FileManager.default.enumerator(atPath: directory.path) else { continue }
            for case let inner as String in walker where inner.hasSuffix(".swift") {
                let url = directory.appendingPathComponent(inner)
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
                files.append(scanned(text, path: relative + "/" + inner))
            }
        }
        return files.sorted { $0.path < $1.path }
    }()

    /// The name a type is declared under, the last component: `Bar` for `Bar`, `Foo.Bar` and `Bar<T>`.
    static func typeName(of type: TypeSyntax) -> String {
        if let member = type.as(MemberTypeSyntax.self) { return member.name.text }
        if let identifier = type.as(IdentifierTypeSyntax.self) { return identifier.name.text }
        return type.trimmedDescription
    }

    /// `text` scanned as the suite scans a file at `path`. The probes in `PurityScanProbeTests` use it.
    static func scanned(_ text: String, path: String) -> SourceFile {
        let tree = Parser.parse(source: text)
        let all = Array(tree.tokens(viewMode: .sourceAccurate))
        let named = all.filter {
            switch $0.tokenKind {
            case .identifier, .dollarIdentifier, .keyword: return true
            default: return false
            }
        }
        let imports = Set(tree.statements.compactMap {
            $0.item.as(ImportDeclSyntax.self)?.path.map(\.name.text).joined(separator: ".")
        })
        return SourceFile(
            path: path,
            tree: tree,
            tokens: all.map(\.text),
            identifierSequence: named.map(\.text),
            imports: imports
        )
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Packaging
            .deletingLastPathComponent()   // CoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repository root
    }
}
