import Core
import Foundation
import LintStudioCore

extension IssueSeverity: @retroactive LintSeverity {
    public var displayName: String { rawValue.capitalized }
    public var isError: Bool { self == .error }
    public var isInfo: Bool { self == .info }
}
