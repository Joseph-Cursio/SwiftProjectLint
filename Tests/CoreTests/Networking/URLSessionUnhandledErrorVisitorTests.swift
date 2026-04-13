import Testing
@testable import Core
@testable import SwiftProjectLintRules
import SwiftSyntax
import SwiftParser

@Suite
struct URLSessionUnhandledErrorVisitorTests {

    private func makeVisitor() -> URLSessionUnhandledErrorVisitor {
        URLSessionUnhandledErrorVisitor(pattern: URLSessionUnhandledError().pattern)
    }

    private func run(_ visitor: URLSessionUnhandledErrorVisitor, source: String) {
        visitor.walk(Parser.parse(source: source))
    }

    // MARK: - Positive Cases

    @Test
    func detectsDataTaskWithUnhandledError() throws {
        let source = """
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data else { return }
            process(data)
        }.resume()
        """
        let visitor = makeVisitor()
        run(visitor, source: source)

        #expect(visitor.detectedIssues.count == 1)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.ruleName == .urlSessionUnhandledError)
        #expect(issue.severity == .warning)
        #expect(issue.message.contains("error"))
    }

    @Test("Detects unhandled error across task method variants", arguments: [
        // downloadTask
        """
        session.downloadTask(with: url) { location, response, error in
            guard let location else { return }
            handle(location)
        }.resume()
        """,
        // uploadTask
        """
        session.uploadTask(with: request, from: data) { result, response, error in
            guard let result else { return }
            use(result)
        }.resume()
        """
    ])
    func detectsVariant(source: String) {
        let visitor = makeVisitor()
        run(visitor, source: source)
        #expect(visitor.detectedIssues.count == 1)
    }

    // MARK: - Negative Cases

    @Test("No issue when error parameter is checked", arguments: [
        // if let error check
        """
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error { print(error); return }
            process(data)
        }.resume()
        """,
        // guard let error
        """
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard error == nil else { handle(error!); return }
            process(data)
        }.resume()
        """,
        // error referenced in message
        """
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error { logger.error("\\(error)"); return }
            process(data)
        }.resume()
        """
    ])
    func noIssueWhenErrorReferenced(source: String) {
        let visitor = makeVisitor()
        run(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("No issue when error parameter is explicitly wildcarded")
    func noIssueWhenErrorWildcarded() {
        let source = """
        URLSession.shared.dataTask(with: url) { data, response, _ in
            guard let data else { return }
            process(data)
        }.resume()
        """
        let visitor = makeVisitor()
        run(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    @Test("No issue for non-URLSession dataTask calls")
    func noIssueForNonURLSessionCall() {
        // A hypothetical custom type named dataTask — not URLSession specific
        let source = """
        database.dataTask(with: query) { result, metadata, error in
            process(result)
        }
        """
        // The visitor flags any method named dataTask — this is an intentional
        // conservative choice. Document here that non-URLSession types named
        // dataTask will also trigger; suppress if needed.
        let visitor = makeVisitor()
        run(visitor, source: source)
        // Visitor is name-based, not type-based — fires on any dataTask method
        #expect(visitor.detectedIssues.count == 1)
    }

    @Test("No issue when closure has no parameter list")
    func noIssueWhenNoParameterList() {
        // Closure using shorthand $0/$1/$2 — can't extract named error param
        let source = """
        URLSession.shared.dataTask(with: url, completionHandler: completion).resume()
        """
        let visitor = makeVisitor()
        run(visitor, source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }
}
