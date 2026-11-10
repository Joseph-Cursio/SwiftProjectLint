import Foundation
import SwiftProjectLintModels
import SwiftSyntax

extension BasePatternVisitor {
    /// Returns `true` if the current file path indicates a test, example,
    /// fixture, mock, or sample file that should generally be excluded from
    /// lint rules.
    public func isTestOrFixtureFile() -> Bool {
        Self.isTestOrFixturePath(filePath)
    }

    /// Returns `true` if `filePath` indicates a test, example, fixture, mock, or
    /// sample file. The one definition of "test file" — rules reach it through
    /// `isTestOrFixtureFile()`, and `SourcePatternDetector` calls it directly.
    public static func isTestOrFixturePath(_ filePath: String) -> Bool {
        // Directory-based: a *containing folder* is a test target or fixture root.
        // Matching whole path components (not raw substrings) means a production
        // file that merely mentions a marker mid-name — e.g.
        // `.../SubclassedForMockingVisitor.swift`, where "Mocking" contains "Mock" —
        // is not mistaken for a fixture.
        for component in PathString.components(of: filePath).dropLast() {
            if ConstructionUniverse.isTestTargetDirectory(component) {
                return true // SPM `Tests/` and Xcode `FooTests/` target folders
            }
            if Self.testSupportDirectorySuffixes.contains(where: component.hasSuffix) {
                return true
            }
            if Self.fixtureDirectoryNames.contains(component) {
                return true
            }
        }

        // File-name-based: standard test / fixture file names.
        let fileName = PathString.lastComponent(of: filePath)
        if fileName.hasSuffix("Test.swift") || fileName.hasSuffix("Tests.swift")
            || fileName.hasSuffix("Examples.swift") || fileName.hasSuffix("Samples.swift") {
            return true
        }

        // Test doubles: a Mock/Fake/Stub/Spy marker at a camelCase boundary — the
        // whole stem (`Mocks.swift`), a suffix (`ClientMock.swift`), or a prefix
        // before an uppercase letter (`MockClient.swift`) — never an inner
        // substring (`MockingbirdConfig.swift` stays production).
        let baseName = PathString.deletingExtension(of: fileName)
        return Self.testDoubleMarkers.contains { marker in
            if baseName == marker || baseName.hasSuffix(marker) {
                return true
            }
            guard baseName.hasPrefix(marker),
                  let next = baseName.dropFirst(marker.count).first else {
                return false
            }
            return next.isUppercase
        }
    }

    /// Suffixes of folder names whose whole contents exist to serve tests, even
    /// though the folder is a shipped target rather than a test target.
    ///
    /// `SwiftLintRuleStudioCoreTestSupport` is a library product — it compiles into
    /// the app graph and is not a `Tests/` folder — but every symbol in it exists
    /// to be called from a test, and its helpers are *deliberately* nondeterministic:
    /// a per-test `UserDefaults` suite name, a per-process scratch root, a unique
    /// directory per call. Reporting those is the tool failing to read an intent the
    /// author stated in the target's name.
    ///
    /// Suffix-matched rather than exact, so `FooTestSupport` and `TestSupport` both
    /// count, and split from `fixtureDirectoryNames` because that set is exact-match
    /// and adding open-ended names to it would widen every entry.
    private static let testSupportDirectorySuffixes = [
        "TestSupport", "TestHelpers", "TestKit", "TestFixtures"
    ]

    /// Folder names whose contents are test fixtures, samples, or doubles rather
    /// than production code. Matched against whole path components.
    private static let fixtureDirectoryNames: Set<String> = [
        "Mocks", "Fakes", "Stubs", "Fixtures", "Examples", "Samples", "ExampleCode"
    ]

    /// Test-double name markers, matched only at camelCase boundaries within a file
    /// name (singular and plural forms) so production code is not swept in.
    private static let testDoubleMarkers = [
        "Mock", "Mocks", "Fake", "Fakes", "Stub", "Stubs", "Spy", "Spies"
    ]

    /// Adds a detected issue directly with explicit parameters.
    ///
    /// Use this method when you need to create issues with custom messages
    /// that don't come from the pattern template.
    ///
    /// - Parameters:
    ///   - severity: The severity level of the issue.
    ///   - message: The issue message.
    ///   - filePath: The file path where the issue was detected.
    ///   - lineNumber: The line number where the issue was detected.
    ///   - suggestion: Optional suggestion for fixing the issue.
    ///   - ruleName: The name of the rule that generated this issue; `nil`, the default, is this
    ///     visitor's own pattern.
    public func addIssue(
        severity: IssueSeverity,
        message: String,
        filePath: String,
        lineNumber: Int,
        suggestion: String,
        ruleName: RuleIdentifier? = nil,
        symbol: String? = nil,
        role: PBTSeedRole? = nil,
        effect: PBTSeedEffect? = nil,
        testReachability: TestReachability = .unknown,
        requires: PBTSeedRequirement? = nil,
        mutates: String? = nil
    ) {
        let issue = LintIssue(
            severity: severity,
            message: message,
            filePath: filePath,
            lineNumber: lineNumber,
            suggestion: suggestion,
            ruleName: ruleName ?? pattern.name,
            symbol: symbol,
            role: role,
            effect: effect,
            testReachability: testReachability,
            requires: requires,
            mutates: mutates
        )
        detectedIssues.append(issue)
    }
}
