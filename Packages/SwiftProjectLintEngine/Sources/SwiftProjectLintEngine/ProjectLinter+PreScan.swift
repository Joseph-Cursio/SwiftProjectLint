import SwiftProjectLintConfig
import SwiftProjectLintModels
import SwiftProjectLintRegistry
import SwiftProjectLintVisitors

/// The project-wide pre-scan: the catalogs per-file visitors cannot compute alone, and the two
/// ways they are handed on — to the detector, and to each file's analysis environment.
extension ProjectLinter {

    /// The cross-file type catalogs the visitors need, gathered in one pre-scan.
    ///
    /// Bundled into a single value so the pre-scan, the detector, and the per-file environment
    /// each take one parameter instead of ten — adding an eleventh collector then touches this
    /// type and nothing else.
    struct CollectedTypes: Sendable {
        let identifiable: Set<String>
        let enums: Set<String>
        let actors: Set<String>
        let local: Set<String>
        let observable: Set<String>
        let protocols: Set<String>
        let equatable: Set<String>
        let values: Set<String>
        let functions: Set<String>
        /// Base names of every `mutating func` — see `MutatingMethodCollector`.
        let mutatingMethods: Set<String>
        let defaultedInitializers: Set<String>
        /// `View` names reading `@Environment(SomeType.self)`. See
        /// `ObservableEnvironmentViewCollector` for why the keypath form is excluded.
        let observableEnvironmentViews: Set<String>
        let inspectedTypeNames: Set<String>
        /// `typealias` names whose underlying type is a function type.
        let functionTypeAliases: Set<String>
        /// Member names declared under `@_spi(...)`.
        let spiMembers: Set<String>
        let underscoredMembers: Set<String>
        /// Per type, the sibling methods that are themselves functions of their inputs. Unlike the
        /// name sets above this needs the parsed bodies, not just declarations, so it is resolved
        /// by its own fixpoint rather than by `collectTypes`.
        let cleanInstanceMethods: CleanInstanceMethodCatalog

        /// Per type, the member names its `extension` blocks declare. A per-file visitor that
        /// reasons about what a type's members read needs this to know when it is looking at
        /// only part of the type — see `ExtensionMemberCatalog`.
        let extensionMembers: ExtensionMemberCatalog

        /// Value types whose whole content is one closure — already a seam. See
        /// `ClosureWrapperTypeCatalog`.
        let closureWrapperTypes: ClosureWrapperTypeCatalog

        /// Package function names this project's own purity oracle refutes with an
        /// establishable witness — the one-hop callee join. Needs parsed bodies for the
        /// same reason `cleanInstanceMethods` does, and shares the single parse below.
        ///
        /// A per-file visitor cannot compute this: the callee whose verdict sinks a
        /// candidate is usually in another file. This pre-pass is the project's existing
        /// answer to that, which is why the join arrives as a `known*` set rather than by
        /// converting a rule to cross-file — the cross-file dispatch path does not forward
        /// the `known*` catalogs at all, so a rule that moved onto it would silently lose
        /// the type knowledge its candidacy test depends on. Measured, when that route was
        /// tried: 377 candidate symbols dropped out.
        let impurePackageFunctions: Set<String>

        static func collect(from filePaths: [String]) -> Self {
            // Parsed once and shared: both body-needing collectors below walk the same
            // trees, and parsing a project twice to build two catalogs is the kind of
            // cost that does not show up until someone points the linter at a large tree.
            let parsed = parseAll(filePaths)
            return Self(
                identifiable: collectTypes(IdentifiableTypeCollector.self, from: filePaths),
                enums: collectTypes(EnumTypeCollector.self, from: filePaths),
                actors: collectTypes(ActorTypeCollector.self, from: filePaths),
                local: collectTypes(LocalTypeCollector.self, from: filePaths),
                observable: collectTypes(ObservableTypeCollector.self, from: filePaths),
                protocols: collectTypes(ProtocolTypeCollector.self, from: filePaths),
                equatable: collectTypes(EquatableConformanceCollector.self, from: filePaths),
                values: collectTypes(ValueTypeCollector.self, from: filePaths),
                functions: collectTypes(DeclaredFunctionCollector.self, from: filePaths),
                mutatingMethods: collectTypes(MutatingMethodCollector.self, from: filePaths),
                defaultedInitializers: collectTypes(
                    DefaultedInitializerCollector.self, from: filePaths
                ),
                observableEnvironmentViews: collectTypes(
                    ObservableEnvironmentViewCollector.self, from: filePaths
                ),
                inspectedTypeNames: collectTypes(
                    InspectedTypeNameCollector.self, from: filePaths
                ),
                functionTypeAliases: collectTypes(FunctionTypeAliasCollector.self, from: filePaths),
                spiMembers: collectTypes(SPIMemberCollector.self, from: filePaths),
                underscoredMembers: collectTypes(UnderscoredMemberCollector.self, from: filePaths),
                cleanInstanceMethods: CleanInstanceMethodCatalog.build(
                    from: parsed, enumTypes: collectTypes(EnumTypeCollector.self, from: filePaths)
                ),
                extensionMembers: ExtensionMemberCatalog.build(from: parsed),
                closureWrapperTypes: ClosureWrapperTypeCatalog.build(from: parsed),
                impurePackageFunctions: PackagePurityJoin(sources: parsed).settledImpureNames
            )
        }
    }

