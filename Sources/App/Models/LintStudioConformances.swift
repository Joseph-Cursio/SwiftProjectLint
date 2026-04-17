//
//  LintStudioConformances.swift
//  SwiftProjectLint
//
//  Bridge conformances connecting SwiftProjectLint model types
//  to LintStudioCore protocols for shared UI components
//

import SwiftUI
import LintStudioCore
import Core

// MARK: - IssueSeverity

extension IssueSeverity: @retroactive LintSeverity {
    public var displayName: String { rawValue.capitalized }
    public var isError: Bool { self == .error }
    public var isInfo: Bool { self == .info }
}

// MARK: - PatternCategory

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
        case .other: "Other"
        }
    }
}

// MARK: - PatternCategory Color Mapping

enum PatternCategoryColors {
    static func color(for category: PatternCategory) -> Color {
        switch category {
        case .stateManagement: .blue
        case .performance: .orange
        case .architecture: .purple
        case .codeQuality: .green
        case .security: .red
        case .accessibility: .teal
        case .memoryManagement: .pink
        case .networking: .cyan
        case .uiPatterns: .indigo
        case .animation: .mint
        case .modernization: .yellow
        case .idempotency: .brown
        case .other: .gray
        }
    }
}

// MARK: - LintIssue

extension LintIssue: @retroactive LintViolation {
    public var identifier: UUID { id }
    public var ruleIdentifier: String { ruleName.rawValue }
    public var line: Int { locations.first?.lineNumber ?? 0 }
    public var column: Int? { nil }
}
