import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors
import Foundation

struct URLSessionUnhandledError: PatternRegistrarProtocol {

    var pattern: SyntaxPattern {
        SyntaxPattern(
            name: .urlSessionUnhandledError,
            visitor: URLSessionUnhandledErrorVisitor.self,
            severity: .warning,
            category: .networking,
            messageTemplate: "URLSession completion handler does not reference the 'error' parameter — "
                + "network failures are silently ignored",
            suggestion: "Check 'if let error { … }' before using 'data'. "
                + "A non-nil error means the request failed regardless of data.",
            description: "Detects URLSession dataTask/downloadTask/uploadTask completion handlers "
                + "that do not reference the error parameter, causing network failures to be silently swallowed."
        )
    }
}
