import Testing
import Foundation
import SwiftSyntax
import SwiftParser
@testable import SwiftProjectLintCore

/// Tests for NetworkingVisitor code paths that require typed closure parameters.
///
/// When closure parameters include type annotations (e.g., `(data: Data?, response: URLResponse?, error: Error?)`),
/// SwiftSyntax parses them as `ClosureParameterClauseSyntax` rather than `ClosureShorthandParameterListSyntax`.
/// This exercises the uncovered branches in `checkErrorHandlingInClosure`:
/// - `logClosureParameters`
/// - `checkErrorHandlingForErrorParameter` (all patterns)
/// - `reportIgnoredErrorParameter`
/// - The fewer-than-3-parameters guard
/// - The fallthrough to `checkErrorHandlingInBody` for non-error-named third param
@Suite("NetworkingVisitor Typed Closure Tests")
struct NetworkingVisitorTypedClosureTests {

    private func makeVisitor(source: String) -> NetworkingVisitor {
        let visitor = NetworkingVisitor(patternCategory: .networking)
        let syntax = Parser.parse(source: source)
        let converter = SourceLocationConverter(fileName: "test.swift", tree: syntax)
        visitor.setSourceLocationConverter(converter)
        visitor.setFilePath("test.swift")
        visitor.walk(syntax)
        return visitor
    }

    // MARK: - Typed closure with error parameter properly handled via "if let error"

