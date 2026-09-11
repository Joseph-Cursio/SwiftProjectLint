@testable import Core
import Foundation
import SwiftParser
@testable import SwiftProjectLintRules
import SwiftSyntax
import Testing

/// The exemption half of the rule's tests; the shared `analyzeSource` helper and
/// the violation half live in `ArchitectureBooleanControlCouplingViolationTests.swift`.
@Suite
struct ArchitectureBooleanControlCouplingExemptionTests {

    @Test func ignoresBoolParameterStoredNotBranched() {
        let source = """
        struct S {
            var enabled: Bool
            init(enabled: Bool) {
                self.enabled = enabled
            }
        }
        """
        #expect(analyzeBooleanControlCoupling(source).isEmpty)
    }

    @Test func ignoresOptionalBehaviorWithoutElse() {
        // `if verbose { log() }` is optional embellishment, not two strategies.
        let source = """
        struct S {
            func run(verbose: Bool) {
                doWork()
                if verbose {
                    log()
                }
            }
        }
        """
        #expect(analyzeBooleanControlCoupling(source).isEmpty)
    }

    @Test func ignoresBooleanToValueMapping() {
        // Each arm returns a single literal/value — a bool→value map, not control coupling.
        let source = """
        struct S {
            func color(isError: Bool) -> String {
                if isError {
                    return "red"
                } else {
                    return "green"
                }
            }
        }
        """
        #expect(analyzeBooleanControlCoupling(source).isEmpty)
    }

    @Test func ignoresOverriddenFunction() {
        // The signature is inherited and can't be changed freely.
        let source = """
        class Child: Parent {
            override func render(animated: Bool) {
                if animated {
                    animateIn()
                } else {
                    snapIn()
                }
            }
        }
        """
        #expect(analyzeBooleanControlCoupling(source).isEmpty)
    }

    @Test func ignoresNonBooleanParameter() {
        let source = """
        struct S {
            func run(mode: Int) {
                if mode == 1 {
                    fast()
                } else {
                    slow()
                }
            }
        }
        """
        #expect(analyzeBooleanControlCoupling(source).isEmpty)
    }

    @Test func ignoresMemberAccessSharingParameterName() {
        // `config.flag` must not match a parameter named `flag`.
        let source = """
        struct S {
            func run(flag: Bool) {
                if config.flag {
                    pathA()
                } else {
                    pathB()
                }
            }
        }
        """
        #expect(analyzeBooleanControlCoupling(source).isEmpty)
    }

    @Test func ignoresStdlibCapacityConventionFlag() {
        // `keepCapacity` mirrors `removeAll(keepingCapacity:)` — exempt even
        // though it branches two ways.
        let source = """
        struct Buffer {
            func removeAll(keepCapacity: Bool) {
                if keepCapacity {
                    zeroOut()
                    retainStorage()
                } else {
                    deallocate()
                    resetCount()
                }
            }
        }
        """
        #expect(analyzeBooleanControlCoupling(source).isEmpty)
    }

    @Test func ignoresCapacityConventionByArgumentLabel() {
        // The convention lives on the label; the internal name differs but is
        // still exempt.
        let source = """
        struct Buffer {
            func clear(keepingCapacity keep: Bool) {
                if keep {
                    zeroOut()
                    retainStorage()
                } else {
                    deallocate()
                    resetCount()
                }
            }
        }
        """
        #expect(analyzeBooleanControlCoupling(source).isEmpty)
    }

    @Test func ignoresAlreadyNamedDispatch() {
        // Both arms are one call, so both paths already have names. This is the
        // rule doc's former canonical violating example — and the fix printed
        // beneath it was "call `premiumPrice()` / `standardPrice()` directly",
        // naming the two functions the example already had. Five of the eight
        // corpus findings were this shape.
        let source = """
        struct Checkout {
            func price(isPremium: Bool) -> Int {
                if isPremium {
                    return premiumPrice()
                } else {
                    return standardPrice()
                }
            }
        }
        """
        #expect(analyzeBooleanControlCoupling(source).isEmpty)
    }

    @Test func ignoresDispatchIntoAFrameworkAPI() {
        // `SwiftUMLStudio`'s arrowhead draw. `GraphicsContext.fill` / `.stroke`
        // are SwiftUI's, so there is no split available here at any price — the
        // finding could not be acted on even in principle.
        let source = """
        struct Diagram {
            func drawArrow(_ path: Path, filled: Bool, in context: inout GraphicsContext) {
                if filled {
                    context.fill(path, with: .color(.black))
                } else {
                    context.stroke(path, with: .color(.black), lineWidth: 1.5)
                }
            }
        }
        """
        #expect(analyzeBooleanControlCoupling(source).isEmpty)
    }

    @Test func ignoresDeferredInitializationOfOneValue() {
        // `SwiftInferProperties`' emitter. Both arms build `property`; the
        // branch selects a value that happens to need statements to compute.
        let source = """
        struct Emitter {
            func emit(call: String, isThrows: Bool) -> String {
                let property: String
                if isThrows {
                    let guarded = "(try? " + call + ")"
                    property = guarded + " == " + guarded
                } else {
                    let plain = call
                    property = equalityExpression(lhs: plain, rhs: plain)
                }
                return property
            }
        }
        """
        #expect(analyzeBooleanControlCoupling(source).isEmpty)
    }

    @Test func flagsAccumulationIntoAPreDeclaredVariable() {
        // The narrow half of `isDeferredValueSelection`: `result` is declared
        // *with* a value and the arms compound-assign to it, so this is
        // accumulation, not deferred initialization, and it still fires.
        let source = """
        struct S {
            func pick(advanced: Bool) -> Int {
                var result = 0
                if advanced {
                    result = 1
                    result += 10
                } else {
                    result = 2
                    result += 20
                }
                return result
            }
        }
        """
        #expect(analyzeBooleanControlCoupling(source).isEmpty == false)

        // And the other half: the declaration *is* deferred, but the arms end in
        // `+=`. Without this the test above would pass on the initializer check
        // alone and say nothing about which operators count.
        let accumulating = """
        struct S {
            func pick(advanced: Bool) -> Int {
                var total: Int
                if advanced {
                    total = 1
                    total += 10
                } else {
                    total = 2
                    total += 20
                }
                return total
            }
        }
        """
        #expect(analyzeBooleanControlCoupling(accumulating).isEmpty == false)
    }

    @Test func ignoresTestAndFixtureFiles() {
        // The same source fires in `Sample.swift` (see the control below), so
        // this asserts the path gate rather than the arm gates.
        let source = """
        struct S {
            func export(_ report: Report, asPDF: Bool) {
                if asPDF {
                    renderPDF(report)
                    attachMetadata(report)
                } else {
                    renderHTML(report)
                    inlineStyles(report)
                }
            }
        }
        """
        #expect(analyzeBooleanControlCoupling(source, filePath: "PricingTests.swift").isEmpty)
        #expect(analyzeBooleanControlCoupling(source, filePath: "Pricing.swift").isEmpty == false)
    }
}
