// Handles tracking of @State variable declarations, usages, and assignments.
import SwiftSyntax
import Foundation

extension PerformanceVisitor {
    // MARK: - Unnecessary View Update Detection

    func trackStateVariableDeclaration(_ node: VariableDeclSyntax) {
        // Check if this is a @State variable
        let attributes = node.attributes
        for attribute in attributes {
            if let attributeName = attribute.as(AttributeSyntax.self)?.attributeName.as(IdentifierTypeSyntax.self)?.name.text,
               attributeName == "State" {

                // Extract variable name
                for binding in node.bindings {
                    if let pattern = binding.pattern.as(IdentifierPatternSyntax.self) {
                        let variableName = pattern.identifier.text
                        stateVariables[variableName] = PerformanceStateVariableInfo(
                            name: variableName,
                            declaredAtLine: getLineNumber(for: Syntax(node)),
                            isUsedInViewBody: false,
                            isAssigned: false,
                            assignmentLine: nil
                        )
                    }
                }
            }
        }
    }

    func trackStateVariableUsage(_ node: MemberAccessExprSyntax) {
        // Check if this is a state variable being used in the view body
        if node.base?.description.trimmingCharacters(in: .whitespacesAndNewlines) == "self" {
            // This is a self.variableName usage
            let variableName = node.declName.baseName.text
            if stateVariables[variableName] != nil {
                stateVariables[variableName]?.isUsedInViewBody = true
            }
        }
    }

    func trackStateVariableAssignment(_ node: AssignmentExprSyntax) {
        guard let parent = node.parent else { return }
        if let sequence = parent.as(SequenceExprSyntax.self) {
            let elements = sequence.elements
            if let assignIndex = elements.firstIndex(where: { $0.as(AssignmentExprSyntax.self)?.positionAfterSkippingLeadingTrivia == node.positionAfterSkippingLeadingTrivia }) {
                let assignIndexInt = elements.distance(from: elements.startIndex, to: assignIndex)
                if assignIndexInt > 0 {
                    let leftExpr = elements[elements.index(elements.startIndex, offsetBy: assignIndexInt - 1)]
                    if let memberAccess = leftExpr.as(MemberAccessExprSyntax.self) {
                        if memberAccess.base?.description.trimmingCharacters(in: .whitespacesAndNewlines) == "self" {
                            let variableName = memberAccess.declName.baseName.text
                            if stateVariables[variableName] != nil {
                                stateVariables[variableName]?.isAssigned = true
                                stateVariables[variableName]?.assignmentLine = getLineNumber(for: Syntax(node))
                            }
                        }
                    }
                }
            }
        }
    }

    func checkForUnnecessaryUpdates() {
        for (variableName, info) in stateVariables {
            if info.isAssigned && !info.isUsedInViewBody {
                addIssue(
                    severity: .warning,
                    message: "State variable '\(variableName)' is being updated unnecessarily",
                    filePath: currentFilePath,
                    lineNumber: info.assignmentLine ?? info.declaredAtLine,
                    suggestion: "Avoid updating state variables that don't affect the UI",
                    ruleName: nil
                )
            }
        }
    }
}
