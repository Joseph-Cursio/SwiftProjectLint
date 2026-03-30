/// Protocol for loading and saving lint configuration.
///
/// Abstracts the YAML file I/O so that `ContentViewModel` and the CLI
/// can be tested with in-memory implementations.
public protocol ConfigurationPersistenceProtocol {
    /// The default config file name (e.g. `.swiftprojectlint.yml`).
    var defaultFileName: String { get }

    /// Loads configuration from the default location in a project directory.
    /// Returns `.default` if no config file exists.
    func load(projectRoot: String) -> LintConfiguration

    /// Loads configuration from an explicit file path.
    /// Returns `.default` if the file doesn't exist or can't be parsed.
    func load(from path: String) -> LintConfiguration

    /// Writes configuration to the given file path.
    func write(_ config: LintConfiguration, to path: String)
}

/// Default implementation backed by `LintConfigurationLoader` and `LintConfigurationWriter`.
public struct YAMLConfigurationPersistence: ConfigurationPersistenceProtocol {
    public let defaultFileName = LintConfigurationLoader.defaultFileName

    public init() {}

    public func load(projectRoot: String) -> LintConfiguration {
        LintConfigurationLoader.load(projectRoot: projectRoot)
    }

    public func load(from path: String) -> LintConfiguration {
        LintConfigurationLoader.load(from: path)
    }

    public func write(_ config: LintConfiguration, to path: String) {
        LintConfigurationWriter.write(config, to: path)
    }
}
