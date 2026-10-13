import SwiftParser
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// `CallSiteContextIndex` exists to make `parseContextAtCallSite(of:)` cheap, not to change it, so
/// every test here holds the index to the per-call lookup's answer, call by call.
///
/// Each shape is linted as written and once for each token in it with an annotation placed in
/// front of that token: on a line of its own, which can change how the code parses, and as an
/// inline block comment, which does not. That puts an annotation on every keyword, operator,
/// argument and closure a call can follow or contain, in every statement shape below.
@Suite("The call-site context index answers what the per-call lookup answers")
struct CallSiteContextIndexTests {

    static let shapes: [String] = [
        // A reducer: the annotation binds to `return`, to a ternary branch, inside a `case`.
        """
        func reduce(into state: inout State, action: Action) -> Effect<Action> {
            switch action {
            case .load:
                return .run { send in await send(.loaded(try await fetch())) }
            case .save:
                return state.dirty ? .none : .run { _ in try await save(state) }
            }
        }
        """,
        // Routes: nested trailing closures, `try` and `let`, an annotation of another kind above.
        """
        func routes(_ app: Application) throws {
            /// @lint.context once
            let api = app.grouped("api")
            try api.group("orders") { orders in
                orders.post { req in try await insert(req.content.decode(Order.self)) }
                let handler = orders.get(":id") { req in await find(req.parameters.get("id")) }
            }
            app.on(.POST, "login", use: login)
        }
        """,
        // Member chains, nested arguments, several statements on one line.
        """
        func chains() {
            _ = x.a().b { y in y.c() }.d(e(f(g())))
            h(); i { j() }; k.l(m: n { o() })
        }
        """,
        // No enclosing item: stored-property initialisers and a default argument.
        """
        struct Handlers {
            let first = makeHandler { request in respond(request) }
            var second: Handler = wrap(inner(make()))
            func call(_ value: Int = compute(seed())) {}
        }
        """,
        // Top-level code, an if-expression, guard, defer, do/catch, a computed property.
        """
        let value = if flag { left() } else { right(fallback()) }
        guard let item = load() else { fatalError(reason()) }
        defer { cleanUp() }
        do { try perform { step() } } catch { report(error) }
        var computed: Int { compute() }
        """,
        // Macros, `#if` around statements and inside a chain, interpolation, a block doc comment.
        """
        func expansions() {
            #expect(check(value()))
            #if DEBUG
            debugOnly { log("\\(describe(state()))") }
            #else
            release()
            #endif
            /** @lint.context retry_safe */
            withRetry(attempts: count()) { try attempt() }
            x.a()
            #if os(macOS)
                .b()
            #endif
        }
        """,
        // Code that does not parse: unclosed calls and braces, a dangling member access.
        """
        func broken() {
            foo(bar(
            x.( baz {
            let = qux() quux()
            .run { }
        """
    ]

    private static func calls(in tree: SourceFileSyntax) -> [FunctionCallExprSyntax] {
        final class Collector: SyntaxVisitor {
            var found: [FunctionCallExprSyntax] = []
            override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
                found.append(node)
                return .visitChildren
            }
        }
        let collector = Collector(viewMode: .sourceAccurate)
        collector.walk(tree)
        return collector.found
    }

    /// `source` with `annotation` spliced in where the text of each of its tokens begins.
    private static func placements(of annotation: String, in source: String) -> [String] {
        Parser.parse(source: source).tokens(viewMode: .sourceAccurate).map { token in
            let offset = token.positionAfterSkippingLeadingTrivia.utf8Offset
            let index = source.utf8.index(source.utf8.startIndex, offsetBy: offset)
            return source[..<index] + annotation + source[index...]
        }
    }

    /// Every call in `source` where the index and the per-call lookup disagree, and how many calls
    /// have a context at all, so a corpus that never reaches one cannot pass by agreeing on `nil`.
    private static func compare(_ source: String) -> (disagreements: [String], annotated: Int) {
        let tree = Parser.parse(source: source)
        let index = CallSiteContextIndex(tree)
        var disagreements: [String] = []
        var annotated = 0
        for call in calls(in: tree) {
            let expected = ContextAnnotationParser.parseContextAtCallSite(of: call)
            if expected != nil { annotated += 1 }
            let actual = index.context(of: call)
            if actual != expected {
                disagreements.append(
                    "\(call.trimmedDescription): index \(String(describing: actual)), lookup "
                        + "\(String(describing: expected)) in\n\(source)"
                )
            }
        }
        return (disagreements, annotated)
    }

    @Test("with an annotation before each token in turn", arguments: shapes)
    func everyPlacement(of shape: String) {
        let variants = [shape]
            + Self.placements(of: "\n/// @lint.context replayable\n", in: shape)
            + Self.placements(of: "/** @lint.context strict_replayable */ ", in: shape)
        var disagreements: [String] = []
        var annotated = 0
        for variant in variants {
            let result = Self.compare(variant)
            disagreements += result.disagreements
            annotated += result.annotated
        }
        #expect(disagreements.isEmpty, "\(disagreements.joined(separator: "\n\n"))")
        #expect(annotated > 0)
    }

    @Test("a call from a tree the index was not built from is looked up directly")
    func callFromAnotherTree() throws {
        let indexed = Parser.parse(source: "func plain() {\n    work()\n}\n")
        let other = Parser.parse(source: "func handler() {\n    /// @lint.context once\n    migrate { }\n}\n")
        let call = try #require(Self.calls(in: other).first)

        #expect(CallSiteContextIndex(indexed).context(of: call) == .once)
        #expect(CallSiteContextIndex().context(of: call) == .once)
    }
}
