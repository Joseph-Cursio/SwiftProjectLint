import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that surfaces uses of Swift's memory-unsafe escape hatches:
/// raw-pointer types, the `unsafeBitCast` / `unsafeDowncast` family, the `withUnsafe…`
/// buffer/pointer APIs, manual `bindMemory` / `assumingMemoryBound` rebinding, and
/// `Unmanaged` reference juggling.
///
/// These APIs opt out of the guarantees the rest of the language provides — bounds
/// checking, type safety, ARC — and a mistake is undefined behavior rather than a
/// compile error or a clean trap. They are legitimately needed for C interop and tight
/// performance work, so this is an **audit** rule (`info` severity): each use should be
/// localized, commented, and justified, not scattered.
///
/// Detection is syntactic, so it errs toward surfacing rather than proving misuse:
/// - **Pointer / opaque types** in any position: `UnsafePointer`, `UnsafeMutablePointer`,
///   `Unsafe[Mutable]RawPointer`, `Unsafe[Mutable][Raw]BufferPointer`, `OpaquePointer`,
///   `Unmanaged`.
/// - **Unsafe calls** by callee name (free function or method): `unsafeBitCast`,
///   `unsafeDowncast`, `withUnsafePointer`, `withUnsafeMutablePointer`, `withUnsafeBytes`,
///   `withUnsafeMutableBytes`, `withUnsafeTemporaryAllocation`, `assumingMemoryBound`,
///   `bindMemory`, `withMemoryRebound`.
/// - **`Unmanaged` factories**: `Unmanaged.passRetained(…)`, `Unmanaged.fromOpaque(…)`, etc.
final class UnsafeMemoryAPIVisitor: BasePatternVisitor {

    private static let unsafePointerTypes: Set<String> = [
        "UnsafePointer", "UnsafeMutablePointer",
        "UnsafeRawPointer", "UnsafeMutableRawPointer",
        "UnsafeBufferPointer", "UnsafeMutableBufferPointer",
        "UnsafeRawBufferPointer", "UnsafeMutableRawBufferPointer",
        "OpaquePointer", "Unmanaged"
    ]

    private static let unsafeCallNames: Set<String> = [
        "unsafeBitCast", "unsafeDowncast",
        "withUnsafePointer", "withUnsafeMutablePointer",
        "withUnsafeBytes", "withUnsafeMutableBytes",
        "withUnsafeTemporaryAllocation",
        "assumingMemoryBound", "bindMemory", "withMemoryRebound"
    ]

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: IdentifierTypeSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        if Self.unsafePointerTypes.contains(name) {
            report(
                "Unsafe memory type '\(name)' traffics in raw, unmanaged memory",
                node: Syntax(node)
            )
        }
        return .visitChildren
    }

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if let name = calleeName(node), Self.unsafeCallNames.contains(name) {
            report(
                "Unsafe memory API '\(name)' bypasses Swift's memory safety",
                node: Syntax(node)
            )
        } else if isUnmanagedFactory(node) {
            report(
                "'Unmanaged' bypasses ARC and requires manual retain/release balancing",
                node: Syntax(node)
            )
        }
        return .visitChildren
    }

    /// The callee's final name: the identifier for a free function (`unsafeBitCast(…)`)
    /// or the member for a method call (`pointer.assumingMemoryBound(…)`).
    private func calleeName(_ call: FunctionCallExprSyntax) -> String? {
        if let reference = call.calledExpression.as(DeclReferenceExprSyntax.self) {
            return reference.baseName.text
        }
        if let member = call.calledExpression.as(MemberAccessExprSyntax.self) {
            return member.declName.baseName.text
        }
        return nil
    }

    /// True for `Unmanaged.<factory>(…)` calls (base is the `Unmanaged` type itself).
    private func isUnmanagedFactory(_ call: FunctionCallExprSyntax) -> Bool {
        guard let member = call.calledExpression.as(MemberAccessExprSyntax.self),
              let base = member.base?.as(DeclReferenceExprSyntax.self) else { return false }
        return base.baseName.text == "Unmanaged"
    }

    private func report(_ message: String, node: Syntax) {
        addIssue(
            severity: .info,
            message: message,
            filePath: getFilePath(for: node),
            lineNumber: getLineNumber(for: node),
            suggestion: "Keep unsafe memory access localized, commented, and justified — "
                + "prefer safe abstractions (Array/Data/Span, withUnsafe… scoped to the "
                + "smallest region) and confine it to interop or measured hot paths.",
            ruleName: .unsafeMemoryAPI
        )
    }
}
