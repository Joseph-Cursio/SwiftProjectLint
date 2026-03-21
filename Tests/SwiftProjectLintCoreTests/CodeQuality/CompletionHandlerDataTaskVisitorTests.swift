import Testing
@testable import SwiftProjectLintCore
import SwiftSyntax
import SwiftParser

@Suite
struct CompletionHandlerDataTaskVisitorTests {

    private func makeVisitor() -> CompletionHandlerDataTaskVisitor {
        let pattern = CallbackDataTaskPatternRegistrar().pattern
        return CompletionHandlerDataTaskVisitor(pattern: pattern)
    }

    private func runVisitor(_ visitor: CompletionHandlerDataTaskVisitor, source: String) {
        let sourceFile = Parser.parse(source: source)
        visitor.walk(sourceFile)
    }

    // MARK: - Positive Cases

    @Test
    func testDetectsDataTaskWithTrailingClosure() throws {
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

    @Test
    func testDetectsDataTaskWithCompletionHandlerLabel() throws {
        let source = """
        URLSession.shared.dataTask(with: request, completionHandler: handler)
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("dataTask"))
    }

    @Test
    func testDetectsDownloadTaskWithClosure() throws {
        let source = """
        session.downloadTask(with: url) { tempURL, response, error in
            guard let tempURL = tempURL else { return }
            process(tempURL)
        }
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("downloadTask"))
    }

    @Test
    func testDetectsUploadTaskWithCompletionHandler() throws {
        let source = """
        session.uploadTask(with: request, from: bodyData, completionHandler: handler)
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)

        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.message.contains("uploadTask"))
    }

    // MARK: - Negative Cases

    @Test
    func testNoIssueForAsyncData() {
        let source = """
        let (data, response) = try await session.data(from: url)
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForDataTaskWithoutClosure() {
        let source = """
        let task = session.dataTask(with: url)
        task.resume()
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForAsyncDownload() {
        let source = """
        let (localURL, response) = try await URLSession.shared.download(from: url)
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test
    func testNoIssueForUnrelatedMethod() {
        let source = """
        let result = processor.dataTask(with: input)
        """

        let visitor = makeVisitor()
        runVisitor(visitor, source: source)

        #expect(visitor.detectedIssues.isEmpty)
    }
}
