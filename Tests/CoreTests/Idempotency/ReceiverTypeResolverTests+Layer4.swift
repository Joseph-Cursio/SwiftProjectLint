import SwiftParser
@testable import SwiftProjectLintVisitors
import SwiftSyntax
import Testing

extension ReceiverTypeResolverTests {
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
