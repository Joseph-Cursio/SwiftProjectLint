import Foundation

/// Reads `SWIFT_DEFAULT_ACTOR_ISOLATION` from the Xcode projects under a root.
///
/// A `project.pbxproj` is an old-style property list, which `PropertyListSerialization` reads. A
/// native target compiles with default MainActor isolation when one of its build configurations
/// (or, failing that, one of the project's) sets the key to `MainActor`. Its sources are:
/// - the folders it synchronizes (`fileSystemSynchronizedGroups`, Xcode 16 and later), and
/// - the files its Sources build phase lists, each resolved through its group chain.
///
/// Not read: settings from `.xcconfig` files, and the exceptions a synchronized folder lists for a
/// target (files it does *not* compile).
enum XcodeDefaultIsolation {

    /// Root-relative paths from every Xcode project under `projectRoot`: a folder ending in `/`,
    /// or one file.
    static func sourcePaths(in projectRoot: String) -> [String] {
        projectDirectories(in: projectRoot).flatMap { project -> [String] in
            let pbxproj = (project.absolute as NSString).appendingPathComponent("project.pbxproj")
            guard let data = FileManager.default.contents(atPath: pbxproj) else { return [] }
            return sourcePaths(pbxproj: data, projectDirectory: project.parent)
        }
    }

    /// The paths one `project.pbxproj` compiles with default MainActor isolation, relative to the
    /// analysed root. `projectDirectory` is the root-relative folder holding the `.xcodeproj`,
    /// `""` at the root.
    static func sourcePaths(pbxproj data: Data, projectDirectory: String) -> [String] {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = plist as? [String: Any],
              let objects = dictionary["objects"] as? [String: [String: Any]],
              let rootID = dictionary["rootObject"] as? String,
              let project = objects[rootID] else { return [] }
        let graph = ProjectGraph(objects: objects, projectDirectory: projectDirectory)
        let projectSetting = graph.isolationSetting(configurationList: project["buildConfigurationList"])
        return (project["targets"] as? [String] ?? []).flatMap { targetID -> [String] in
            guard let target = objects[targetID], target["isa"] as? String == "PBXNativeTarget" else { return [] }
            // A target's own setting overrides the project's.
            let setting = graph.isolationSetting(configurationList: target["buildConfigurationList"]) ?? projectSetting
            return setting == "MainActor" ? graph.sourcePaths(of: target) : []
        }
    }

    /// Each `.xcodeproj` under `projectRoot`: its absolute path, and the root-relative folder
    /// holding it (`""` at the root, otherwise ending in `/`).
    private static func projectDirectories(in projectRoot: String) -> [(absolute: String, parent: String)] {
        // Enumerated at the canonical root: see `ProjectRoot.url`.
        let root = ProjectRoot(projectRoot)
        guard let enumerator = FileManager.default.enumerator(
            at: root.url, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles
        ) else { return [] }
        var found: [(absolute: String, parent: String)] = []
        for case let itemURL as URL in enumerator {
            if FileAnalysisUtils.skippedDirectories.contains(itemURL.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            guard itemURL.pathExtension == "xcodeproj" else { continue }
            // A project bundle holds no other project.
            enumerator.skipDescendants()
            guard let parent = root.relativePath(of: itemURL.deletingLastPathComponent().path) else { continue }
            found.append((itemURL.path, parent.isRoot ? "" : parent.value + "/"))
        }
        return found.sorted { $0.absolute < $1.absolute }
    }
}

/// The object graph of one `project.pbxproj`.
private struct ProjectGraph {
    let objects: [String: [String: Any]]
    let projectDirectory: String

    private static let settingKey = "SWIFT_DEFAULT_ACTOR_ISOLATION"

    /// Each group or file reference's parent group.
    private let parents: [String: String]

    init(objects: [String: [String: Any]], projectDirectory: String) {
        self.objects = objects
        self.projectDirectory = projectDirectory
        var parents: [String: String] = [:]
        for (identifier, object) in objects {
            for child in object["children"] as? [String] ?? [] {
                parents[child] = identifier
            }
        }
        self.parents = parents
    }

    /// The default isolation a configuration list sets: `MainActor` if any of its configurations
    /// (Debug, Release, …) says so, otherwise the first value set, or `nil` when none sets it.
    func isolationSetting(configurationList: Any?) -> String? {
        guard let listID = configurationList as? String,
              let configurations = objects[listID]?["buildConfigurations"] as? [String] else { return nil }
        let values = configurations.compactMap { identifier in
            (objects[identifier]?["buildSettings"] as? [String: Any])?[Self.settingKey] as? String
        }
        return values.contains("MainActor") ? "MainActor" : values.first
    }

    /// The synchronized folders (ending in `/`) and listed source files of a native target.
    func sourcePaths(of target: [String: Any]) -> [String] {
        let folders = (target["fileSystemSynchronizedGroups"] as? [String] ?? []).compactMap { identifier in
            path(of: identifier).map { $0 + "/" }
        }
        let files = (target["buildPhases"] as? [String] ?? [])
            .filter { objects[$0]?["isa"] as? String == "PBXSourcesBuildPhase" }
            .flatMap { objects[$0]?["files"] as? [String] ?? [] }
            .compactMap { objects[$0]?["fileRef"] as? String }
            .compactMap { path(of: $0) }
        return folders + files
    }

    /// The root-relative path of a group, folder or file reference, or `nil` when it lives
    /// outside the project (an SDK, the build products, an absolute path).
    func path(of identifier: String, depth: Int = 0) -> String? {
        guard depth < 64, let object = objects[identifier] else { return nil }
        let own = object["path"] as? String
        switch object["sourceTree"] as? String ?? "<group>" {
        case "<group>":
            // The main group has no parent and sits at the project's folder.
            let base = parents[identifier].map { path(of: $0, depth: depth + 1) } ?? projectDirectory
            guard let base else { return nil }
            return Self.normalized(base + "/" + (own ?? ""))

        case "SOURCE_ROOT":
            return own.map { Self.normalized(projectDirectory + "/" + $0) }

        default:
            return nil
        }
    }

    /// `a/./b/../c` → `a/c`; empty components and a trailing `/` are dropped.
    private static func normalized(_ path: String) -> String {
        var components: [Substring] = []
        for component in path.split(separator: "/") where component != "." {
            if component == "..", let last = components.last, last != ".." {
                components.removeLast()
            } else {
                components.append(component)
            }
        }
        return components.joined(separator: "/")
    }
}