    @Test("typed closure with if-let error handling reports no issues")
    func typedClosureWithIfLetError() throws {
        let source = """
        let url = URL(string: "https://example.com")!
        URLSession.shared.dataTask(with: url) { (data: Data?, response: URLResponse?, error: Error?) in
            if let error = error {
                print(error)
            }
        }.resume()
        """

        let visitor = makeVisitor(source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Typed closure with error parameter handled via "guard let error"

    @Test("typed closure with guard-let error handling reports no issues")
    func typedClosureWithGuardLetError() throws {
        let source = """
        let url = URL(string: "https://example.com")!
        URLSession.shared.dataTask(with: url) { (data: Data?, response: URLResponse?, error: Error?) in
            guard let error = error else { return }
            print(error)
        }.resume()
        """

        let visitor = makeVisitor(source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Typed closure with error parameter handled via "error != nil"

    @Test("typed closure with error-not-nil check reports no issues")
    func typedClosureWithErrorNotNilCheck() throws {
        let source = """
        let url = URL(string: "https://example.com")!
        URLSession.shared.dataTask(with: url) { (data: Data?, response: URLResponse?, error: Error?) in
            if error != nil {
                print("error occurred")
            }
        }.resume()
        """

        let visitor = makeVisitor(source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Typed closure with error parameter handled via "error." property access

    @Test("typed closure with error dot access reports no issues")
    func typedClosureWithErrorDotAccess() throws {
        let source = """
        let url = URL(string: "https://example.com")!
        URLSession.shared.dataTask(with: url) { (data: Data?, response: URLResponse?, error: Error?) in
            let desc = error.localizedDescription
            print(desc)
        }.resume()
        """

        let visitor = makeVisitor(source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Typed closure with error parameter handled via "error.description"

    @Test("typed closure with error description access reports no issues")
    func typedClosureWithErrorDescription() throws {
        let source = """
        let url = URL(string: "https://example.com")!
        URLSession.shared.dataTask(with: url) { (data: Data?, response: URLResponse?, error: Error?) in
            print(error.description)
        }.resume()
        """

        let visitor = makeVisitor(source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Typed closure with error parameter handled via "error as" cast

    @Test("typed closure with error-as cast reports no issues")
    func typedClosureWithErrorAsCast() throws {
        let source = """
        let url = URL(string: "https://example.com")!
        URLSession.shared.dataTask(with: url) { (data: Data?, response: URLResponse?, error: Error?) in
            let nsErr = error as NSError?
            print(nsErr?.code ?? 0)
        }.resume()
        """

        let visitor = makeVisitor(source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Typed closure with error parameter NOT handled

    @Test("typed closure with unhandled error parameter reports missing error handling")
    func typedClosureWithUnhandledError() throws {
        let source = """
        let url = URL(string: "https://example.com")!
        URLSession.shared.dataTask(with: url) { (data: Data?, response: URLResponse?, error: Error?) in
            print(data ?? Data())
        }.resume()
        """

        let visitor = makeVisitor(source: source)
        let issues = visitor.detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message == "Network request missing error handling")
        #expect(issue.severity == .warning)
    }

    // MARK: - Typed closure with ignored error parameter (_)

    @Test("typed closure with underscore error parameter reports ignored error")
    func typedClosureWithIgnoredErrorParameter() throws {
        let source = """
        let url = URL(string: "https://example.com")!
        URLSession.shared.dataTask(with: url) { (data: Data?, response: URLResponse?, _: Error?) in
            print(data ?? Data())
        }.resume()
        """

        let visitor = makeVisitor(source: source)
        let issues = visitor.detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message == "Network request ignores error parameter (_)")
        #expect(issue.severity == .warning)
        #expect(issue.filePath == "test.swift")
    }

    // MARK: - Typed closure with fewer than 3 parameters

    @Test("typed closure with two parameters falls back to body check and reports issue")
    func typedClosureWithTwoParameters() throws {
        let source = """
        let url = URL(string: "https://example.com")!
        URLSession.shared.dataTask(with: url) { (data: Data?, response: URLResponse?) in
            print("no error handling")
        }.resume()
        """

        let visitor = makeVisitor(source: source)
        let issues = visitor.detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message == "Network request missing error handling")
    }

    @Test("typed closure with two parameters and error handling in body reports no issues")
    func typedClosureTwoParamsWithErrorInBody() throws {
        let source = """
        let url = URL(string: "https://example.com")!
        URLSession.shared.dataTask(with: url) { (data: Data?, response: URLResponse?) in
            if let error = error {
                print(error)
            }
        }.resume()
        """

        let visitor = makeVisitor(source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Typed closure with non-standard third parameter name

    @Test("typed closure with non-error-named third parameter falls back to body check")
    func typedClosureWithNonErrorThirdParam() throws {
        let source = """
        let url = URL(string: "https://example.com")!
        URLSession.shared.dataTask(with: url) { (data: Data?, response: URLResponse?, failure: Error?) in
            print("no error handling here")
        }.resume()
        """

        let visitor = makeVisitor(source: source)
        let issues = visitor.detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message == "Network request missing error handling")
    }

    @Test("typed closure with non-error-named third parameter and error handling in body is clean")
    func typedClosureNonErrorThirdParamWithBodyHandling() throws {
        let source = """
        let url = URL(string: "https://example.com")!
        URLSession.shared.dataTask(with: url) { (data: Data?, response: URLResponse?, failure: Error?) in
            if let error = error {
                print(error)
            }
        }.resume()
        """

        let visitor = makeVisitor(source: source)
        #expect(visitor.detectedIssues.isEmpty)
    }

    // MARK: - Typed closure with single parameter

    @Test("typed closure with single parameter falls back to body check")
    func typedClosureWithSingleParam() throws {
        let source = """
        let url = URL(string: "https://example.com")!
        URLSession.shared.dataTask(with: url) { (result: Result<Data, Error>) in
            print("single param")
        }.resume()
        """

        let visitor = makeVisitor(source: source)
        let issues = visitor.detectedIssues
        #expect(issues.count == 1)
        let issue = try #require(issues.first)
        #expect(issue.message == "Network request missing error handling")
    }

    // MARK: - Issue metadata verification

    @Test("typed closure ignored error parameter issue has correct suggestion")
    func ignoredErrorSuggestion() throws {
        let source = """
        let url = URL(string: "https://example.com")!
        URLSession.shared.dataTask(with: url) { (data: Data?, response: URLResponse?, _: Error?) in
            print("ignored")
        }.resume()
        """

        let visitor = makeVisitor(source: source)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.suggestion == "Handle the error parameter instead of ignoring it")
        #expect(issue.ruleName == .missingErrorHandling)
    }

    // MARK: - Line number verification with typed closure

    @Test("typed closure issue reports correct line number")
    func typedClosureIssueLineNumber() throws {
        let source = """
        let url = URL(string: "https://example.com")!
        URLSession.shared.dataTask(with: url) { (data: Data?, response: URLResponse?, error: Error?) in
            print(data ?? Data())
        }.resume()
        """

        let visitor = makeVisitor(source: source)
        let issue = try #require(visitor.detectedIssues.first)
        #expect(issue.lineNumber > 0)
    }
}
