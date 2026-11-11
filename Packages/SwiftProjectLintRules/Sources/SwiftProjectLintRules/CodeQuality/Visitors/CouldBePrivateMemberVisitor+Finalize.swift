import SwiftProjectLintModels
import SwiftProjectLintVisitors

extension CouldBePrivateMemberVisitor {
    // MARK: - Finalize

    func finalizeAnalysis() {
        for decl in declarations {
            // Suppress members on types conforming to project-defined protocols —
            // the member may be a protocol requirement
            if let conformances = typeConformanceNames[decl.typeName],
               conformances.contains(where: { projectProtocolNames.contains($0) }) {
                continue
            }

            // Suppress members on types conforming to system framework protocols —
            // members are called by the framework, not by app code
            if let conformances = typeConformanceNames[decl.typeName],
               conformances.contains(where: { Self.systemFrameworkProtocols.contains($0) }) {
                continue
            }

            let usageFiles = identifierUsages[decl.memberName] ?? []
            let externalFiles = usageFiles.subtracting([decl.file])

            if externalFiles.isEmpty {
                addIssue(
                    severity: .info,
                    message: narrowingMessage(for: decl),
                    filePath: decl.file,
                    lineNumber: getLineNumber(for: decl.node),
                    suggestion: narrowingSuggestion(for: decl),
                    ruleName: .couldBePrivateMember
                )
            }
        }
    }
}
