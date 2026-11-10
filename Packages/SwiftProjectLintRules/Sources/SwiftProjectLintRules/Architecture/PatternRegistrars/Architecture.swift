import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// Registers patterns related to architectural best practices in SwiftUI.
/// This registrar handles patterns for dependency injection, coupling, and architectural principles.

class Architecture: BasePatternRegistrar {
    /// The architecture patterns registered as one table; the rest register one by one below.
    private static let categoryPatterns: [SyntaxPattern] = [
        SyntaxPattern(
            name: .missingDependencyInjection,
            visitor: ArchitectureVisitor.self,
            severity: .info,
            category: .architecture,
            messageTemplate: "Consider using dependency injection for {dependency}",
            suggestion: "Inject dependencies through initializers or environment",
            description: "Detects direct instantiation where dependency injection would be better"
        ),
        SyntaxPattern(
            name: .fatViewDetection,
            visitor: ArchitectureVisitor.self,
            severity: .warning,
            category: .architecture,
            messageTemplate: "View '{viewName}' has too many responsibilities, consider MVVM pattern",
            suggestion: "Extract business logic into an ObservableObject ViewModel",
            description: "Detects views that violate single responsibility principle"
        ),
    ]

    /// The coupling rules (instantiation, concrete types, implementation details, singletons,
    /// the Law of Demeter), registered after the category table in this order.
    private static let couplingPatterns: [SyntaxPattern] = [
        SyntaxPattern(
            name: .directInstantiation,
            visitor: DirectInstantiationVisitor.self,
            severity: .warning,
            category: .architecture,
            messageTemplate: "Direct instantiation of {typeName} detected",
            suggestion: "Inject dependencies through initializers or environment objects",
            description: "Detects direct instantiation of concrete types " +
                "where dependency injection would improve testability"
        ),
        SyntaxPattern(
            name: .concreteTypeUsage,
            visitor: ConcreteTypeUsageVisitor.self,
            severity: .info,
            category: .architecture,
            messageTemplate: "Concrete type {typeName} used where a protocol abstraction would improve testability",
            suggestion: "Define a protocol for {typeName} and use it as the type annotation",
            description: "Detects parameters and properties typed as concrete classes instead of protocols"
        ),
        SyntaxPattern(
            name: .accessingImplementationDetails,
            visitor: AccessingImplementationDetailsVisitor.self,
            severity: .warning,
            category: .architecture,
            messageTemplate: "Accessing implementation detail {memberName} bypasses encapsulation",
            suggestion: "Use the public interface or protocol instead of accessing {memberName} directly",
            description: "Detects underscore-prefixed member access and force-cast bypasses to concrete types"
        ),
        SyntaxPattern(
            name: .singletonUsage,
            visitor: SingletonUsageVisitor.self,
            severity: .warning,
            category: .architecture,
            messageTemplate: "Singleton access to {typeName} creates hard coupling",
            suggestion: "Inject {typeName} as a dependency instead of accessing .shared",
            description: "Detects .shared singleton access on service-like types"
        ),
        SyntaxPattern(
            name: .lawOfDemeter,
            visitor: LawOfDemeterVisitor.self,
            severity: .info,
            category: .architecture,
            messageTemplate: "Method chain violates the Law of Demeter",
            suggestion: "Encapsulate the access in a direct collaborator method",
            description: "Detects 3+ level member access chains (train wreck pattern)"
        ),
    ]

    override func registerPatterns() {
        registry.register(patterns: Self.categoryPatterns)
        registry.register(patterns: Self.couplingPatterns)
        registry.register(registrars: leafRegistrars)
    }

    /// The rules with a single-purpose visitor, each supplying its own pattern.
    private var leafRegistrars: [any PatternRegistrarProtocol] {
        [
            ComputedPropertyView(),
            FatProtocol(),
            SingleImplementationProtocol(),
            MirrorProtocol(),
            DuplicateStructShape(),
            SharedDomainEnumField(),
            PrimitiveBypassingDomainType(),
            PrimitiveNamedForDomainType(),
            ScatteredEnumMapping(),
            DuplicateEnumMapping(),
            ParallelEnumShape(),
            UnusedProtocolAbstraction(),
            UnusedProtocolRequirement(),
            CouldAdoptProtocol(),
            HoistableConformerMember(),
            HoistableSequenceOperation(),
            SubclassedForMocking(),
            UnabstractedFileIO(),
            SwiftDataUniqueAttribute(),
            GodViewModel(),
            ViewModelDirectDBAccess(),
            CircularDependency(),
            ArchitecturalBoundary(),
            BooleanControlCoupling(),
            ManualRegistrationList(),
            ParallelListDrift(),
            UndeclaredTargetDependency(),
            UnusedTargetDependency(),
            LayerDependency(),
            WideReachThrough(),
        ]
    }
}
