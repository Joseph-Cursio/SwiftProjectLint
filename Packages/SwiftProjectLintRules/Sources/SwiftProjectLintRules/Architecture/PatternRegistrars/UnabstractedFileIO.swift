import Foundation
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// A registrar for the unabstracted-file-I/O pattern.
///
/// Detects raw Foundation file access (`String(contentsOfFile:)`,
/// `Data(contentsOf:)`, `someText.write(to:)`) performed inline inside a
/// testable orchestration type (`…Model`/`…ViewModel`/`…Service`), where the
/// access should be routed through an injected reader/writer protocol seam so
/// the type can be unit-tested without touching the filesystem.
struct UnabstractedFileIO: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .unabstractedFileIO,
            visitor: UnabstractedFileIOVisitor.self,
            severity: .info,
            category: .architecture,
            messageTemplate: "Raw file I/O runs inline inside an orchestration type "
                + "— route it through an injected reader/writer seam.",
            suggestion: "Define a protocol for the file access, inject it through the "
                + "initializer, and call it instead of Foundation directly.",
            description: "Detects raw file reads/writes inside a Model/ViewModel/Service that "
                + "should delegate to an injected protocol seam, signalling a missed testability boundary."
        )
    }
}
