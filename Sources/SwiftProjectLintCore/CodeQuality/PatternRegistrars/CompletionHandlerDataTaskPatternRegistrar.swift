import Foundation

/// A registrar for the completion-handler-data-task pattern.
///
/// Provides the pattern for detecting URLSession task methods with completion handlers
/// that should use async/await equivalents instead.
struct CallbackDataTaskPatternRegistrar: PatternRegistrar {

    var patterns: [SyntaxPattern] {
        [pattern]
    }

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .completionHandlerDataTask,
            visitor: CompletionHandlerDataTaskVisitor.self,
            severity: .info,
            category: .codeQuality,
            messageTemplate: "URLSession task with completion handler uses callback-based networking",
            suggestion: "Use async URLSession.data(from:) / .download(from:) / "
                + ".upload(for:from:) instead.",
            description: "Detects dataTask(with:completionHandler:), "
                + "downloadTask(with:completionHandler:), and uploadTask(with:...) calls "
                + "that should use async/await URLSession APIs."
        )
    }
}
