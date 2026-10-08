@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// A type named from inside its own declaration is not a caller depending on it.
///
/// The advice — *prefer a protocol abstraction* — is for a caller, which could name the protocol
/// instead. Code inside the type is the type's own implementation: its methods, its extensions,
/// and the types nested in it. A protocol in front of the type would be conformed to by that one
/// type, for the benefit of that type's own code, so the finding has no end state to reach.
///
/// Four Hummingbird findings were this shape: `Parser`'s sub-parser initialiser taking another
/// `Parser`, its nested `Iterator` holding the parser it walks, and
/// `HTTP2ServerConnectionManager`'s nested `LoopBoundHandler` and `HTTP2StreamDelegate` holding
/// their owner. The guard began as an actor-only one, added with the actor narrowing; it is the
/// same guard for every kind of type.
@Suite("A type named inside its own declaration is not reported")
struct ConcreteTypeUsageSelfReferenceTests {

    private func issues(_ source: String) -> [LintIssue] {
        let visitor = ConcreteTypeUsageVisitor(patternCategory: .architecture)
        let syntax = Parser.parse(source: source)
        visitor.setSourceLocationConverter(
            SourceLocationConverter(fileName: "Subject.swift", tree: syntax)
        )
        visitor.setFilePath("Subject.swift")
        visitor.walk(syntax)
        return visitor.detectedIssues.filter { $0.ruleName == RuleIdentifier.concreteTypeUsage }
    }

    // MARK: - Inside the type

    @Test("a copy initialiser taking the type's own type is not reported")
    func copyInitializer() {
        let source = """
        struct RequestParser {
            private let buffer: [UInt8]
            init(_ parser: RequestParser) { self.buffer = parser.buffer }
        }
        """
        #expect(issues(source).isEmpty)
    }

    @Test("a type nested in its owner, holding the owner, is not reported")
    func nestedTypeHoldingItsOwner() {
        // Hummingbird's two `HTTP2ServerConnectionManager` shapes: the nested type declared in an
        // extension, and the same nested type declared in the owner's body.
        let inExtension = """
        final class ConnectionManager { }
        extension ConnectionManager {
            struct LoopBoundHandler {
                let handler: ConnectionManager
                init(_ handler: ConnectionManager) { self.handler = handler }
            }
        }
        """
        let inBody = """
        final class ConnectionManager {
            struct StreamDelegate {
                let handler: ConnectionManager
            }
        }
        """
        #expect(issues(inExtension).isEmpty)
        #expect(issues(inBody).isEmpty)
    }

    @Test("an extension method taking the type's own type is not reported")
    func extensionMethodTakingItsOwnType() {
        // Hummingbird's `Parser` sub-parser initialiser, and an ordinary method of the same shape.
        let source = """
        struct RequestParser { }
        extension RequestParser {
            private init(_ parser: RequestParser, range: Range<Int>) { }
            func merged(with other: RequestParser) -> Int { 0 }
        }
        """
        #expect(issues(source).isEmpty)
    }

    @Test("an extension of a nested type is inside the type it is nested in")
    func extensionOfNestedType() {
        // The `Parser.Iterator` property, declared inline, is exempt; moving the same member into
        // `extension Parser.Iterator` must not bring the finding back.
        let source = """
        struct RequestParser {
            struct Iterator { }
        }
        extension RequestParser.Iterator {
            func restarted(from parser: RequestParser) -> Self { self }
        }
        """
        #expect(issues(source).isEmpty)
    }

    @Test(
        "the guard holds for every kind of type, without any pre-scan",
        arguments: ["class", "struct", "enum", "actor"]
    )
    func everyKindOfType(kind: String) {
        // No enum or actor catalog is set, so nothing but the self-reference guard keeps the enum
        // and the actor quiet here.
        let source = """
        \(kind) SessionManager {
            func adopt(_ other: SessionManager) { }
        }
        """
        #expect(issues(source).isEmpty)
    }

    // MARK: - The control

    @Test("the same type named from a different type is still reported")
    func namedFromAnotherTypeIsReported() {
        // Hummingbird's `URI` holds a `Parser` too, and it is a caller: that finding stays.
        let source = """
        struct RequestParser {
            init(_ parser: RequestParser) { }
        }
        struct URI {
            private var parser: RequestParser
        }
        extension URI {
            func reparse(using parser: RequestParser) { }
        }
        """
        let found = issues(source)
        #expect(found.count == 2)
        let messages = found.map(\.message)
        #expect(messages.contains { $0.hasPrefix("Property 'parser' declares concrete type 'RequestParser'") })
        #expect(messages.contains { $0.hasPrefix("Parameter 'using' uses concrete type 'RequestParser'") })
    }

    @Test("a namesake nested in another type does not lend its name to the outer one")
    func onlyTheEnclosingTypesCount() {
        // `Outer` names its own nested `RequestParser`: the parser is not an enclosing type of the
        // property, so `Outer` is a caller of it like any other.
        let source = """
        struct Outer {
            struct RequestParser { }
            var parser: RequestParser
        }
        """
        #expect(issues(source).count == 1)
    }
}
