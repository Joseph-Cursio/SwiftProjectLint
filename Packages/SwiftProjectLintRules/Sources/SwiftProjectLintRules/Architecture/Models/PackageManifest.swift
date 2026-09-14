import SwiftSyntax

/// The targets a `Package.swift` declares, read from its syntax tree rather than by running it.
///
/// A manifest is a Swift program, and SwiftPM learns its targets by executing it. A linter cannot,
/// so this reads only what the source states literally: a target's name, its `path:`, its
/// `sources:` and `exclude:` lists, and its dependency list. That covers the manifests people
/// actually write, where `targets:` is an array of `.target(name: "…", dependencies: […])` calls.
///
/// **What cannot be read is refused, not guessed.** A target whose name or paths are computed makes
/// the whole manifest unreadable (`init` returns `nil`), because the rules built on this map source
/// files to targets by path — one unseen target can own files that would otherwise be attributed to
/// a neighbour whose `path:` encloses them, and every finding about those files would be wrong. A
/// target whose *dependency list* alone is computed stays readable with `dependencies == nil`: its
/// files still belong to it, but no claim about what it declares can be made.
struct PackageManifest {

    /// The `Target` factory a declaration was written with.
    enum TargetKind: String {
        case regular = "target"
        case executable = "executableTarget"
        case test = "testTarget"
        case macro
        case plugin
        case systemLibrary
        case binaryTarget

        /// The directories SwiftPM searches for `<name>/` when a target gives no `path:`, in its
        /// own order of preference.
        var predefinedDirectories: [String] {
            switch self {
            case .test: ["Tests", "Sources", "Source", "src", "srcs"]
            case .plugin: ["Plugins"]
            default: ["Sources", "Source", "src", "srcs"]
            }
        }
    }

    /// One entry of a target's `dependencies:` array.
    struct Dependency {
        let name: String
        /// `.product(name:package:)` names a product of another package. Which modules that product
        /// vends is written in the other package's manifest, so it never matches a local target.
        let isPackageProduct: Bool
        /// The literal `package:` of a `.product(name:package:)`; `nil` for any other entry.
        let package: String?
        let node: Syntax
    }

    struct Target {
        let name: String
        let kind: TargetKind
        /// The literal `path:`, relative to the package directory; `nil` for SwiftPM's default.
        let path: String?
        /// The literal `sources:` list, relative to the target's directory; `nil` when absent.
        let sources: [String]?
        /// The literal `exclude:` list, relative to the target's directory.
        let exclude: [String]
        /// `nil` when the list is not a literal array of recognisable entries.
        let dependencies: [Dependency]?
        let node: Syntax

        /// The name `import` uses. SwiftPM turns a target name into a C99 identifier, so
        /// `my-lib` is imported as `my_lib`.
        var moduleName: String {
            PackageManifest.c99Identifier(name)
        }
    }

    /// A `.library` product: the only product kind another package's targets can import.
    struct LibraryProduct {
        let name: String
        let targets: [String]
    }

    /// A `.package(path:)` dependency — the one kind whose manifest can sit inside the analysed tree.
    struct PathDependency {
        /// The literal `path:`, relative to this manifest's directory.
        let path: String
        /// The literal `name:` of the older `.package(name:path:)` spelling.
        let name: String?

        /// SwiftPM's identity for a path dependency: the last path component, lowercased. It is
        /// what `.product(name:package:)` names.
        var identity: String {
            (path.split(separator: "/").last.map(String.init) ?? path).lowercased()
        }
    }

    /// The root-relative directory holding the manifest, with a trailing `/`, or `""` at the root.
    let directory: String
    let targets: [Target]
    /// The literal `name:` given to `Package(...)`.
    let packageName: String?
    /// `nil` when any `.library` declaration is not literal, since a product that cannot be read
    /// could vend any of the package's modules.
    let libraryProducts: [LibraryProduct]?
    /// The `.package(path:)` dependencies with a literal path. One with a computed path is left out,
    /// and so is everything reached only through it.
    let pathDependencies: [PathDependency]

    /// Reads the targets declared in `source`, or returns `nil` when any declaration is not literal.
    init?(source: SourceFileSyntax, directory: String) {
        let collector = TargetDeclarationCollector(viewMode: .sourceAccurate)
        collector.walk(source)
        guard collector.isReadable else { return nil }
        self.directory = directory
        self.targets = collector.targets

        let packageCollector = PackageDeclarationCollector(viewMode: .sourceAccurate)
        packageCollector.walk(source)
        packageName = packageCollector.packageName
        libraryProducts = packageCollector.productsAreReadable ? packageCollector.libraryProducts : nil
        pathDependencies = packageCollector.pathDependencies
    }

    /// Whether `relativePath` names a manifest file — `Package.swift`, or a version-specific
    /// `Package@swift-6.0.swift`.
    static func isManifestFile(_ relativePath: String) -> Bool {
        let fileName = relativePath.split(separator: "/").last.map(String.init) ?? relativePath
        return fileName == "Package.swift"
            || (fileName.hasPrefix("Package@swift-") && fileName.hasSuffix(".swift"))
    }

    static func c99Identifier(_ name: String) -> String {
        var identifier = String(name.map { character -> Character in
            character.isLetter || character.isNumber || character == "_" ? character : "_"
        })
        if let first = identifier.first, first.isNumber {
            identifier = "_" + identifier
        }
        return identifier
    }
}

