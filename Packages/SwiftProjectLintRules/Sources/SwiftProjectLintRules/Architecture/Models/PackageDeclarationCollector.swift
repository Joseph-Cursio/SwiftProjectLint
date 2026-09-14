import SwiftSyntax

/// Reads what a manifest says about the package as a whole: its name, its library products, and
/// the `.package(path:)` dependencies through which other manifests in the run can be reached.
///
/// Kept apart from target reading because the two refuse differently. An unreadable *target* makes
/// the whole manifest unreadable, since it could own files a neighbour would otherwise claim. An
/// unreadable *product* only makes the product list unknown, and an unreadable dependency path only
/// leaves that one package unreached — neither can misattribute a file.
final class PackageDeclarationCollector: SyntaxVisitor {

    private(set) var packageName: String?
    private(set) var libraryProducts: [PackageManifest.LibraryProduct] = []
    private(set) var productsAreReadable = true
    private(set) var pathDependencies: [PackageManifest.PathDependency] = []

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if let reference = node.calledExpression.as(DeclReferenceExprSyntax.self),
           reference.baseName.text == "Package",
           let nameExpression = ManifestLiterals.argument("name", of: node) {
            packageName = ManifestLiterals.string(nameExpression)
            return .visitChildren
        }

        guard let member = node.calledExpression.as(MemberAccessExprSyntax.self) else {
            return .visitChildren
        }
        switch (member.declName.baseName.text, baseName(of: member)) {
        case ("library", nil), ("library", "Product"):
            readLibrary(node)
            return .skipChildren

        case ("package", nil), ("package", "Dependency"):
            readPackageDependency(node)
            return .skipChildren

        default:
            return .visitChildren
        }
    }

    private func readLibrary(_ call: FunctionCallExprSyntax) {
        guard let nameExpression = ManifestLiterals.argument("name", of: call),
              let name = ManifestLiterals.string(nameExpression),
              let targetsExpression = ManifestLiterals.argument("targets", of: call),
              let targets = ManifestLiterals.strings(targetsExpression) else {
            productsAreReadable = false
            return
        }
        libraryProducts.append(PackageManifest.LibraryProduct(name: name, targets: targets))
    }

    private func readPackageDependency(_ call: FunctionCallExprSyntax) {
        guard let pathExpression = ManifestLiterals.argument("path", of: call),
              let path = ManifestLiterals.string(pathExpression) else {
            return
        }
        let name = ManifestLiterals.argument("name", of: call).flatMap(ManifestLiterals.string)
        pathDependencies.append(PackageManifest.PathDependency(path: path, name: name))
    }

    /// The last component of an explicit base — `Product` in `Product.library`, `Dependency` in
    /// `Package.Dependency.package` — or `nil` for the implicit-member spelling.
    private func baseName(of member: MemberAccessExprSyntax) -> String? {
        guard let base = member.base else { return nil }
        if let reference = base.as(DeclReferenceExprSyntax.self) {
            return reference.baseName.text
        }
        return base.as(MemberAccessExprSyntax.self)?.declName.baseName.text
    }
}

/// Literal reads shared by the manifest collectors: an argument by label, a plain string literal,
/// and an array of them. Anything computed — interpolation, a variable, a concatenation — reads as
/// `nil`, which each caller turns into its own kind of refusal.
enum ManifestLiterals {

    static func argument(_ label: String, of call: FunctionCallExprSyntax) -> ExprSyntax? {
        call.arguments.first { $0.label?.text == label }?.expression
    }

    static func string(_ expression: ExprSyntax) -> String? {
        guard let literal = expression.as(StringLiteralExprSyntax.self),
              literal.segments.count == 1,
              let segment = literal.segments.first?.as(StringSegmentSyntax.self) else {
            return nil
        }
        return segment.content.text
    }

    static func strings(_ expression: ExprSyntax) -> [String]? {
        guard let array = expression.as(ArrayExprSyntax.self) else { return nil }
        var strings: [String] = []
        for element in array.elements {
            guard let string = string(element.expression) else { return nil }
            strings.append(string)
        }
        return strings
    }
}
