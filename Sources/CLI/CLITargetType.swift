import ArgumentParser
import Core

/// The target type hint passed via `--target-type`.
///
/// A CLI-side mirror of ``TargetType`` rather than a conformance on it: making the
/// engine's enum `ExpressibleByArgument` would put an ArgumentParser dependency in
/// the engine to serve one flag.
enum CLITargetType: String, ExpressibleByArgument, CaseIterable {
    case auto
    case app
    case library

    var coreTargetType: TargetType {
        switch self {
        case .auto: .auto
        case .app: .app
        case .library: .library
        }
    }
}
