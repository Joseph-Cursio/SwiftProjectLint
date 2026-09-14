import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// Cross-file visitor that reports a declared dependency — a sibling target, or a product of a local
/// path package — that nothing in the target imports.
///
/// The mirror of ``UndeclaredTargetDependencyVisitor``. A stale entry in `dependencies:` does not
/// break a build, but it keeps one: the target is rebuilt whenever the dependency changes, and the
/// manifest goes on claiming a coupling the source no longer has — which is exactly the record a
/// reader consults to learn how the package is layered.
///
/// A dependency counts as used when the target imports it, imports something that re-exports it
/// through `@_exported import` (followed transitively), or names it in `#externalMacro(module:)`.
///
/// **Only a dependency the rule can see is judged.** Unused-ness is a claim about every file of the
/// importing target and about the dependency's module name, so the rule declines when either is in
/// doubt:
/// - The importing target has no Swift files in the run (excluded, or not a Swift target).
/// - The dependency has no Swift files in the run. A C target's module name comes from its module
///   map, not its target name, so `import zlib` can be how `CZlib` is used.
/// - The dependency is an executable, plugin, system library or binary target. A test target can
///   depend on an executable only to have it built, and the other three are not imported by their
///   target name.
/// - A product of a package outside the run (remote, or a path the graph cannot follow), or of a
///   local package whose product cannot be matched.
/// - A local package's product any of whose targets has no Swift files in the run, for the same
///   module-map reason as a C sibling target.
final class UnusedTargetDependencyVisitor: CrossFileVisitorBase, CrossFilePatternVisitorProtocol {

    func finalizeAnalysis() {
        let graph = PackageGraph(fileCache: fileCache)
        for node in graph.nodes {
            analyze(node, in: graph)
        }
    }

    private func analyze(_ node: PackageGraph.Node, in graph: PackageGraph) {
        let imports = node.imports
        let package = node.package
        let manifestPath = package.manifest.directory + "Package.swift"

        for target in package.manifest.targets where target.kind != .plugin {
            guard let dependencies = target.dependencies,
                  let files = package.filesByTarget[target.name], files.isEmpty == false else {
                continue
            }

            let imported = Set((imports.sitesByTarget[target.name] ?? []).map(\.module))
            let used = graph.withReexports(of: imported).union(externalMacroModules(in: files))

            for dependency in dependencies {
                guard let unused = unusedDependency(dependency, resolvedIn: node, graph: graph, used: used) else {
                    continue
                }
                addIssue(
                    severity: .info,
                    message: "Target '\(target.name)' declares a dependency on \(unused.description) "
                        + "but never imports it",
                    filePath: manifestPath,
                    lineNumber: getLineNumber(for: dependency.node),
                    suggestion: "Remove \(unused.entry) from the dependencies of '\(target.name)', or import "
                        + "it where it is used. An unused dependency still rebuilds '\(target.name)' "
                        + "whenever it changes.",
                    ruleName: .unusedTargetDependency
                )
            }
        }
    }

    /// How a judged, unused dependency is named in the finding: as prose, and as the manifest entry.
    private struct UnusedDependency {
        let description: String
        let entry: String
    }

    private func unusedDependency(
        _ dependency: PackageManifest.Dependency,
        resolvedIn node: PackageGraph.Node,
        graph: PackageGraph,
        used: Set<String>
    ) -> UnusedDependency? {
        switch graph.resolve(dependency, in: node) {
        case .localTarget(let dependencyTarget):
            guard isJudgeable(dependencyTarget, in: node.package),
                  used.contains(dependencyTarget.moduleName) == false else {
                return nil
            }
            return UnusedDependency(description: "'\(dependencyTarget.name)'", entry: "\"\(dependencyTarget.name)\"")

        case let .product(product, modules, package):
            let productTargets = product.targets.compactMap { package.imports.targetsByName[$0] }
            guard productTargets.count == product.targets.count,
                  productTargets.allSatisfy({ isJudgeable($0, in: package.package) }),
                  modules.isDisjoint(with: used) else {
                return nil
            }
            let reference = graph.packageReference(to: package, from: node)
            return UnusedDependency(
                description: "product '\(product.name)' of '\(reference)'",
                entry: dependency.isPackageProduct
                    ? ".product(name: \"\(product.name)\", package: \"\(dependency.package ?? reference)\")"
                    : "\"\(product.name)\""
            )

        case .unresolvedProduct, .external:
            return nil
        }
    }

    private func isJudgeable(
        _ dependency: PackageManifest.Target,
        in package: PackageTargetSources.Package
    ) -> Bool {
        guard dependency.kind == .regular || dependency.kind == .macro else { return false }
        return package.filesByTarget[dependency.name]?.isEmpty == false
    }

    /// The modules named by `#externalMacro(module: "…")` in `files` — how a library uses the macro
    /// target it depends on without importing it.
    private func externalMacroModules(in files: [String]) -> Set<String> {
        let collector = ExternalMacroModuleCollector(viewMode: .sourceAccurate)
        for file in files {
            if let source = fileCache[file] {
                collector.walk(source)
            }
        }
        return collector.modules
    }
}

private final class ExternalMacroModuleCollector: SyntaxVisitor {
    private(set) var modules: Set<String> = []

    override func visit(_ node: MacroExpansionExprSyntax) -> SyntaxVisitorContinueKind {
        guard node.macroName.text == "externalMacro",
              let argument = node.arguments.first(where: { $0.label?.text == "module" }),
              let literal = argument.expression.as(StringLiteralExprSyntax.self),
              let segment = literal.segments.first?.as(StringSegmentSyntax.self),
              literal.segments.count == 1 else {
            return .visitChildren
        }
        modules.insert(PackageManifest.c99Identifier(segment.content.text))
        return .visitChildren
    }
}
