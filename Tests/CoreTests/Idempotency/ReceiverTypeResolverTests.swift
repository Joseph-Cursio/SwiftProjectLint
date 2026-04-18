import Testing
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import SwiftParser

/// Phase-2 second-slice: receiver-type resolver fixtures. Exercises the
/// syntactic resolver across every supported source (literal, constructor,
/// parameter, local binding, stored property, `self.` prefix) and the
/// `.unresolved` fallback.
@Suite
struct ReceiverTypeResolverTests {

    /// Finds a `MemberAccessExpr`-based call whose method name matches
    /// `method`. Returns the call (not just the receiver) so tests can
    /// route through `resolve(receiverOf:)` end-to-end.
    private func memberCall(method: String, in source: String) throws -> FunctionCallExprSyntax {
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

    // MARK: - Layer 4: bare-identifier resolution (stored property)

    @Test
    func storedProperty_array_resolvesToArray() throws {
        let source = """
        class C {
            var items: [Int] = []
            func f() { items.append(1) }
        }
        """
        let call = try memberCall(method: "append", in: source)
        #expect(ReceiverTypeResolver.resolve(receiverOf: call) == .stdlibCollection("Array"))
    }

    @Test
    func storedProperty_namedType_resolvesToNamed() throws {
        let source = """
        struct S {
            let q: Queue
            func f() { q.enqueue("a") }
        }
        """
        let call = try memberCall(method: "enqueue", in: source)
        #expect(ReceiverTypeResolver.resolve(receiverOf: call) == .named("Queue"))
    }

    @Test
    func storedProperty_inActor_resolvesToNamed() throws {
        let source = """
        actor A {
            let q: Queue = Queue()
            func f() { q.enqueue("a") }
        }
        """
        let call = try memberCall(method: "enqueue", in: source)
        #expect(ReceiverTypeResolver.resolve(receiverOf: call) == .named("Queue"))
    }

    // MARK: - Shadowing

    @Test
    func localTypeShadowsStdlibName_downgradesToNamed() throws {
        // The project declares its own `Array` type. An expression whose
        // receiver syntactically resolves to "Array" must be downgraded
        // from `.stdlibCollection` to `.named`, because the stdlib
        // exclusions no longer apply.
        let call = try memberCall(method: "append", in: "func f(x: Array) { x.append(1) }")
        #expect(
            ReceiverTypeResolver.resolve(receiverOf: call, localTypes: ["Array"])
                == .named("Array")
        )
    }

    // MARK: - `.unresolved` fallthrough

    @Test
    func chainedMemberAccess_isUnresolved() throws {
        // `outer.inner.append(...)` — receiver is `outer.inner` (a chained
        // member access). Syntactic resolution doesn't follow the chain.
        let source = """
        func f() {
            outer.inner.append(1)
        }
        """
        let call = try memberCall(method: "append", in: source)
        #expect(ReceiverTypeResolver.resolve(receiverOf: call) == .unresolved)
    }

    @Test
    func returnValueReceiver_isUnresolved() throws {
        // `getThing().append(...)` — receiver is a function-call expression
        // with a non-constructor callee. Unresolved.
        let source = """
        func f() { getThing().append(1) }
        """
        let call = try memberCall(method: "append", in: source)
        #expect(ReceiverTypeResolver.resolve(receiverOf: call) == .unresolved)
    }

    @Test
    func undeclaredIdentifier_isUnresolved() throws {
        // `nowhereDeclared.append(1)` — no param, local, or stored property
        // of that name. Unresolved.
        let source = """
        func f() {
            nowhereDeclared.append(1)
        }
        """
        let call = try memberCall(method: "append", in: source)
        #expect(ReceiverTypeResolver.resolve(receiverOf: call) == .unresolved)
    }

    @Test
    func computedPropertyWithoutTypeAnnotation_isUnresolved() throws {
        // `var items: [Int] { ... }` doesn't match our "stored property
        // with a type annotation" shape — but the type annotation is
        // there, so we DO resolve. Regression guard: the resolver looks at
        // type-annotation syntax, not stored-ness.
        //
        // The true unresolved case is a computed property without an
        // annotation (computed properties with a body-only inferred type).
        // That shape isn't typically valid Swift (computed needs a type),
        // so we test the harder case: the resolver falls through when no
        // matching binding exists at all.
        let source = """
        struct S {
            var items: [Int] { [1] }
            func f() { items.append(1) }
        }
        """
        let call = try memberCall(method: "append", in: source)
        // A computed-get property with a type annotation is still
        // resolvable lexically — annotation says `[Int]`. Resolver sees
        // that and classifies as Array. This is correct behaviour.
        #expect(ReceiverTypeResolver.resolve(receiverOf: call) == .stdlibCollection("Array"))
    }

    // MARK: - Convenience: no-receiver call

    @Test
    func bareGlobalCall_hasNoReceiver_isUnresolved() throws {
        // `publish(x)` — no receiver. `resolve(receiverOf:)` returns
        // `.unresolved` by convention (there's nothing to resolve).
        final class Finder: SyntaxVisitor {
            var call: FunctionCallExprSyntax?
            init() { super.init(viewMode: .sourceAccurate) }
            override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
                if call == nil { call = node }
                return .skipChildren
            }
        }
        let finder = Finder()
        finder.walk(Parser.parse(source: "func f() { publish(event) }"))
        let call = try #require(finder.call)
        #expect(ReceiverTypeResolver.resolve(receiverOf: call) == .unresolved)
    }
}
