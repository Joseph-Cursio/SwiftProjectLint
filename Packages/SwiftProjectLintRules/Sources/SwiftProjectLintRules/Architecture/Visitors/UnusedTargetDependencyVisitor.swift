import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// Cross-file visitor that reports a declared sibling-target dependency that nothing in the target
/// imports.
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
/// - `.product(name:package:)` entries, whose modules are listed in another manifest.
final class UnusedTargetDependencyVisitor: CrossFileVisitorBase, CrossFilePatternVisitorProtocol {

    func finalizeAnalysis() {
        for package in PackageTargetSources(fileCache: fileCache).packages {
            analyze(PackageTargetImports(package: package, fileCache: fileCache))
        }
    }

    private func analyze(_ imports: PackageTargetImports) {
        let package = imports.package
        let manifestPath = package.manifest.directory + "Package.swift"

        for target in package.manifest.targets where target.kind != .plugin {
            guard let dependencies = target.dependencies,
                  let files = package.filesByTarget[target.name], files.isEmpty == false else {
                continue
            }

            let imported = Set((imports.sitesByTarget[target.name] ?? []).map(\.module))
            let used = imports.withReexports(of: imported).union(externalMacroModules(in: files))

            for dependency in dependencies where dependency.isPackageProduct == false {
                guard let dependencyTarget = imports.targetsByName[dependency.name],
                      isJudgeable(dependencyTarget, in: package),
                      used.contains(dependencyTarget.moduleName) == false else {
                    continue
                }

                addIssue(
                    severity: .info,
                    message: "Target '\(target.name)' declares a dependency on "
                        + "'\(dependencyTarget.name)' but never imports it",
                    filePath: manifestPath,
                    lineNumber: getLineNumber(for: dependency.node),
                    suggestion: "Remove \"\(dependencyTarget.name)\" from the dependencies of "
                        + "'\(target.name)', or import it where it is used. An unused dependency still "
                        + "rebuilds '\(target.name)' whenever it changes.",
                    ruleName: .unusedTargetDependency
                )
            }
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
