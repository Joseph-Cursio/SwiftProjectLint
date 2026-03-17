import ArgumentParser

/// The output format for lint results.
enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
    case text
    case json
}
