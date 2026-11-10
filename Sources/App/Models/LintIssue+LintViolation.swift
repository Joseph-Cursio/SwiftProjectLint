import Foundation
import LintStudioCore
import SwiftProjectLintModels

extension LintIssue: @retroactive LintViolation {
    public var identifier: UUID { id }
    public var ruleIdentifier: String { ruleName.rawValue }
    public var line: Int { locations.first?.lineNumber ?? 0 }
    public var column: Int? { nil }
}
