import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects raw file I/O performed inline inside a
/// testable orchestration type (a `Model`/`ViewModel`/`Service`) where the call
/// should instead route through an injected reader/writer seam.
///
/// This is the dual of `ConcreteTypeUsage`: that rule flags a *property or
/// parameter* typed as a concrete service class, whereas this one flags a raw
/// Foundation I/O *call* — `String(contentsOfFile:)`, `Data(contentsOf:)`,
/// `someText.write(to:)` — that has no type annotation to catch but is exactly
/// the kind of dependency that defeats unit-testing an otherwise-injectable
/// model. The fix is a small `protocol`-typed collaborator (a `…Reading` /
/// `…Writing` seam) supplied through the initializer.
///
/// Scope is deliberately narrow to stay high-precision: it fires only inside
/// types whose name marks them as orchestration layers (`…Model`, `…ViewModel`,
/// `…Service`). Types that *are* the I/O seam — `…Reader`, `…Writer`, `…Store`,
/// `…Actor`, a CLI's `…Linter`, etc. — never end in those suffixes, so raw I/O
/// there (its whole job) is left alone. Test and fixture files are exempt.
final class UnabstractedFileIOVisitor: BasePatternVisitor {

    /// Enclosing type-name stack so the *innermost* declaration decides scope.
    private var typeNameStack: [String] = []

    /// Name suffixes marking a testable orchestration type that should delegate
    /// I/O rather than perform it inline.
    private static let orchestrationSuffixes = ["Model", "ViewModel", "Service"]

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    // MARK: - Scope tracking

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        typeNameStack.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ _: StructDeclSyntax) {
        if !typeNameStack.isEmpty { typeNameStack.removeLast() }
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        typeNameStack.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ _: ClassDeclSyntax) {
        if !typeNameStack.isEmpty { typeNameStack.removeLast() }
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        typeNameStack.append(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ _: ActorDeclSyntax) {
        if !typeNameStack.isEmpty { typeNameStack.removeLast() }
    }

    /// Whether the innermost enclosing type is an orchestration layer we hold to
    /// the "delegate your I/O" standard.
    private var isInsideOrchestrationType: Bool {
        guard let typeName = typeNameStack.last else { return false }
        return Self.orchestrationSuffixes.contains { typeName.hasSuffix($0) }
    }

    // MARK: - Call detection

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        guard !isTestOrFixtureFile(), isInsideOrchestrationType else {
            return .visitChildren
        }
        if let call = rawFileIOCall(node) {
            addIssue(
                severity: .info,
                message: "Raw file I/O '\(call)' runs inline inside '\(typeNameStack.last ?? "")' "
                    + "— route it through an injected reader/writer seam for testability",
                filePath: getFilePath(for: Syntax(node)),
                lineNumber: getLineNumber(for: Syntax(node)),
                suggestion: "Define a protocol (e.g. 'SourceFileReading') for the file access, "
                    + "inject it through the initializer, and call it here instead of Foundation directly.",
                ruleName: .unabstractedFileIO
            )
        }
        return .visitChildren
    }

    /// Returns a short label for the raw-I/O call if `node` is one, else `nil`.
    private func rawFileIOCall(_ node: FunctionCallExprSyntax) -> String? {
        // Reads: String(contentsOfFile:)/String(contentsOf:), Data(contentsOfFile:)/Data(contentsOf:)
        if let declRef = node.calledExpression.as(DeclReferenceExprSyntax.self),
           declRef.baseName.text == "String" || declRef.baseName.text == "Data",
           let firstLabel = node.arguments.first?.label?.text,
           firstLabel == "contentsOf" || firstLabel == "contentsOfFile" {
            return "\(declRef.baseName.text)(\(firstLabel):)"
        }
        // Writes: <value>.write(to:) — Foundation's String/Data write, whose *first*
        // argument label is `to`. This deliberately excludes a static call to an
        // injected writer helper such as `SafeFileWriter.write(text, to:)`, whose
        // first argument is the unlabeled content — that call is already a seam.
        if let member = node.calledExpression.as(MemberAccessExprSyntax.self),
           member.declName.baseName.text == "write",
           node.arguments.first?.label?.text == "to" {
            return ".write(to:)"
        }
        return nil
    }
}
