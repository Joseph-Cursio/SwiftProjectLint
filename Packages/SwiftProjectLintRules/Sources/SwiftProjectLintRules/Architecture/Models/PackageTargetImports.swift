import SwiftSyntax

/// The imports each target of one package makes.
///
/// Both halves of the manifest-versus-source comparison need the same facts about which modules a
/// target imports, so they are collected once here rather than twice in the two rules that ask.
/// Re-exports are followed by ``PackageGraph``, since `@_exported import` crosses packages.
struct PackageTargetImports {

    struct Site {
        let file: String
        let node: ImportDeclSyntax
        let module: String

        var isExported: Bool {
            node.attributes.contains { element in
                element.as(AttributeSyntax.self)?.attributeName.trimmedDescription == "_exported"
            }
        }

        /// Whether the import sits under `#if canImport(Module)` for its own module, which is written
        /// to compile without the module.
        var isGuardedByCanImport: Bool {
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

    let package: PackageTargetSources.Package
    /// Every import of each target, in path order then source order.
    let sitesByTarget: [String: [Site]]
    let targetsByModule: [String: PackageManifest.Target]
    let targetsByName: [String: PackageManifest.Target]

    init(package: PackageTargetSources.Package, fileCache: [String: SourceFileSyntax]) {
        let targets = package.manifest.targets
        self.package = package
        targetsByModule = Dictionary(targets.map { ($0.moduleName, $0) }) { first, _ in first }
        targetsByName = Dictionary(targets.map { ($0.name, $0) }) { first, _ in first }

        var sitesByTarget: [String: [Site]] = [:]
        for target in targets {
            sitesByTarget[target.name] = Self.imports(
                in: package.filesByTarget[target.name] ?? [], fileCache: fileCache
            )
        }
        self.sitesByTarget = sitesByTarget
    }

    /// The module names of the same-package targets `target` declares; `nil` when its dependency
    /// list could not be read.
    func declaredLocalModules(of target: PackageManifest.Target) -> Set<String>? {
        guard let dependencies = target.dependencies else { return nil }
        return Set(
            dependencies
                .filter { $0.isPackageProduct == false }
                .compactMap { targetsByName[$0.name]?.moduleName }
        )
    }

    private static func imports(in files: [String], fileCache: [String: SourceFileSyntax]) -> [Site] {
        files.flatMap { file -> [Site] in
            guard let source = fileCache[file] else { return [] }
            let collector = ImportDeclarationCollector(viewMode: .sourceAccurate)
            collector.walk(source)
            return collector.imports.compactMap { node in
                node.path.first.map { Site(file: file, node: node, module: $0.name.text) }
            }
        }
    }
}

/// Collects import declarations at any depth, including inside `#if` blocks.
private final class ImportDeclarationCollector: SyntaxVisitor {
    private(set) var imports: [ImportDeclSyntax] = []

    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
        imports.append(node)
        return .skipChildren
    }
}
