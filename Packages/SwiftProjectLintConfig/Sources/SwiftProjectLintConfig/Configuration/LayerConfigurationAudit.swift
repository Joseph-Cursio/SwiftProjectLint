import SwiftProjectLintModels

/// Mistakes in `architectural_layers` that make the layer rules report less than the author meant,
/// without saying so.
///
/// Every one of these fails quietly. A misspelled path puts no file in the layer, so neither layer
/// rule has anything to judge; a misspelled `may_depend_on` entry permits a layer that does not
/// exist, so the layer it was meant to permit is reported instead — or, if nothing references it,
/// nothing is; and two layers permitting each other are no longer layered at all. A clean run over
/// any of them looks exactly like a clean architecture.
public enum LayerConfigurationAudit {

    public enum Problem: Equatable, Sendable {
        /// A layer path under which no analysed file lives.
        case pathMatchesNoFile(layer: String, path: String)
        /// A `may_depend_on` entry naming no configured layer.
        case unknownDependency(layer: String, dependency: String)
        /// Layers that may depend on one another, sorted, with one cycle through them.
        case cycle(layers: [String], path: [String])
    }

    /// The problems in `layers`, given the root-relative paths of the files the run analysed.
    public static func problems(in layers: [LayerPolicy], analysedFiles: [String]) -> [Problem] {
        let sorted = layers.sorted { $0.name < $1.name }
        let names = Set(sorted.map(\.name))

        var problems: [Problem] = []
        for layer in sorted {
            for path in layer.paths.sorted() where analysedFiles.contains(where: { $0.hasPrefix(path) }) == false {
                problems.append(.pathMatchesNoFile(layer: layer.name, path: path))
            }
            for dependency in (layer.mayDependOn ?? []).sorted() where names.contains(dependency) == false {
                problems.append(.unknownDependency(layer: layer.name, dependency: dependency))
            }
        }
        return problems + cycles(in: sorted, names: names)
    }

    /// One line per problem, for stderr.
    public static func notice(for problems: [Problem]) -> String {
        let lines = problems.map { problem -> String in
            switch problem {
            case let .pathMatchesNoFile(layer, path):
                return "  layer '\(layer)': path '\(path)' matches no analysed file, so nothing in it is checked."

            case let .unknownDependency(layer, dependency):
                return "  layer '\(layer)': may_depend_on names '\(dependency)', but no layer has that name."

            case let .cycle(_, path):
                return "  layers \(path.map { "'\($0)'" }.joined(separator: " → ")) may depend on each other, "
                    + "so they are not layered."
            }
        }
        return """
            Warning: architectural_layers has \(problems.count) problem\(problems.count == 1 ? "" : "s") \
            that make the layer rules check less than configured.
            \(lines.joined(separator: "\n"))
            """
    }

    // MARK: - Cycles

    /// Each group of layers that can reach one another through `may_depend_on`, reported once.
    /// A layer listing itself is not a cycle: a layer may always use its own types.
    private static func cycles(in layers: [LayerPolicy], names: Set<String>) -> [Problem] {
        let edges = Dictionary(uniqueKeysWithValues: layers.map { layer in
            (layer.name, (layer.mayDependOn ?? []).filter { names.contains($0) && $0 != layer.name }.sorted())
        })

        var reported: Set<Set<String>> = []
        var problems: [Problem] = []
        for layer in layers.map(\.name) {
            let group = Set(reachable(from: layer, edges: edges).filter {
                reachable(from: $0, edges: edges).contains(layer)
            }).union([layer])
            guard group.count > 1, reported.insert(group).inserted,
                  let path = cyclePath(from: layer, within: group, edges: edges) else {
                continue
            }
            problems.append(.cycle(layers: group.sorted(), path: path))
        }
        return problems
    }

    private static func reachable(from start: String, edges: [String: [String]]) -> Set<String> {
        var seen: Set<String> = []
        var pending = edges[start] ?? []
        while let next = pending.popLast() {
            guard seen.insert(next).inserted else { continue }
            pending.append(contentsOf: edges[next] ?? [])
        }
        return seen
    }

    /// A shortest route from `start` back to itself, staying inside `group`.
    private static func cyclePath(from start: String, within group: Set<String>, edges: [String: [String]]) -> [String]? {
        var queue: [[String]] = [[start]]
        var visited: Set<String> = []
        while queue.isEmpty == false {
            let route = queue.removeFirst()
            guard let last = route.last else { continue }
            for next in edges[last] ?? [] where group.contains(next) {
                if next == start { return route + [start] }
                if visited.insert(next).inserted { queue.append(route + [next]) }
            }
        }
        return nil
    }
}
