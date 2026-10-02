import Foundation
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// Cross-file visitor that reports a Swift package whose manifests never enable the
/// `MemberImportVisibility` upcoming feature (SE-0444, Swift 6.1).
///
/// Without the feature, a file can use a module's extension members without importing that module,
/// as long as the module is loaded some other way: another file in the target imports it, or a
/// dependency does. The file then compiles because of an import it cannot see, and stops compiling
/// when that import moves — and SwiftPM and Xcode builds can disagree about whether it compiles.
/// With the feature on, each file has to import the modules whose members it uses, and the compiler
/// says which import is missing. No language mode enables it yet, so a package gets it only by
/// asking for it.
///
/// That a *file* relies on another file's import needs type information, which a syntax visitor does
/// not have. What it can see is whether the package lets the compiler check, so that is what it
/// reports: once per package, at its `Package.swift`, rather than once per target, since one
/// command fixes every target.
///
/// **Judged per package, not per target.** Manifests enable the feature in too many ways to resolve
/// it target by target: inline, through a shared `let swiftSettings`, or by appending to every
/// target in a `for target in package.targets` loop, sometimes under a condition. So any spelling
/// anywhere in any of the package's manifests (`Package.swift` or a `Package@swift-X.Y.swift`
/// variant) counts as enabled:
/// - the name as an unlabeled string — `.enableUpcomingFeature("MemberImportVisibility")`,
///   `.enableExperimentalFeature(…)`, an array element, a constant;
/// - a compiler flag carrying it, such as `"-enable-upcoming-feature MemberImportVisibility"`.
///
/// A target *named* `MemberImportVisibility` (`name: "MemberImportVisibility"`) does not count.
///
/// Not reported:
/// - A package in a test, fixture or example folder (`Tests/`, `Fixtures/`, `Examples/`, … — see
///   `isTestOrFixturePath`). Those are inputs to tests and samples for readers, and with
///   `--include-nested-packages` they outnumbered real packages: 170 findings in SwiftPM's
///   `Fixtures/` alone.
/// - A package with no Swift targets (only binary, system-library or plugin targets).
/// - A manifest whose `swift-tools-version` is below 5.8, which has no `.enableUpcomingFeature`.
///   Adopting the feature there means raising the tools version first, which is a decision about
///   which toolchains the package supports, not a missing setting.
/// - Xcode projects. Their setting, `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY`, is in the
///   `.pbxproj`, which this linter does not read.
final class MemberImportVisibilityNotEnabledVisitor: CrossFileVisitorBase, CrossFilePatternVisitorProtocol {

    static let featureName = "MemberImportVisibility"

    /// The first tools version whose `PackageDescription` has `.enableUpcomingFeature`.
    private static let minimumToolsVersion = (major: 5, minor: 8)

    private static let swiftTargetKinds: Set<PackageManifest.TargetKind> = [
        .regular, .executable, .test, .macro
    ]

    func finalizeAnalysis() {
        let manifestPaths = fileCache.keys.filter(PackageManifest.isManifestFile)
        let pathsByDirectory = Dictionary(grouping: manifestPaths, by: Self.directory(of:))

        for directory in pathsByDirectory.keys.sorted() {
            let manifestPath = directory + "Package.swift"
            guard let manifest = fileCache[manifestPath],
                  Self.isTestOrFixturePath(manifestPath) == false else {
                continue
            }

            let manifests = (pathsByDirectory[directory] ?? []).compactMap { fileCache[$0] }
            guard manifests.contains(where: Self.enablesFeature) == false,
                  Self.declaresSwiftTarget(manifest),
                  Self.supportsUpcomingFeatures(manifest) else {
                continue
            }
            report(manifest, at: manifestPath)
        }
    }

    // MARK: - Reading the manifest

