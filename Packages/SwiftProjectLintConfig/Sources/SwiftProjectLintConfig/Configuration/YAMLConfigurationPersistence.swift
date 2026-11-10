/// Default implementation backed by `LintConfigurationLoader` and `LintConfigurationWriter`.
public struct YAMLConfigurationPersistence: ConfigurationPersistenceProtocol {
    public let defaultFileName = LintConfigurationLoader.defaultFileName

    public init() { /* no-op */ }

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
