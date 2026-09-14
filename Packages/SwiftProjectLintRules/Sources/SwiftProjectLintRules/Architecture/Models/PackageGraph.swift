import SwiftSyntax

/// Every readable package in a run, connected through `.package(path:)` dependencies.
///
/// A `.product(name:package:)` dependency names modules that another manifest lists. When that
/// manifest is a path dependency inside the analysed tree — a local package under `Packages/`, say,
/// on a run with `include_nested_packages` — it is already parsed, and following the path is enough
/// to learn which modules the product vends. A package whose manifest is not in the run (outside
/// the tree, pruned, or unreadable) is simply not reached, and nothing it vends is judged.
struct PackageGraph {

    struct Node {
        let package: PackageTargetSources.Package
        let imports: PackageTargetImports

        var manifest: PackageManifest { package.manifest }
    }

    /// What one entry of a target's `dependencies:` turns out to name.
    enum ResolvedDependency {
        /// A target of the same manifest.
        case localTarget(PackageManifest.Target)
        /// A library product of a path dependency, with the modules it vends.
        case product(PackageManifest.LibraryProduct, modules: Set<String>, package: Node)
        /// Could name a product of these path dependencies in the run, but none can be matched —
        /// the product list is unreadable, or has no product of that name. Anything those packages
        /// vend is unjudgeable.
        case unresolvedProduct(packages: [Node])
        /// A package outside the run: a remote dependency, or a path the graph could not follow.
        case external
    }

    /// Sorted by manifest directory, so findings come out in the same order on every run.
    let nodes: [Node]
    private let nodesByDirectory: [String: Node]
    private let reexportsByModule: [String: Set<String>]

    init(fileCache: [String: SourceFileSyntax]) {
        nodes = PackageTargetSources(fileCache: fileCache).packages.map { package in
            Node(package: package, imports: PackageTargetImports(package: package, fileCache: fileCache))
        }
        nodesByDirectory = Dictionary(nodes.map { ($0.manifest.directory, $0) }) { first, _ in first }

        var reexports: [String: Set<String>] = [:]
        for node in nodes {
            for target in node.manifest.targets {
                let exported = (node.imports.sitesByTarget[target.name] ?? []).filter(\.isExported)
                reexports[target.moduleName, default: []].formUnion(exported.map(\.module))
            }
        }
        reexportsByModule = reexports
    }

    // MARK: - Path dependencies

    /// The packages `node` declares as `.package(path:)` dependencies and the run contains.
    func directPathPackages(of node: Node) -> [(dependency: PackageManifest.PathDependency, package: Node)] {
        node.manifest.pathDependencies.compactMap { dependency in
            Self.resolve(dependency.path, from: node.manifest.directory)
                .flatMap { nodesByDirectory[$0] }
                .map { (dependency: dependency, package: $0) }
        }
    }

    /// Every package reachable from `node` through path dependencies, not including `node`.
    func reachablePathPackages(of node: Node) -> [Node] {
        var visited: Set<String> = [node.manifest.directory]
        var reached: [Node] = []
        var pending = [node]
        while let current = pending.popLast() {
            for (_, package) in directPathPackages(of: current)
            where visited.contains(package.manifest.directory) == false {
                visited.insert(package.manifest.directory)
                reached.append(package)
                pending.append(package)
            }
        }
        return reached.sorted { $0.manifest.directory < $1.manifest.directory }
    }

    // MARK: - Dependencies

    func resolve(_ dependency: PackageManifest.Dependency, in node: Node) -> ResolvedDependency {
        if dependency.isPackageProduct == false, let target = node.imports.targetsByName[dependency.name] {
            return .localTarget(target)
        }

        // SwiftPM resolves a product only among the package's *direct* dependencies. A plain string
        // that is not a local target may name a product of any of them.
        let candidates = directPathPackages(of: node).filter { entry in
            guard let package = dependency.package else { return true }
            return Self.names(package, entry.dependency, entry.package.manifest)
        }

        var unmatched: [Node] = []
        for (_, package) in candidates {
            guard let products = package.manifest.libraryProducts else {
                unmatched.append(package)
                continue
            }
            if let product = products.first(where: { $0.name == dependency.name }) {
                let modules = product.targets.compactMap { package.imports.targetsByName[$0]?.moduleName }
                return .product(product, modules: Set(modules), package: package)
            }
            // A named package that lacks the product is still that package; an unnamed string is
            // only unresolved where a product list could not be read.
            if dependency.package != nil {
                unmatched.append(package)
            }
        }
        return unmatched.isEmpty ? .external : .unresolvedProduct(packages: unmatched)
    }

    /// `modules` plus every module re-exported, transitively, by a module already in the set — across
    /// every package in the run, since `@_exported import` carries a module over package boundaries.
    func withReexports(of modules: Set<String>) -> Set<String> {
        var reachable = modules
        var pending = Array(modules)
        while let module = pending.popLast() {
            for reexported in reexportsByModule[module] ?? [] where reachable.contains(reexported) == false {
                reachable.insert(reexported)
                pending.append(reexported)
            }
        }
        return reachable
    }

    /// How `node`'s manifest names `package` in a `.product(name:package:)`: the spelling it already
    /// uses for that package, else the path dependency's identity, else the identity of the directory
    /// the author would add a dependency on.
    func packageReference(to package: Node, from node: Node) -> String {
        let direct = directPathPackages(of: node).first {
            $0.package.manifest.directory == package.manifest.directory
        }
        if let direct {
            let spellings = node.manifest.targets
                .flatMap { $0.dependencies ?? [] }
                .compactMap(\.package)
            if let spelling = spellings.first(where: { Self.names($0, direct.dependency, package.manifest) }) {
                return spelling
            }
            if let identity = direct.dependency.identity {
                return identity
            }
        }
        // Not yet a dependency: the path the author would add ends in the package's directory, which
        // is its identity. Only the analysed root has no directory name to read.
        return package.manifest.directory.split(separator: "/").last.map { $0.lowercased() }
            ?? package.manifest.packageName
            ?? ""
    }

    // MARK: - Helpers

    /// Whether `package:` in a product dependency names this path dependency: its SwiftPM identity,
    /// the `name:` of the older `.package(name:path:)` spelling, or the manifest's own package name.
    private static func names(
        _ package: String,
        _ dependency: PackageManifest.PathDependency,
        _ manifest: PackageManifest
    ) -> Bool {
        (dependency.identity.map { package.lowercased() == $0 } ?? false)
            || package == dependency.name
            || package == manifest.packageName
    }

    /// `path` resolved against `directory`, as a root-relative directory with a trailing `/`, or
    /// `nil` when it is absolute or climbs above the analysed root.
    static func resolve(_ path: String, from directory: String) -> String? {
        guard path.hasPrefix("/") == false else { return nil }
        var components = directory.split(separator: "/").map(String.init)
        for component in path.split(separator: "/").map(String.init) {
            switch component {
            case "", ".":
                continue

            case "..":
                guard components.isEmpty == false else { return nil }
                components.removeLast()

            default:
                components.append(component)
            }
        }
        return components.isEmpty ? "" : components.joined(separator: "/") + "/"
    }
}
