import SwiftParser
import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

/// Phase-2 second-slice: receiver-type resolver fixtures. Exercises the
/// syntactic resolver across every supported source (literal, constructor,
/// parameter, local binding, stored property, `self.` prefix) and the
/// `.unresolved` fallback.
@Suite
struct ReceiverTypeResolverTests: FrameworkAllowlistTestSupport {

    /// Finds a `MemberAccessExpr`-based call whose method name matches
    /// `method`. Returns the call (not just the receiver) so tests can
    /// route through `resolve(receiverOf:)` end-to-end.
    func memberCall(method: String, in source: String) throws -> FunctionCallExprSyntax {
        final class Finder: SyntaxVisitor {
            let method: String
            var call: FunctionCallExprSyntax?

            init(method: String) {
                self.method = method
                super.init(viewMode: .sourceAccurate)
            }
            override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
                if call == nil,
                   let member = node.calledExpression.as(MemberAccessExprSyntax.self),
                   member.declName.baseName.text == method {
                    call = node
                }
                return .visitChildren
            }
        }
        let finder = Finder(method: method)
        finder.walk(Parser.parse(source: source))
        return try #require(finder.call, "expected a call to .\(method)")
    }

    // MARK: - Layer 1: literal shapes

    @Test
    func arrayLiteralReceiver_resolvesToArray() throws {
        let call = try memberCall(method: "append", in: "func f() { [1, 2].append(3) }")
        #expect(ReceiverTypeResolver.resolve(receiverOf: call) == .stdlibCollection("Array"))
    }

    @Test
    func dictionaryLiteralReceiver_resolvesToDictionary() throws {
        let call = try memberCall(method: "updateValue", in: #"func f() { ["a": 1].updateValue(2, forKey: "b") }"#)
        #expect(ReceiverTypeResolver.resolve(receiverOf: call) == .stdlibCollection("Dictionary"))
    }

    @Test
    func stringLiteralReceiver_resolvesToString() throws {
        let call = try memberCall(method: "append", in: #"func f() { "hello".append("!") }"#)
        #expect(ReceiverTypeResolver.resolve(receiverOf: call) == .stdlibCollection("String"))
    }

    // MARK: - Layer 2: constructor calls

    @Test
    func arrayGenericConstructor_resolvesToArray() throws {
        let call = try memberCall(method: "append", in: "func f() { Array<Int>().append(1) }")
        #expect(ReceiverTypeResolver.resolve(receiverOf: call) == .stdlibCollection("Array"))
    }

    @Test
    func userDefinedConstructor_resolvesToNamed() throws {
        let call = try memberCall(method: "enqueue", in: #"func f() { Queue().enqueue("a") }"#)
        #expect(ReceiverTypeResolver.resolve(receiverOf: call) == .named("Queue"))
    }

    @Test
    func lowercaseCalleeIsNotAConstructor_fallsToUnresolved() throws {
        // `makeQueue()` returns something, but syntactically it's a function
        // call with a lowercase callee — not a constructor. Unresolved.
        let call = try memberCall(method: "enqueue", in: #"func f() { makeQueue().enqueue("a") }"#)
        #expect(ReceiverTypeResolver.resolve(receiverOf: call) == .unresolved)
    }

    // MARK: - Layer 3: `self.` member access

    @Test
    func selfProperty_arrayType_resolvesToArray() throws {
        let source = """
        class C {
            var items: [Int] = []
            func f() { self.items.append(1) }
        }
        """
        let call = try memberCall(method: "append", in: source)
        #expect(ReceiverTypeResolver.resolve(receiverOf: call) == .stdlibCollection("Array"))
    }

    @Test
    func selfProperty_namedType_resolvesToNamed() throws {
        let source = """
        class C {
            let q: Queue = Queue()
            func f() { self.q.enqueue("a") }
        }
        """
        let call = try memberCall(method: "enqueue", in: source)
        #expect(ReceiverTypeResolver.resolve(receiverOf: call) == .named("Queue"))
    }

    // MARK: - Layer 4: bare-identifier resolution (parameter)

    @Test
    func parameter_genericArrayType_resolvesToArray() throws {
        let call = try memberCall(
            method: "append",
            in: "func f(x: Array<Int>) { x.append(1) }"
        )
        #expect(ReceiverTypeResolver.resolve(receiverOf: call) == .stdlibCollection("Array"))
    }

    @Test
    func parameter_arrayShorthand_resolvesToArray() throws {
        let call = try memberCall(method: "append", in: "func f(x: [Int]) { x.append(1) }")
        #expect(ReceiverTypeResolver.resolve(receiverOf: call) == .stdlibCollection("Array"))
    }

    @Test
    func parameter_dictionaryShorthand_resolvesToDictionary() throws {
        let call = try memberCall(
            method: "updateValue",
            in: "func f(d: [String: Int]) { d.updateValue(1, forKey: \"a\") }"
        )
        #expect(ReceiverTypeResolver.resolve(receiverOf: call) == .stdlibCollection("Dictionary"))
    }

    @Test
    func parameter_userType_resolvesToNamed() throws {
        let call = try memberCall(
            method: "enqueue",
            in: #"func f(q: Queue) { q.enqueue("a") }"#
        )
        #expect(ReceiverTypeResolver.resolve(receiverOf: call) == .named("Queue"))
    }

    @Test
    func parameter_withExternalLabel_usesLocalName() throws {
        // `func f(_ x: [Int])` — external label `_`, local name `x`.
        let call = try memberCall(method: "append", in: "func f(_ x: [Int]) { x.append(1) }")
        #expect(ReceiverTypeResolver.resolve(receiverOf: call) == .stdlibCollection("Array"))
    }

    // MARK: - Layer 4: bare-identifier resolution (local binding)

    @Test
    func localBinding_typed_resolvesToAnnotation() throws {
        let source = """
        func f() {
            let x: [Int] = []
            x.append(1)
        }
        """
        let call = try memberCall(method: "append", in: source)
        #expect(ReceiverTypeResolver.resolve(receiverOf: call) == .stdlibCollection("Array"))
    }

    @Test
    func localBinding_untypedFromArrayLiteral_resolvesToArray() throws {
        // Matches the Run D pattern: `var users = [owner]; users.append(...)`.
        let source = """
        func f(owner: User) {
            var users = [owner]
            users.append(other)
        }
        """
        let call = try memberCall(method: "append", in: source)
        #expect(ReceiverTypeResolver.resolve(receiverOf: call) == .stdlibCollection("Array"))
    }

    @Test
    func localBinding_untypedFromConstructor_resolvesToNamed() throws {
        let source = """
        func f() {
            let q = Queue()
            q.enqueue("a")
        }
        """
        let call = try memberCall(method: "enqueue", in: source)
        #expect(ReceiverTypeResolver.resolve(receiverOf: call) == .named("Queue"))
    }

    @Test
    func localBinding_untypedFromUnknownExpression_isUnresolved() throws {
        // Binding from a function call that isn't a constructor → unresolved.
        let source = """
        func f() {
            let q = makeQueue()
            q.enqueue("a")
        }
        """
        let call = try memberCall(method: "enqueue", in: source)
        #expect(ReceiverTypeResolver.resolve(receiverOf: call) == .unresolved)
    }

    @Test
    func localBinding_shadowsParameter() throws {
        // Local binding `x` later in the body shadows the outer parameter.
        // Resolver must use the inner binding's type.
        let source = """
        func f(x: Queue) {
            let x = [1, 2]
            x.append(3)
        }
        """
        let call = try memberCall(method: "append", in: source)
        #expect(ReceiverTypeResolver.resolve(receiverOf: call) == .stdlibCollection("Array"))
    }

    @Test
    func localBinding_afterUsage_doesNotApply() throws {
        // The binding appears lexically *after* the usage site. The
        // resolver must ignore it and fall through to the parameter.
        let source = """
        func f(x: [Int]) {
            x.append(1)
            let x = Queue()
        }
        """
        let call = try memberCall(method: "append", in: source)
        #expect(ReceiverTypeResolver.resolve(receiverOf: call) == .stdlibCollection("Array"))
    }
}
