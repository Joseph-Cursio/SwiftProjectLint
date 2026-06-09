/// Type-name suffixes that conventionally mark a "service"-like type — one that
/// holds behaviour or dependencies and is therefore a candidate for protocol
/// abstraction, dependency injection, or the architectural checks that flag
/// direct instantiation, singleton access, and implementation-detail coupling.
///
/// This is the single source of truth for that suffix set. Every architecture
/// rule that keys off "does this name look like a service type" resolves against
/// it via `ServiceTypeSuffix.allCases` so the rules cannot silently drift apart
/// (they previously each held a private copy, and four of them had fallen behind
/// the `Analyzer`/`Simulator`/`Engine`/`Checker` additions).
enum ServiceTypeSuffix: String, CaseIterable {
    case manager = "Manager"
    case service = "Service"
    case store = "Store"
    case provider = "Provider"
    case client = "Client"
    case repository = "Repository"
    case handler = "Handler"
    case controller = "Controller"
    case factory = "Factory"
    case adapter = "Adapter"
    case viewModel = "ViewModel"
    case coordinator = "Coordinator"
    case generator = "Generator"
    case analyzer = "Analyzer"
    case simulator = "Simulator"
    case engine = "Engine"
    case checker = "Checker"

    /// Whether `name` ends with any service-type suffix.
    static func matches(_ name: String) -> Bool {
        allCases.contains { name.hasSuffix($0.rawValue) }
    }
}