    /// The caller's detector (or a fresh one) primed with the pre-scan catalogs and config.
    static func configuredDetector(
        _ detector: (any SourcePatternDetectorProtocol)?,
        collected: CollectedTypes,
        configuration: LintConfiguration
    ) -> any SourcePatternDetectorProtocol {
        var resolved = detector ?? SourcePatternDetector()
        resolved.knownIdentifiableTypes = collected.identifiable
        resolved.knownEnumTypes = collected.enums
        resolved.knownActorTypes = collected.actors
        resolved.knownLocalTypeNames = collected.local
        resolved.knownObservableTypes = collected.observable
        resolved.knownObservableEnvironmentViews = collected.observableEnvironmentViews
        resolved.knownInspectedTypeNames = collected.inspectedTypeNames
        resolved.knownSPIMembers = collected.spiMembers
        resolved.knownUnderscoredMembers = collected.underscoredMembers
        resolved.knownFunctionTypeAliases = collected.functionTypeAliases
        resolved.knownProtocolTypes = collected.protocols
        resolved.knownEquatableTypes = collected.equatable
        resolved.knownValueTypes = collected.values
        resolved.knownCleanInstanceMethods = collected.cleanInstanceMethods
        resolved.knownExtensionMembers = collected.extensionMembers
        resolved.knownClosureWrapperTypes = collected.closureWrapperTypes
        resolved.knownImpurePackageFunctions = collected.impurePackageFunctions
        resolved.knownProjectFunctions = collected.functions
        resolved.knownMutatingMethods = collected.mutatingMethods
        resolved.knownDefaultedInitializerTypes = collected.defaultedInitializers
        resolved.layerPolicies = configuration.architecturalLayers
        resolved.enabledFrameworkAllowlists = configuration.enabledFrameworkAllowlists
        return resolved
    }

    /// Spreads the bundled catalogs back into the flat per-file environment.
    static func makeEnvironment(
        projectRoot: String,
        registry: PatternVisitorRegistry,
        categories: [PatternCategory]?,
        ruleIdentifiers: [RuleIdentifier]?,
        collected: CollectedTypes,
        configuration: LintConfiguration
    ) -> FileAnalysisEnvironment {
        FileAnalysisEnvironment(
            projectRoot: projectRoot,
            registry: registry,
            categories: categories,
            ruleIdentifiers: ruleIdentifiers,
            identifiableTypes: collected.identifiable,
            observableEnvironmentViews: collected.observableEnvironmentViews,
            inspectedTypeNames: collected.inspectedTypeNames,
            functionTypeAliases: collected.functionTypeAliases,
            spiMembers: collected.spiMembers,
            underscoredMembers: collected.underscoredMembers,
            enumTypes: collected.enums,
            actorTypes: collected.actors,
            localTypes: collected.local,
            observableTypes: collected.observable,
            protocolTypes: collected.protocols,
            equatableTypes: collected.equatable,
            valueTypes: collected.values,
            projectFunctions: collected.functions,
            mutatingMethods: collected.mutatingMethods,
            impurePackageFunctions: collected.impurePackageFunctions,
            defaultedInitializerTypes: collected.defaultedInitializers,
            extensionMembers: collected.extensionMembers,
            closureWrapperTypes: collected.closureWrapperTypes,
            cleanInstanceMethods: collected.cleanInstanceMethods,
            enabledFrameworkAllowlists: configuration.enabledFrameworkAllowlists,
            layerPolicies: configuration.architecturalLayers
        )
    }
}
