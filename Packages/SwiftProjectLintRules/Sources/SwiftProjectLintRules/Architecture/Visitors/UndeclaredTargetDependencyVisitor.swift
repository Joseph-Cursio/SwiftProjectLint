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

    private struct ImportSite {
        let file: String
        let node: ImportDeclSyntax
        let module: String
    }

    func finalizeAnalysis() {
        for package in PackageTargetSources(fileCache: fileCache).packages {
            analyze(package)
        }
    }

    private func analyze(_ package: PackageTargetSources.Package) {
        let targets = package.manifest.targets
        let targetsByModule = Dictionary(targets.map { ($0.moduleName, $0) }) { first, _ in first }
        let moduleByTargetName = Dictionary(targets.map { ($0.name, $0.moduleName) }) { first, _ in first }

        var importsByTarget: [String: [ImportSite]] = [:]
        var reexportsByModule: [String: Set<String>] = [:]
        for target in targets {
            let sites = imports(in: package.filesByTarget[target.name] ?? [])
            importsByTarget[target.name] = sites
            reexportsByModule[target.moduleName] = Set(
                sites.filter { isExported($0.node) }.map(\.module)
            )
        }

        for target in targets where target.kind != .plugin {
            guard let dependencies = target.dependencies else { continue }

            let declared = Set(
                dependencies
                    .filter { $0.isPackageProduct == false }
                    .compactMap { moduleByTargetName[$0.name] }
            )
            let reachable = closure(of: declared, reexports: reexportsByModule)

            let undeclared = (importsByTarget[target.name] ?? []).filter { site in
                site.module != target.moduleName
                    && targetsByModule[site.module] != nil
                    && reachable.contains(site.module) == false
                    && isGuardedByCanImport(site.node, module: site.module) == false
            }
            report(undeclared, in: target)
        }
    }

    private func report(_ sites: [ImportSite], in target: PackageManifest.Target) {
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

    // MARK: - Imports

    /// Every import in `files`, in path order then source order.
    private func imports(in files: [String]) -> [ImportSite] {
        files.flatMap { file -> [ImportSite] in
            guard let source = fileCache[file] else { return [] }
            let collector = ImportCollector(viewMode: .sourceAccurate)
            collector.walk(source)
            return collector.imports.compactMap { node in
                node.path.first.map { ImportSite(file: file, node: node, module: $0.name.text) }
            }
        }
    }

    private func isExported(_ node: ImportDeclSyntax) -> Bool {
        node.attributes.contains { element in
            element.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "_exported"
        }
    }

    /// `declared` plus every module re-exported, transitively, by a module already in the set.
    private func closure(of declared: Set<String>, reexports: [String: Set<String>]) -> Set<String> {
        var reachable = declared
        var pending = Array(declared)
        while let module = pending.popLast() {
            for reexported in reexports[module] ?? [] where reachable.contains(reexported) == false {
                reachable.insert(reexported)
                pending.append(reexported)
            }
        }
        return reachable
    }

    private func isGuardedByCanImport(_ node: ImportDeclSyntax, module: String) -> Bool {
        // `canImport(Module)` or `canImport(Module, _version: …)`, but not `canImport(ModuleKit)`.
        let spellings = ["canImport(\(module))", "canImport(\(module),"]
        var ancestor = node.parent
        while let current = ancestor {
            if let clause = current.as(IfConfigClauseSyntax.self),
               let condition = clause.condition?.trimmedDescription.filter({ $0.isWhitespace == false }),
               spellings.contains(where: { condition.contains($0) }) {
                return true
            }
            ancestor = current.parent
        }
        return false
    }
}

/// Collects import declarations at any depth, including inside `#if` blocks.
private final class ImportCollector: SyntaxVisitor {
    private(set) var imports: [ImportDeclSyntax] = []

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        imports.append(node)
        return .skipChildren
    }
}