    /// Whether any string literal in `manifest` turns the feature on.
    static func enablesFeature(_ manifest: SourceFileSyntax) -> Bool {
        manifest.tokens(viewMode: .sourceAccurate).contains { token in
            guard case .stringSegment(let content) = token.tokenKind,
                  content.contains(featureName),
                  let literal = enclosingLiteral(of: token) else {
                return false
            }
            if content == featureName {
                // A labeled argument names something (`name:`, `path:`); the feature is passed bare.
                return literal.parent?.as(LabeledExprSyntax.self)?.label == nil
            }
            // A flag such as `-enable-upcoming-feature MemberImportVisibility` in `unsafeFlags`.
            return content.hasPrefix("-")
        }
    }

    /// The string literal a segment token belongs to: segment → segment list → literal.
    private static func enclosingLiteral(of token: TokenSyntax) -> StringLiteralExprSyntax? {
        var node = token.parent
        while let current = node {
            if let literal = current.as(StringLiteralExprSyntax.self) { return literal }
            node = current.parent
        }
        return nil
    }

    /// Whether `manifest` declares a target the Swift compiler builds. A manifest whose targets
    /// cannot all be read is assumed to, since an unreadable target is still a target.
    static func declaresSwiftTarget(_ manifest: SourceFileSyntax) -> Bool {
        let collector = TargetDeclarationCollector(viewMode: .sourceAccurate)
        collector.walk(manifest)
        return collector.isReadable == false
            || collector.targets.contains { swiftTargetKinds.contains($0.kind) }
    }

    /// Whether the manifest's `swift-tools-version` is new enough for `.enableUpcomingFeature`.
    /// A manifest that states none is judged, since the rule cannot tell it is too old.
    static func supportsUpcomingFeatures(_ manifest: SourceFileSyntax) -> Bool {
        guard let version = toolsVersion(of: manifest) else { return true }
        return version.major > minimumToolsVersion.major
            || (version.major == minimumToolsVersion.major && version.minor >= minimumToolsVersion.minor)
    }

    /// The `// swift-tools-version:X.Y` comment, wherever in the leading comments it sits.
    static func toolsVersion(of manifest: SourceFileSyntax) -> (major: Int, minor: Int)? {
        let text = manifest.description
        guard let match = text.range(
            of: #"swift-tools-version:\s*\d+(\.\d+)?"#, options: .regularExpression
        ) else {
            return nil
        }
        let numbers = text[match]
            .drop { $0.isNumber == false }
            .split(separator: ".")
            .compactMap { Int($0) }
        guard let major = numbers.first else { return nil }
        return (major, numbers.dropFirst().first ?? 0)
    }

    private static func directory(of path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "" }
        return String(path[...slash])
    }

    // MARK: - Reporting

    private func report(_ manifest: SourceFileSyntax, at path: String) {
        let packageCollector = PackageDeclarationCollector(viewMode: .sourceAccurate)
        packageCollector.walk(manifest)
        let subject = packageCollector.packageName.map { "Package '\($0)'" } ?? "This package"

        addIssue(
            severity: .info,
            message: "\(subject) does not enable \(Self.featureName) (SE-0444), so a file can use "
                + "extension members from modules it does not import",
            filePath: path,
            lineNumber: getLineNumber(for: Self.packageCall(in: manifest).map(Syntax.init) ?? Syntax(manifest)),
            suggestion: "Run `swift package migrate --to-feature \(Self.featureName)` (Swift 6.2 or "
                + "later): it adds .enableUpcomingFeature(\"\(Self.featureName)\") to every target and "
                + "the imports each file was relying on. The compiler supports the feature from Swift 6.1.",
            ruleName: .memberImportVisibilityNotEnabled
        )
    }

    /// The `Package(…)` initializer call, where the finding is placed.
    private static func packageCall(in manifest: SourceFileSyntax) -> FunctionCallExprSyntax? {
        for token in manifest.tokens(viewMode: .sourceAccurate) where token.tokenKind == .identifier("Package") {
            if let call = token.parent?.parent?.as(FunctionCallExprSyntax.self),
               call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Package" {
                return call
            }
        }
        return nil
    }
}
