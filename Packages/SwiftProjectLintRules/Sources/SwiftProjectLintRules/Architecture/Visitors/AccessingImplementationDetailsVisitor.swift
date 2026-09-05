import Foundation
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects two heuristics for encapsulation violations:
/// 1. Accessing underscore-prefixed members on non-self/super objects.
/// 2. Accessing members via a force-cast base to a service-like concrete type.
class AccessingImplementationDetailsVisitor: BasePatternVisitor {
    private var currentFilePath: String = ""

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func setFilePath(_ filePath: String) {
        super.setFilePath(filePath)
        self.currentFilePath = filePath
    }

    // MARK: - Same-type declaration

    /// Whether the type enclosing `node` declares `name` as one of its own members.
    ///
    /// Scope is the enclosing type, deliberately, and not the file. A first attempt used the
    /// file and was wrong in a way the existing suite caught immediately: two classes in one
    /// file, one reaching into the other's `_data`, is exactly the violation this rule is for.
    /// Swift's `private` being file-scoped makes that access *legal*, which is not the same as
    /// it being encapsulated.
    private func enclosingTypeDeclares(_ name: String, from node: some SyntaxProtocol) -> Bool {
        var current = node.parent
        while let candidate = current {
            if let members = Self.memberBlock(of: candidate) {
                return Self.declaredNames(in: members).contains(name)
            }
            current = candidate.parent
        }
        return false
    }

    private static func memberBlock(of node: Syntax) -> MemberBlockSyntax? {
        if let decl = node.as(StructDeclSyntax.self) { return decl.memberBlock }
        if let decl = node.as(ClassDeclSyntax.self) { return decl.memberBlock }
        if let decl = node.as(ActorDeclSyntax.self) { return decl.memberBlock }
        if let decl = node.as(EnumDeclSyntax.self) { return decl.memberBlock }
        if let decl = node.as(ExtensionDeclSyntax.self) { return decl.memberBlock }
        return nil
    }

    /// The member names a type declares directly — properties and functions.
    private static func declaredNames(in members: MemberBlockSyntax) -> Set<String> {
        var names: Set<String> = []
        for member in members.members {
            if let function = member.decl.as(FunctionDeclSyntax.self) {
                names.insert(function.name.text)
            }
            if let variable = member.decl.as(VariableDeclSyntax.self) {
                for binding in variable.bindings {
                    if let identifier = binding.pattern.as(IdentifierPatternSyntax.self) {
                        names.insert(identifier.identifier.text)
                    }
                }
            }
        }
        return names
    }

    // MARK: - MemberAccessExprSyntax

    override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
        guard let base = node.base else { return .visitChildren }

        let memberName = node.declName.baseName.text

        // Heuristic A: underscore-prefix member on a non-self/super base
        if memberName.hasPrefix("_") {
            // Skip test files — test code commonly accesses internals
            if isTestOrFixtureFile() {
                return .visitChildren
            }
            // Skip self._member and Self._member — accessing own type's internals is fine
            if let ref = base.as(DeclReferenceExprSyntax.self),
               ref.baseName.text == "self" || ref.baseName.text == "Self" {
                return .visitChildren
            }
            // Skip super._member
            if base.is(SuperExprSyntax.self) {
                return .visitChildren
            }
            // Skip `_base._member` — the base is underscored too, so both sides are in the
            // implementation domain. The rule is about a caller reaching past a type's
            // public interface; a type reaching through its own SPI is the convention
            // working as intended, and library code does it routinely.
            if let baseReference = base.as(DeclReferenceExprSyntax.self),
               baseReference.baseName.text.hasPrefix("_") {
                return .visitChildren
            }
            // Skip a member the project publishes under `@_spi(...)`. That attribute is
            // Swift's own way of saying "public symbol, deliberately not public API", and the
            // underscore is the naming convention that accompanies it rather than an accident.
            // Reporting it tells the author something they already said, in the language's own
            // vocabulary. Requires the project-wide SPI prescan.
            if knownSPIMembers.contains(memberName) {
                return .visitChildren
            }
            // Skip a member the *enclosing type itself* declares. The shape is
            // `other._value` inside that type's own initializer, which is how an
            // `Equatable`-style comparison against another instance is written — a type
            // reaching into its own kind, not a caller reaching past an interface.
            if enclosingTypeDeclares(memberName, from: node) {
                return .visitChildren
            }
            let baseDesc = base.as(DeclReferenceExprSyntax.self)?.baseName.text ?? "object"
            addIssue(
                severity: .warning,
                message: "Accessing implementation detail '\(memberName)' on '\(baseDesc)' " +
                    "— prefer the public interface",
                filePath: currentFilePath,
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Expose '\(memberName)' through a protocol or public API",
                ruleName: .accessingImplementationDetails
            )
            return .visitChildren
        }

        // Heuristic B: force-cast base to service-like concrete type
        if let castTypeName = extractForceCastTypeName(from: base) {
            addIssue(
                severity: .warning,
                message: "Accessing '\(memberName)' via force-cast to concrete type '\(castTypeName)' " +
                    "— prefer the protocol interface",
                filePath: currentFilePath,
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Avoid force-casting '\(castTypeName)'; add '\(memberName)' to the protocol instead",
                ruleName: .accessingImplementationDetails
            )
        }
        return .visitChildren
    }

    // MARK: - Helpers

    /// Searches the base expression's text for an `as!` cast to a service-like type.
    /// Uses textual inspection because sub-walking non-root nodes crashes in SwiftSyntax 601.
    private func extractForceCastTypeName(from expr: ExprSyntax) -> String? {
        let text = expr.trimmedDescription
        // Find "as! TypeName" — extract the identifier that follows
        guard let castRange = text.range(of: "as! ") else { return nil }
        let afterCast = text[castRange.upperBound...]
        let typeName = String(afterCast.prefix { $0.isLetter || $0.isNumber || $0 == "_" })
        return qualifyingServiceName(typeName)
    }

    /// Returns the name if it starts uppercase and ends with a service-like suffix, else nil.
    private func qualifyingServiceName(_ name: String) -> String? {
        guard name.first?.isUppercase == true,
              ServiceTypeSuffix.matches(name)
        else { return nil }
        return name
    }
}
