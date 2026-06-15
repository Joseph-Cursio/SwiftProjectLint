import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import SwiftSyntax

/// A cross-file visitor that detects a concrete production class which is
/// subclassed by a test double (a `Mock`/`Stub`/`Fake`/`Spy`, or any class in a
/// test target) purely to substitute it.
///
/// Subclassing a production class to fake it is the anti-pattern that protocols
/// exist to eliminate: the test double must invoke the real `super.init` (and
/// any side effects it carries), and a new method on the production class
/// silently escapes the override. When the only reason a class is subclassed is
/// to mock it, and the class exposes no protocol abstraction, extracting a
/// protocol lets the test provide a lightweight conformer instead.
///
/// **Phase 1 (walk):** Collects every class and protocol declaration, each
/// class's inheritance clause, and — captured while the correct per-file
/// source-location converter is active — the declaration's line number.
/// **Phase 2 (finalizeAnalysis):** For each test-double subclass, flags its
/// production superclass when that superclass has no protocol abstraction.
final class SubclassedForMockingVisitor: CrossFileVisitorBase, CrossFilePatternVisitorProtocol {

    private struct ClassRecord {
        let name: String
        let file: String
        let line: Int
        let inheritedNames: [String]
        let isTestDoubleLocation: Bool
    }

    private var classes: [ClassRecord] = []
    private var classNames: Set<String> = []
    private var protocolNames: Set<String> = []

    // MARK: - Collect declarations

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        protocolNames.insert(node.name.text)
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        classNames.insert(name)
        classes.append(
            ClassRecord(
                name: name,
                file: currentFilePath,
                line: getLineNumber(for: Syntax(node)),
                inheritedNames: inheritedNames(from: node.inheritanceClause),
                isTestDoubleLocation: isTestOrFixtureFile()
            )
        )
        return .visitChildren
    }

    private func inheritedNames(from clause: InheritanceClauseSyntax?) -> [String] {
        guard let clause else { return [] }
        return clause.inheritedTypes.compactMap {
            $0.type.as(IdentifierTypeSyntax.self)?.name.text
        }
    }

    // MARK: - Finalize

    func finalizeAnalysis() {
        let classByName = Dictionary(classes.map { ($0.name, $0) }) { first, _ in first }

        // Base class name → an example test double subclassing it.
        var flagged: [String: String] = [:]

        for record in classes where isTestDouble(record) {
            for inherited in record.inheritedNames where inherited != record.name {
                guard let base = classByName[inherited] else { continue }
                guard isFlaggableBase(base) else { continue }
                if flagged[base.name] == nil {
                    flagged[base.name] = record.name
                }
            }
        }

        for (baseName, mockName) in flagged {
            guard let base = classByName[baseName] else { continue }
            addIssue(
                severity: .info,
                message: "'\(baseName)' is subclassed by '\(mockName)' to substitute it in tests — "
                    + "consider extracting a protocol instead of subclassing the production type.",
                filePath: base.file,
                lineNumber: base.line,
                suggestion: "Extract a protocol describing the surface '\(mockName)' overrides, conform "
                    + "'\(baseName)' to it, and inject the protocol so tests can supply a lightweight "
                    + "conformer rather than subclassing '\(baseName)' and calling its real initializer.",
                ruleName: .subclassedForMocking
            )
        }
    }

    /// A class is a test double if its name carries a mock marker (matched at a
    /// camelCase boundary, so `MockFoo`/`FooMock` qualify but `MockingbirdRunner`
    /// does not) or it is declared in a test/fixture file.
    private func isTestDouble(_ record: ClassRecord) -> Bool {
        record.isTestDoubleLocation || ProtocolExemption.isTestDoubleName(record.name)
    }

    /// A base class is flaggable only when it is a production type with no
    /// existing protocol abstraction — extracting one is then the real fix.
    private func isFlaggableBase(_ base: ClassRecord) -> Bool {
        if isTestDouble(base) { return false }
        // Already conforms to a protocol — the test should mock through it, not subclass.
        if base.inheritedNames.contains(where: { protocolNames.contains($0) }) { return false }
        // Conventional mirror protocol already exists for this type.
        if protocolNames.contains("\(base.name)Protocol") { return false }
        return true
    }
}
