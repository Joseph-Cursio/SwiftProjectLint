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
        /// Actor names, and the all-`async` project protocols each conforms to — a join across
        /// files, so built by its own catalog rather than by `collectTypes`. See
        /// `ActorTypeCatalog`.
        let actors: ActorTypeCatalog
        let local: Set<String>
        let observable: Set<String>
        /// Declared protocols, plus the `typealias`es that stand for them — see
        /// `CompositionAliasCatalog.abstractionAliases(protocols:)`.
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

        /// Runs inside the run's `PackagePurity` binding, which is what makes the two
        /// purity-judging catalogs below — `CleanInstanceMethodCatalog` and
        /// `PackagePurityJoin` — construction-aware: each creates its `PurityInferrer()` here.
        static func collect(from filePaths: [String], sources: [String: SharedSource] = [:]) -> Self {
            // Parsed once and shared: every collector below — the name sets and the
            // body-needing catalogs alike — walks the same trees, and re-parsing a project
            // once per collector is the kind of cost that does not show up until someone
            // points the linter at a large tree. The trees are the run's shared parse — the
            // ones the purity facts were built from and the per-file visitors walk — in
            // discovery order. (`parseAll` covers only a caller that passes no shared parse.)
            let parsed = filePaths.compactMap { sources[$0]?.tree ?? parseAll([$0]).first }
            let declaredProtocols = collectTypes(ProtocolTypeCollector.self, in: parsed)
            let aliases = CompositionAliasCatalog.build(from: parsed)
            return Self(
                identifiable: collectTypes(IdentifiableTypeCollector.self, in: parsed),
                enums: collectTypes(EnumTypeCollector.self, in: parsed),
                actors: ActorTypeCatalog.build(from: parsed),
                local: collectTypes(LocalTypeCollector.self, in: parsed),
                observable: collectTypes(ObservableTypeCollector.self, in: parsed),
                protocols: declaredProtocols.union(
                    aliases.abstractionAliases(protocols: declaredProtocols)
                ),
                equatable: collectTypes(EquatableConformanceCollector.self, in: parsed),
                values: collectTypes(ValueTypeCollector.self, in: parsed),
                functions: collectTypes(DeclaredFunctionCollector.self, in: parsed),
                mutatingMethods: collectTypes(MutatingMethodCollector.self, in: parsed),
                defaultedInitializers: collectTypes(
                    DefaultedInitializerCollector.self, in: parsed
                ),
                observableEnvironmentViews: collectTypes(
                    ObservableEnvironmentViewCollector.self, in: parsed
                ),
                inspectedTypeNames: collectTypes(
                    InspectedTypeNameCollector.self, in: parsed
                ),
                functionTypeAliases: collectTypes(FunctionTypeAliasCollector.self, in: parsed),
                spiMembers: collectTypes(SPIMemberCollector.self, in: parsed),
                underscoredMembers: collectTypes(UnderscoredMemberCollector.self, in: parsed),
                cleanInstanceMethods: CleanInstanceMethodCatalog.build(
                    from: parsed, enumTypes: collectTypes(EnumTypeCollector.self, in: parsed)
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
        configuration: LintConfiguration,
        shared: [String: SharedSource] = [:]
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
            layerPolicies: configuration.architecturalLayers,
            shared: shared
        )
    }
}
