import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A SwiftSyntax visitor that detects Foundation formatter, coder, and locale
/// types created inside a SwiftUI view's `body` computed property.
///
/// Types such as `DateFormatter`, `NumberFormatter`, and `JSONDecoder` are
/// expensive to create — they allocate internal caches and parse locale data
/// on initialization. When constructed inside `body`, they are rebuilt on
/// every view re-render, turning per-update allocation overhead into a
/// sustained performance cost.
///
/// `Calendar.current` and `Locale.current` are lighter, but each access
/// returns a struct copy. Inside a `ForEach` or a frequently re-rendered body
/// these copies accumulate; using `@Environment(\.calendar)` or
/// `@Environment(\.locale)` is both cheaper and respects Dynamic Type /
/// locale-change notifications correctly.
///
/// **Detection:** Scans the getter of the `body` computed property on any
/// `struct` conforming to `View`, looking for:
/// - Call expressions whose callee is a known expensive formatter type.
/// - Member accesses of the form `Calendar.current` or `Locale.current`.
/// Only `struct`-based Views are checked (all SwiftUI Views must be structs).
///
/// **No suppression needed:** Foundation formatters cannot be declared as
/// `static` stored properties inside a function body or computed property
/// getter — they are structurally guaranteed to be per-render allocations
/// whenever they appear inside `body`.
final class FormatterInViewBodyVisitor: BasePatternVisitor {

    private static let expensiveFormatterTypes: Set<String> = [
        "DateFormatter",
        "NumberFormatter",
        "ISO8601DateFormatter",
        "DateComponentsFormatter",
        "ByteCountFormatter",
        "MeasurementFormatter",
        "PersonNameComponentsFormatter",
        "JSONDecoder",
        "JSONEncoder"
    ]

    required init(pattern: SyntaxPattern, viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        super.init(pattern: pattern, viewMode: viewMode)
    }

    // MARK: - Visitor Entry Point

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        guard isSwiftUIView(node) else { return .visitChildren }
        scanBodyProperty(in: node.memberBlock)
        return .visitChildren
    }

    // MARK: - Body Property Detection

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
            reportFormatterCalls(in: Syntax(items))
        case .accessors(let list):
            for accessor in list where accessor.accessorSpecifier.text == "get" {
                if let body = accessor.body {
                    reportFormatterCalls(in: Syntax(body.statements))
                }
            }
        }
    }

    // MARK: - Formatter Call Detection

    private func reportFormatterCalls(in subtree: Syntax) {
        let finder = FormatterCallFinder(formatterTypes: Self.expensiveFormatterTypes)
        finder.walk(subtree)

        for (typeName, callNode) in finder.findings {
            addIssue(node: callNode, variables: ["formatterType": typeName])
        }
    }

    // MARK: - Nested Call Finder

    /// Walks a syntax subtree collecting calls to known expensive formatter types
    /// and accesses to `Calendar.current` / `Locale.current`.
    private final class FormatterCallFinder: SyntaxVisitor {
        let formatterTypes: Set<String>
        var findings: [(typeName: String, node: Syntax)] = []

        /// Static property accesses that are flagged: type name → property name.
        private static let expensivePropertyAccesses: [String: String] = [
            "Calendar": "current",
            "Locale": "current"
        ]

        init(formatterTypes: Set<String>) {
            self.formatterTypes = formatterTypes
            super.init(viewMode: .sourceAccurate)
        }

        override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
            if let typeName = calledTypeName(from: node.calledExpression),
               formatterTypes.contains(typeName) {
                findings.append((typeName: typeName, node: Syntax(node)))
            }
            return .visitChildren
        }

        override func visit(_ node: MemberAccessExprSyntax) -> SyntaxVisitorContinueKind {
            if let base = node.base?.as(DeclReferenceExprSyntax.self) {
                let typeName = base.baseName.text
                let memberName = node.declName.baseName.text
                if Self.expensivePropertyAccesses[typeName] == memberName {
                    findings.append((typeName: "\(typeName).\(memberName)", node: Syntax(node)))
                }
            }
            return .visitChildren
        }

        /// Extracts the base type name from a call expression.
        /// Handles plain calls (`DateFormatter()`) only — formatter types
        /// don't have meaningful generic specializations in practice.
        private func calledTypeName(from expr: ExprSyntax) -> String? {
            guard let declRef = expr.as(DeclReferenceExprSyntax.self) else { return nil }
            return declRef.baseName.text
        }
    }
}
