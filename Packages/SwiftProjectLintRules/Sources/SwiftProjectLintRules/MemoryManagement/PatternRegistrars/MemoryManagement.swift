import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// Registers patterns related to memory management in SwiftUI.
/// This registrar handles patterns for retain cycles, large objects, and memory optimization.

class MemoryManagement: BasePatternRegistrar {
    override func registerPatterns() {
        let patterns = [
            SyntaxPattern(
                name: .potentialRetainCycle,
                visitor: MemoryManagementVisitor.self,
                severity: .warning,
                category: .memoryManagement,
                messageTemplate: "Potential retain cycle detected in {context}",
                suggestion: "Use weak references or proper memory management patterns",
                description: "Detects potential retain cycles in closures and property wrappers"
            ),
            SyntaxPattern(
                name: .largeObjectInState,
                visitor: MemoryManagementVisitor.self,
                severity: .warning,
                category: .memoryManagement,
                messageTemplate: "Large object stored in state: {objectType}",
                suggestion: "Consider using @StateObject or moving to a separate model",
                description: "Detects large objects that might be inefficiently stored in @State"
            ),
            SyntaxPattern(
                name: .unsafeMemoryAPI,
                visitor: UnsafeMemoryAPIVisitor.self,
                severity: .info,
                category: .memoryManagement,
                messageTemplate: "Unsafe memory API bypasses Swift's memory safety",
                suggestion: "Keep unsafe memory access localized, commented, and justified; "
                    + "prefer safe abstractions and confine it to interop or measured hot paths.",
                description: "Surfaces raw-pointer types, unsafeBitCast/unsafeDowncast, the "
                    + "withUnsafe… APIs, manual memory rebinding, and Unmanaged — escape "
                    + "hatches out of Swift's memory safety that should be audited."
            )
        ]
        registry.register(patterns: patterns)
    }
}
