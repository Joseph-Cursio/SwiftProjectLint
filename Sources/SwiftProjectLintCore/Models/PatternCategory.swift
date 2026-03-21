//
//  PatternCategory.swift
//  SwiftProjectLint
//
//  Created by joe cursio on 7/14/25.
//

/// Represents logical categories of code patterns that can be detected within Swift source files.
/// Each category groups related patterns corresponding to common concerns in SwiftUI development,
/// architecture, or best practices:
///
/// - `stateManagement`: Patterns related to property wrappers, state handling, and the management of stateful data within views.
/// - `performance`: Patterns that may negatively affect performance, such as inefficient collection usage or large view bodies.
/// - `architecture`: Patterns connected to software architecture, such as MVVM adherence, dependency injection, and modular design.
/// - `codeQuality`: Patterns affecting maintainability, readability, and clarity, including magic numbers, documentation, and code style.
/// - `security`: Patterns that pose potential security risks, such as hardcoded secrets or unsafe URL handling.
/// - `accessibility`: Patterns highlighting accessibility concerns, such as missing labels or hints for UI components.
/// - `memoryManagement`: Patterns indicating possible memory issues, such as retain cycles or inefficient state storage.
/// - `networking`: Patterns related to network operations, error handling, and asynchronous calls.
/// - `uiPatterns`: Patterns concerning user interface structure and design conventions, such as navigation usage, previews, or styling consistency.
/// - `other`: System-level patterns and errors that don't fit into other categories, such as file parsing errors.
public enum PatternCategory: CaseIterable, Sendable {
    case stateManagement
    case performance
    case architecture
    case codeQuality
    case security
    case accessibility
    case memoryManagement
    case networking
    case uiPatterns
    case animation
    case modernization
    case other
}
