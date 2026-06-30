import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// Flags impure / side-effecting references inside a SwiftUI view's `body`.
///
/// A `body` should be a pure function of state — it builds a view tree and does
/// nothing else. Reaching into persistence, the file system, the network,
/// logging, or the dispatch queue from `body` couples *rendering* to side
/// effects and external mutable state: the view renders differently depending on
/// outside-the-view state (so it can't be snapshot- or property-tested by simply
/// rendering it), and SwiftUI may re-invoke `body` many times, re-firing the
/// effect. Move the work to an action / `onAppear` (for effects) or `@AppStorage`
/// / injected state (for reads), and drive the view from state.
///
/// **Detection:** mirrors `FormatterInViewBodyVisitor` — scans the getter of the
/// `body` computed property on any `struct` conforming to `View`, reporting any
/// reference to a known impure API. Value-source nondeterminism (`Date()`,
/// `.random`) is deliberately *not* flagged here — `NonInjectedNondeterminism`
/// already covers it in any computed-property body, so this rule stays focused
/// on side-effecting / external-state calls and avoids double-reporting.
final class ImpureCallInViewBodyVisitor: BasePatternVisitor {

    /// Persistence / IO / logging / scheduling APIs whose use in `body` makes
    /// rendering impure. Matched as the bare reference name (`UserDefaults` in
    /// `UserDefaults.standard.set(...)`, `print` in `print(...)`).
    private static let impureMarkers: Set<String> = [
        "UserDefaults",
        "FileManager",
        "URLSession",
        "NotificationCenter",
        "DispatchQueue",
        "print",
        "NSLog"
    ]

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        guard isSwiftUIView(node) else { return .visitChildren }
        scanBodyProperty(in: node.memberBlock)
        return .visitChildren
    }

    private func scanBodyProperty(in memberBlock: MemberBlockSyntax) {
        for member in memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            for binding in varDecl.bindings {
                guard let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
                      pattern.identifier.text == "body",
                      let accessorBlock = binding.accessorBlock else { continue }
                scanAccessorBlock(accessorBlock)
            }
        }
    }

    private func scanAccessorBlock(_ accessorBlock: AccessorBlockSyntax) {
        switch accessorBlock.accessors {
        case .getter(let items):
            reportImpureCalls(in: Syntax(items))

        case .accessors(let list):
            for accessor in list where accessor.accessorSpecifier.text == "get" {
                if let body = accessor.body {
                    reportImpureCalls(in: Syntax(body.statements))
                }
            }
        }
    }

    private func reportImpureCalls(in subtree: Syntax) {
        let finder = ImpureReferenceFinder(markers: Self.impureMarkers)
        finder.walk(subtree)
        for (marker, node) in finder.findings {
            addIssue(
                severity: .warning,
                message: "Impure call in view body — `body` should be a pure function of state, but "
                    + "`\(marker)` couples rendering to side effects / external mutable state, so the "
                    + "view renders nondeterministically and can't be tested by rendering it",
                filePath: getFilePath(for: node),
                lineNumber: getLineNumber(for: node),
                suggestion: "Move it out of `body` — an action / `onAppear` for effects, or "
                    + "`@AppStorage` / injected state for reads — and drive the view from state.",
                ruleName: .impureCallInViewBody
            )
        }
    }

    /// Walks a subtree collecting references whose name is a known impure marker.
    /// `UserDefaults.standard` and `print(...)` both surface their marker as a
    /// `DeclReferenceExprSyntax` (the member-access base / the call callee).
    private final class ImpureReferenceFinder: SyntaxVisitor {
        let markers: Set<String>
        var findings: [(marker: String, node: Syntax)] = []

        init(markers: Set<String>) {
            self.markers = markers
            super.init(viewMode: .sourceAccurate)
        }

        override func visit(_ node: DeclReferenceExprSyntax) -> SyntaxVisitorContinueKind {
            let name = node.baseName.text
            if markers.contains(name) {
                findings.append((marker: name, node: Syntax(node)))
            }
            return .visitChildren
        }
    }
}