// MARK: - Reading the syntax

/// Finds the `Target` factory calls in a manifest and reads each one's literal arguments.
private final class TargetDeclarationCollector: SyntaxVisitor {

    private(set) var targets: [PackageManifest.Target] = []
    private(set) var isReadable = true

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard let member = node.calledExpression.as(MemberAccessExprSyntax.self),
              let kind = PackageManifest.TargetKind(rawValue: member.declName.baseName.text),
              isTargetFactoryBase(member.base) else {
            return .visitChildren
        }

        switch role(of: node, kind: kind) {
        case .dependency:
            return .skipChildren

        case .unknown:
            isReadable = false
            return .skipChildren

        case .target:
            if let target = readTarget(node, kind: kind) {
                targets.append(target)
            } else {
                isReadable = false
            }
            return .skipChildren
        }
    }

    // MARK: Telling a target from a dependency

    private enum Role {
        case target
        case dependency
        case unknown
    }

    /// `.target(name:)` is spelled the same as a `Target` and as a `Target.Dependency`, so the
    /// spelling alone does not say which one a call builds. Every other factory in `TargetKind`
    /// exists only on `Target`.
    private func role(of call: FunctionCallExprSyntax, kind: PackageManifest.TargetKind) -> Role {
        guard kind == .regular else { return .target }

        // Only a Target takes anything beyond a name and a platform condition.
        let dependencyLabels: Set<String> = ["name", "condition"]
        if call.arguments.contains(where: { dependencyLabels.contains($0.label?.text ?? "") == false }) {
            return .target
        }

        var ancestor = call.parent
        while let current = ancestor {
            if let labeled = current.as(LabeledExprSyntax.self) {
                switch labeled.label?.text {
                case "dependencies": return .dependency
                case "targets": return .target
                default: break
                }
            }
            if let binding = current.as(PatternBindingSyntax.self),
               let annotation = binding.typeAnnotation?.type.trimmedDescription {
                return annotation.contains("Dependency") ? .dependency
                    : annotation.contains("Target") ? .target : .unknown
            }
            ancestor = current.parent
        }
        return .unknown
    }

    private func isTargetFactoryBase(_ base: ExprSyntax?) -> Bool {
        guard let base else { return true }
        return base.as(DeclReferenceExprSyntax.self)?.baseName.text == "Target"
    }

    // MARK: Literal arguments

    private func readTarget(
        _ call: FunctionCallExprSyntax,
        kind: PackageManifest.TargetKind
    ) -> PackageManifest.Target? {
        guard let nameExpression = ManifestLiterals.argument("name", of: call),
              let name = ManifestLiterals.string(nameExpression) else {
            return nil
        }

        var path: String?
        if let pathExpression = ManifestLiterals.argument("path", of: call) {
            guard let literal = ManifestLiterals.string(pathExpression) else { return nil }
            path = literal
        }

        var sources: [String]?
        if let sourcesExpression = ManifestLiterals.argument("sources", of: call) {
            guard let literal = ManifestLiterals.strings(sourcesExpression) else { return nil }
            sources = literal
        }

        var exclude: [String] = []
        if let excludeExpression = ManifestLiterals.argument("exclude", of: call) {
            guard let literal = ManifestLiterals.strings(excludeExpression) else { return nil }
            exclude = literal
        }

        // No `dependencies:` argument declares none; one that cannot be enumerated declares unknown.
        var dependencies: [PackageManifest.Dependency]? = []
        if let dependenciesExpression = ManifestLiterals.argument("dependencies", of: call) {
            dependencies = readDependencies(dependenciesExpression)
        }

        return PackageManifest.Target(
            name: name,
            kind: kind,
            path: path,
            sources: sources,
            exclude: exclude,
            dependencies: dependencies,
            node: Syntax(call)
        )
    }

    /// The entries of a literal dependency array, or `nil` if any entry is something else.
    private func readDependencies(_ expression: ExprSyntax) -> [PackageManifest.Dependency]? {
        guard let array = expression.as(ArrayExprSyntax.self) else { return nil }
        var dependencies: [PackageManifest.Dependency] = []
        for element in array.elements {
            guard let dependency = readDependency(element.expression) else { return nil }
            dependencies.append(dependency)
        }
        return dependencies
    }

    private func readDependency(_ expression: ExprSyntax) -> PackageManifest.Dependency? {
        if let name = ManifestLiterals.string(expression) {
            return PackageManifest.Dependency(
                name: name, isPackageProduct: false, package: nil, node: Syntax(expression)
            )
        }
        guard let call = expression.as(FunctionCallExprSyntax.self),
              let member = call.calledExpression.as(MemberAccessExprSyntax.self),
              let nameExpression = ManifestLiterals.argument("name", of: call),
              let name = ManifestLiterals.string(nameExpression) else {
            return nil
        }
        switch member.declName.baseName.text {
        case "target", "byName":
            return PackageManifest.Dependency(
                name: name, isPackageProduct: false, package: nil, node: Syntax(expression)
            )

        case "product":
            let package = ManifestLiterals.argument("package", of: call).flatMap(ManifestLiterals.string)
            return PackageManifest.Dependency(
                name: name, isPackageProduct: true, package: package, node: Syntax(expression)
            )

        default:
            return nil
        }
    }
}
