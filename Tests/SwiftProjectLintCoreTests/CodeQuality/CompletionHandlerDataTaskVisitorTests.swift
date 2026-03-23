import Testing
@testable import SwiftProjectLintCore
import SwiftSyntax
import SwiftParser

@Suite
struct CompletionHandlerDataTaskVisitorTests {

    private func makeVisitor() -> CompletionHandlerDataTaskVisitor {
        let pattern = CallbackDataTask().pattern
        return CompletionHandlerDataTaskVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: CompletionHandlerDataTaskVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Detailed Positive Case

    @Test
    func detectsDataTaskWithTrailingClosure() throws {
        let source = """
        session.dataTask(with: url) { data, response, error in
            guard let data = data else { return }
            print(data)
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .completionHandlerDataTask)
        #expect(issue.severity == .info)
        #expect(issue.message.contains("dataTask"))
    }

    // MARK: - Parameterized Positive Cases

    @Test("Detects completion handler task variant", arguments: [
        (
            """
            URLSession.shared.dataTask(with: request, completionHandler: handler)
            """,
            "dataTask"
        ),
        (
            """
            session.downloadTask(with: url) { tempURL, response, error in
                guard let tempURL = tempURL else { return }
                process(tempURL)
            }
            """,
            "downloadTask"
        ),
        (
            """
            session.uploadTask(with: request, from: bodyData, completionHandler: handler)
            """,
            "uploadTask"
        )
    ] as [(String, String)])
    func detectsVariant(source: String, expected: String) throws {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains(expected))
    }

    // MARK: - Negative Cases

    @Test("No issue for async or unrelated code", arguments: [
        // Async data
        """
        let (data, response) = try await session.data(from: url)
        """,
        // dataTask without closure
        """
        let task = session.dataTask(with: url)
        task.resume()
        """,
        // Async download
        """
        let (localURL, response) = try await URLSession.shared.download(from: url)
        """,
        // Unrelated method
        """
        let result = processor.dataTask(with: input)
        """
    ])
    func noIssue(source: String) {
        let visitor = makeVisitor()
        runVisitor(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }
}
