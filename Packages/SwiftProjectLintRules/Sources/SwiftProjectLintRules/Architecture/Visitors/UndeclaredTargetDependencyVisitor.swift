import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// Cross-file visitor that reports a target importing a module it never declared.
///
/// SwiftPM does not check a target's imports against its `dependencies:`. A module is importable
/// whenever it has been built before the importing target compiles, and a module that some *other*
/// dependency pulls in has been. So `Checkout` can `import Persistence` with only `Domain` declared,
/// provided `Domain` depends on `Persistence` — and it keeps compiling until that edge is removed,
/// at which point a target nobody touched stops building. With parallel builds it can also fail
/// intermittently, when the scheduler happens to compile the importer first.
///
/// **Which modules are judged.** The targets of the importing target's own package, and the targets
/// of every package reachable through `.package(path:)` dependencies whose manifest is in the run.
/// An import of anything else — Foundation, a remote package, a path package outside the analysed
/// tree — is not a finding, because the rule cannot see which modules that package vends.
///
/// Not reported:
/// - An import satisfied by an `@_exported import` in a declared dependency, followed transitively
///   and across packages. The module is then part of the declared dependency's interface.
/// - Modules of a path package the target declares a product of that the rule cannot match — the
///   product list is unreadable, or names no such product — along with what they re-export. That
///   declaration could be what makes the import legitimate.
/// - An import inside `#if canImport(Module)`, which is written to compile without the module.
/// - Plugin targets, and targets whose dependency list is not a literal.
///
/// Each undeclared module is reported once per target, at its first import in path order, since the
/// fix is one line in `Package.swift` however many files import it.
final class UndeclaredTargetDependencyVisitor: CrossFileVisitorBase, CrossFilePatternVisitorProtocol {

    /// Where a judged module comes from, which decides the dependency the finding suggests adding.
    private enum Origin {
        case localTarget
        case pathPackage(PackageGraph.Node)
    }

    /// What a target's dependency list settles about the modules it may import.
    private struct Declaration {
        var declared: Set<String> = []
        /// Directories of path packages the target declares a product of that could not be matched.
        var unmatchedPackages: Set<String> = []
    }

    func finalizeAnalysis() {
        let graph = PackageGraph(fileCache: fileCache)
        for node in graph.nodes {
            analyze(node, in: graph)
        }
    }

    private func analyze(_ node: PackageGraph.Node, in graph: PackageGraph) {
        let reachablePackages = graph.reachablePathPackages(of: node)

        for target in node.targets where target.kind != .plugin {
            guard let dependencies = target.dependencies else { continue }

            let declaration = declaration(of: dependencies, in: node, graph: graph)
            let (origins, exempt) = judgedModules(
                of: node, reachablePackages: reachablePackages, unmatched: declaration.unmatchedPackages
            )
            let permitted = graph.withReexports(of: declaration.declared.union(exempt))

            let undeclared = (node.imports.sitesByTarget[target.name] ?? []).filter { site in
                site.module != target.moduleName
                    && origins[site.module] != nil
                    && permitted.contains(site.module) == false
                    && site.isGuardedByCanImport == false
            }
            report(undeclared, in: target, of: node, origins: origins, graph: graph)
        }
    }

    private func declaration(
        of dependencies: [PackageManifest.Dependency],
        in node: PackageGraph.Node,
        graph: PackageGraph
    ) -> Declaration {
        var declaration = Declaration()
        for dependency in dependencies {
            switch graph.resolve(dependency, in: node) {
            case .localTarget(let dependencyTarget):
                declaration.declared.insert(dependencyTarget.moduleName)

            case .product(_, let modules, _):
                declaration.declared.formUnion(modules)

            case .unresolvedProduct(let packages):
                declaration.unmatchedPackages.formUnion(packages.map(\.directory))

            case .external:
                break
            }
        }
        return declaration
    }

    /// The modules this rule judges, each with its origin, and the modules of unmatched packages,
    /// which are exempt rather than judged.
    private func judgedModules(
        of node: PackageGraph.Node,
        reachablePackages: [PackageGraph.Node],
        unmatched: Set<String>
    ) -> (origins: [String: Origin], exempt: Set<String>) {
        var origins: [String: Origin] = [:]
        for local in node.targets {
            origins[local.moduleName] = .localTarget
        }

        var exempt: Set<String> = []
        for package in reachablePackages {
            let modules = package.targets.map(\.moduleName)
            guard unmatched.contains(package.directory) == false else {
                exempt.formUnion(modules)
                continue
            }
            for module in modules where origins[module] == nil {
                origins[module] = .pathPackage(package)
            }
        }
        return (origins, exempt)
    }

    // MARK: - Reporting

    private func report(
        _ sites: [PackageTargetImports.Site],
        in target: PackageManifest.Target,
        of node: PackageGraph.Node,
        origins: [String: Origin],
        graph: PackageGraph
    ) {
        let sitesByModule = Dictionary(grouping: sites, by: \.module)
        for module in sitesByModule.keys.sorted() {
            guard let moduleSites = sitesByModule[module], let first = moduleSites.first,
                  let origin = origins[module] else {
                continue
            }
            let otherFiles = Set(moduleSites.map(\.file)).count - 1
            let spread = otherFiles == 0 ? ""
                : " (and \(otherFiles) other file\(otherFiles == 1 ? "" : "s"))"

            let suggestion: String
            switch origin {
            case .localTarget:
                suggestion = "Add \"\(module)\" to the dependencies of '\(target.name)' in Package.swift. "
                    + Self.consequence

            case .pathPackage(let package):
                suggestion = productSuggestion(for: module, from: package, in: target, of: node, graph: graph)
            }

            addIssue(
                severity: .warning,
                message: "Target '\(target.name)' imports '\(module)'\(spread) "
                    + "without declaring it as a dependency",
                filePath: first.file,
                lineNumber: getLineNumber(for: Syntax(first.node)),
                suggestion: suggestion,
                ruleName: .undeclaredTargetDependency
            )
        }
    }

    private static let consequence = "It builds today only because another dependency happens to build it first."

    private func productSuggestion(
        for module: String,
        from package: PackageGraph.Node,
        in target: PackageManifest.Target,
        of node: PackageGraph.Node,
        graph: PackageGraph
    ) -> String {
        let direct = graph.directPathPackages(of: node).first {
            $0.package.directory == package.directory
        }
        let identity = graph.packageReference(to: package, from: node)

        // Prefer a product named after the module, then the smallest product that vends it.
        let vending = (package.libraryProducts ?? [])
            .filter { product in
                product.targets.contains { package.imports.targetsByName[$0]?.moduleName == module }
            }
            .min { lhs, rhs in
                let lhsRank = (lhs.name == module ? 0 : 1, lhs.targets.count, lhs.name)
                let rhsRank = (rhs.name == module ? 0 : 1, rhs.targets.count, rhs.name)
                return lhsRank < rhsRank
            }

        guard let product = vending else {
            return "No library product of '\(identity)' vends '\(module)', so '\(target.name)' can import it "
                + "only because a dependency builds it. Import a product of '\(identity)' instead, or add a "
                + "library product for '\(module)'."
        }

        let addPackage = direct == nil
            ? " Also add '\(identity)' to this package's dependencies; it is reached only through another package."
            : ""
        return "Add .product(name: \"\(product.name)\", package: \"\(identity)\") to the dependencies of "
            + "'\(target.name)' in Package.swift.\(addPackage) \(Self.consequence)"
    }
}
