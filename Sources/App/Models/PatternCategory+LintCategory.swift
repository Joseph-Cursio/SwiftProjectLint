import Core
import LintStudioCore

extension PatternCategory: @retroactive LintCategory {
    public var rawValue: String {
        switch self {
        case .stateManagement: "stateManagement"
        case .performance: "performance"
        case .architecture: "architecture"
        case .codeQuality: "codeQuality"
        case .security: "security"
        case .accessibility: "accessibility"
        case .memoryManagement: "memoryManagement"
        case .networking: "networking"
        case .uiPatterns: "uiPatterns"
        case .animation: "animation"
        case .modernization: "modernization"
        case .idempotency: "idempotency"
        case .testability: "testability"
        case .other: "other"
        }
    }

    public var displayName: String {
        switch self {
        case .stateManagement: "State Management"
        case .performance: "Performance"
        case .architecture: "Architecture"
        case .codeQuality: "Code Quality"
        case .security: "Security"
        case .accessibility: "Accessibility"
        case .memoryManagement: "Memory Management"
        case .networking: "Networking"
        case .uiPatterns: "UI Patterns"
        case .animation: "Animation"
        case .modernization: "Modernization"
        case .idempotency: "Idempotency"
        case .testability: "Testability"
        case .other: "Other"
        }
    }
}
