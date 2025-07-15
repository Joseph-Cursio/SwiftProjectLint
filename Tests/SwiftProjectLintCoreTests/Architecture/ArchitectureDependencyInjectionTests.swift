import Testing
import Foundation
@testable import SwiftProjectLintCore

@MainActor
final class ArchitectureDependencyInjectionTests {
    @Test func testDetectArchitecturalAntiPatternsWithMissingDependencyInjection() async throws {
        // ... existing code ...
    }
    @Test func testDetectArchitecturalAntiPatternsWithMultipleIssues_MissingDI() async throws {
        // ... relevant code from testDetectArchitecturalAntiPatternsWithMultipleIssues ...
    }
} 