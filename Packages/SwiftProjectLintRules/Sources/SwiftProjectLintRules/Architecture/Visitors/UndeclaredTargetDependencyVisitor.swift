import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// Cross-file visitor that reports a target importing a sibling target it never declared.
///
/// SwiftPM does not check a target's imports against its `dependencies:`. A module is importable
/// whenever it has been built before the importing target compiles, and a sibling that some *other*
/// dependency pulls in has been. So `Checkout` can `import Persistence` with only `Domain` declared,
/// provided `Domain` depends on `Persistence` — and it keeps compiling until that edge is removed,
/// at which point a target nobody touched stops building. With parallel builds it can also fail
/// intermittently, when the scheduler happens to compile the importer first.
///
/// **Only targets declared in the same manifest are checked.** A `.product(name:package:)` names a
/// product whose modules are listed in another package's manifest, so an import that matches no
/// local target is outside this rule rather than a finding.
///
/// Not reported:
/// - An import satisfied by an `@_exported import` in a declared dependency, followed transitively.
///   The module is then part of the declared dependency's interface, which is the author's intent.
/// - An import inside `#if canImport(Module)`, which is written to compile without the module.
/// - Plugin targets, which cannot import the package's targets at all.
/// - Targets whose dependency list is not a literal the manifest reader can enumerate.
///
/// Each undeclared module is reported once per target, at its first import in path order, since the
/// fix is one line in `Package.swift` however many files import it.
final class UndeclaredTargetDependencyVisitor: CrossFileVisitorBase, CrossFilePatternVisitorProtocol {

    func finalizeAnalysis() {
        for package in PackageTargetSources(fileCache: fileCache).packages {
            analyze(PackageTargetImports(package: package, fileCache: fileCache))
        }
    }

    private func analyze(_ imports: PackageTargetImports) {
        for target in imports.package.manifest.targets where target.kind != .plugin {
            guard let declared = imports.declaredLocalModules(of: target) else { continue }
            let reachable = imports.withReexports(of: declared)

            let undeclared = (imports.sitesByTarget[target.name] ?? []).filter { site in
                site.module != target.moduleName
                    && imports.targetsByModule[site.module] != nil
                    && reachable.contains(site.module) == false
                    && site.isGuardedByCanImport == false
            }
            report(undeclared, in: target)
        }
    }

    private func report(_ sites: [PackageTargetImports.Site], in target: PackageManifest.Target) {
        let sitesByModule = Dictionary(grouping: sites, by: \.module)
        for module in sitesByModule.keys.sorted() {
            guard let moduleSites = sitesByModule[module], let first = moduleSites.first else { continue }
            let otherFiles = Set(moduleSites.map(\.file)).count - 1
            let spread = otherFiles == 0 ? ""
                : " (and \(otherFiles) other file\(otherFiles == 1 ? "" : "s"))"

            addIssue(
                severity: .warning,
                message: "Target '\(target.name)' imports '\(module)'\(spread) "
                    + "without declaring it as a dependency",
                filePath: first.file,
                lineNumber: getLineNumber(for: Syntax(first.node)),
                suggestion: "Add \"\(module)\" to the dependencies of '\(target.name)' in Package.swift. "
                    + "It builds today only because another dependency happens to build it first.",
                ruleName: .undeclaredTargetDependency
            )
        }
    }
}
