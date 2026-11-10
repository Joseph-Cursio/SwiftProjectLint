import Foundation
import SwiftProjectLintModels
import SwiftProjectLintVisitors
import SwiftSyntax

extension DirectInstantiationVisitor {
    // MARK: - Composition roots

    /// Whether `node` sits in a body that is assembling an object graph rather than reaching
    /// for one dependency.
    ///
    /// Dependency injection has to bottom out. Somewhere a concrete graph is built, and that
    /// place is allowed — required — to name every concrete type it wires together; the whole
    /// benefit of injecting elsewhere is that there is exactly one such place. Reporting each
    /// construction inside it turns one architectural fact into a warning per line.
    ///
    /// Two conditions, and the second is what keeps this from being a neighbour count. The
    /// body must construct at least three distinct service-like types, **and** it must keep at
    /// least one of them past its own return, by assigning to a stored property of the
    /// enclosing type. That is what separates assembling a graph from using several tools.
    ///
    /// The condition was added after measuring the first version, which had only the count.
    /// `ProjectAnalyzer.analyze(paths:)` builds four diagram generators, uses each once and
    /// returns a summary; it went silent while an identical `ClassDiagramGenerator()` forty
    /// lines below, in a function with fewer neighbours, kept reporting. A rule that answers
    /// differently for the same construction depending on how many siblings it has is drawing
    /// the line on syntax rather than substance — which is the fault this rule's own
    /// documentation already records having corrected once, over defaulted parameters.
    func insideCompositionRoot(_ node: Syntax) -> Bool {
        guard let body = Self.enclosingBody(of: node) else { return false }
        let counter = ServiceConstructionCounter(viewMode: .sourceAccurate)
        counter.walk(body)
        guard counter.typeNames.count >= Self.compositionRootThreshold else { return false }
        return counter.retainsBeyondBody
    }

    /// How many *distinct* service-like types a body must construct before it can read as an
    /// assembler.
    ///
    /// Three, chosen by looking at what each value removes rather than by taste. At two, a
    /// function that reaches for a store and its index — the ordinary two-dependency case the
    /// rule exists to catch — would go silent. At three, with the retention condition, the
    /// corpus's roots are named and nothing else is: `AppState.constructCoreServices`,
    /// `assignStatelessServices`, `constructHigherLayers`, `ExtensionServiceContainer`\'s
    /// `commandHandler`, `KnowledgeGraph.init` — nine domain stores off one injected database
    /// — and the sandboxed `App`\'s `init`, whose file header calls itself a composition root
    /// in as many words.
    private static let compositionRootThreshold = 3

    /// The nearest enclosing function, initializer, or accessor body.
    ///
    /// Deliberately not the enclosing *type*: a type with ten service-typed stored properties
    /// is a container too, but its properties are usually declared without initializers and
    /// filled by one of these bodies, so the body is where the constructions actually are.
    private static func enclosingBody(of node: Syntax) -> Syntax? {
        var current: Syntax? = node.parent
        while let candidate = current {
            if let function = candidate.as(FunctionDeclSyntax.self) {
                return function.body.map(Syntax.init)
            }
            if let initializer = candidate.as(InitializerDeclSyntax.self) {
                return initializer.body.map(Syntax.init)
            }
            if let accessor = candidate.as(AccessorDeclSyntax.self) {
                return accessor.body.map(Syntax.init)
            }
            current = candidate.parent
        }
        return nil
    }
}
