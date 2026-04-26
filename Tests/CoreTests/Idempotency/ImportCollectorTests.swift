import Testing
@testable import SwiftProjectLintIdempotencyRules
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import SwiftParser

/// Structural tests for `ImportCollector` — the visitor that produces
/// the base-module import set consumed by the framework-whitelist gate.
/// Split off from `FrameworkWhitelistGatingTests` into its own file so
/// the base struct stays under SwiftLint's `type_body_length` threshold.
@Suite
struct ImportCollectorTests {

    // MARK: - ImportCollector

    @Test
    func importCollector_extractsTopLevelImports() {
        let source: SourceFileSyntax = Parser.parse(source: """
        import Foundation
        import NIOCore
        @preconcurrency import Logging
        """)
        let imports = ImportCollector.imports(in: source)
        #expect(imports == ["Foundation", "NIOCore", "Logging"])
    }

    @Test
    func importCollector_handlesSubmoduleImports() {
        let source: SourceFileSyntax = Parser.parse(source: """
        import class Foundation.JSONDecoder
        import NIOCore.ByteBuffer
        """)
        let imports = ImportCollector.imports(in: source)
        // Base-module names only; submodule paths collapse.
        #expect(imports == ["Foundation", "NIOCore"])
    }

    @Test
    func importCollector_emptyForNoImports() {
        let source: SourceFileSyntax = Parser.parse(source: """
        func foo() {}
        """)
        let imports = ImportCollector.imports(in: source)
        #expect(imports.isEmpty)
    }
}
