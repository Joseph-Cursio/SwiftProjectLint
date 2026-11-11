import Foundation
import LintStudioCore
import SwiftProjectLintModels

extension IssueSeverity: @retroactive LintSeverity {
    public var displayName: String { rawValue.capitalized }
    public var isError: Bool { self == .error }
    public var isInfo: Bool { self == .info }
}
