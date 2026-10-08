import Foundation

/// Finds the source files a project compiles with default MainActor isolation (SE-0466).
///
/// In such a target every declaration without isolation of its own is `@MainActor`, and nothing
/// in the file says so: the setting lives in the build configuration. Xcode 26 turns it on for new
/// app targets. `Blocking I/O On Main Actor` reads this to know that an unannotated helper there
/// runs on the main actor.
///
/// Both build systems are read, and a file counts if either compiles it that way:
/// - **SwiftPM:** `.defaultIsolation(MainActor.self)` in a target's `swiftSettings`, written
///   inline or through a `let` the manifest declares (`let uiSettings: [SwiftSetting] = [...]`,
///   the usual form). Read as text, like ``ExecutableTargetDetector``. A manifest is not parsed
///   here because a deep one overflows a concurrency thread's stack (`LargeStackWorkers`).
/// - **Xcode:** `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` in a native target's build settings,
///   or the project's, for the folders it synchronizes and the files its Sources phase lists
///   (``XcodeDefaultIsolation``).
public enum DefaultIsolationDetector {

    /// Root-relative paths, sorted. One ending in `/` covers every file below it; any other names
    /// one file. `BasePatternVisitor.isDefaultMainActorSource(_:)` reads them.
    public static func mainActorSourcePaths(in projectRoot: String) -> [String] {
        var paths: Set<String> = []
        let packages = [(relative: "", absolute: projectRoot)]
            + NestedPackageWalker.packageDirectories(in: projectRoot)
        for package in packages {
            let manifestPath = (package.absolute as NSString).appendingPathComponent("Package.swift")
            guard let manifest = try? String(contentsOfFile: manifestPath, encoding: .utf8) else { continue }
            paths.formUnion(targetPaths(manifest: manifest).map { package.relative + $0 })
        }
        paths.formUnion(XcodeDefaultIsolation.sourcePaths(in: projectRoot))
        return paths.sorted()
    }

    // MARK: - SwiftPM

    /// Source directories (`Sources/App/`) of the targets `manifest` compiles with default
    /// MainActor isolation.
    static func targetPaths(manifest: String) -> [String] {
        let code = ManifestText.strippingComments(manifest)
        let names = mainActorSettingNames(in: code)
        guard let marker = try? NSRegularExpression(pattern: #"\.(?:executableTarget|target)\s*\("#) else {
            return []
        }
        return marker.matches(in: code, range: NSRange(code.startIndex..., in: code)).compactMap { match in
            guard let range = Range(match.range, in: code),
                  let arguments = ExecutableTargetDetector.balancedArgs(in: code, from: range.upperBound),
                  let settings = ManifestText.argument("swiftSettings", in: arguments),
                  setsMainActorDefault(settings, names: names),
                  let name = ManifestText.stringArgument("name", in: arguments) else { return nil }
            let path = ManifestText.stringArgument("path", in: arguments) ?? "Sources/\(name)"
            return path.hasSuffix("/") ? path : path + "/"
        }
    }

    /// Top-level `let`/`var` names whose value sets the default, directly or through a name
    /// collected before it: `let ui = base + [.defaultIsolation(MainActor.self)]`.
    static func mainActorSettingNames(in code: String) -> Set<String> {
        var names: Set<String> = []
        for declaration in ManifestText.topLevelDeclarations(in: code)
            where setsMainActorDefault(declaration.value, names: names) {
            names.insert(declaration.name)
        }
        return names
    }

    private static func setsMainActorDefault(_ expression: String, names: Set<String>) -> Bool {
        let setting = #"\.defaultIsolation\s*\(\s*MainActor\.self\s*\)"#
        if expression.range(of: setting, options: .regularExpression) != nil {
            return true
        }
        return names.contains { name in
            expression.range(of: #"\b\#(name)\b"#, options: .regularExpression) != nil
        }
    }
}
