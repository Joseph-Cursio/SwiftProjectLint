/// The method names a logging call is spelled with, in one place.
///
/// Two rules ask a question about the same vocabulary from opposite ends.
/// `LoggingSensitiveDataVisitor` asks *"is this call writing to the log?"* and must stay on
/// Apple's `Logger` surface, because it reports a secret being logged and a false positive
/// there is an accusation. `CatchWithoutHandlingVisitor` asks *"did this catch block do
/// anything at all?"* and is better off recognising every logger anyone ships, because a
/// name it does not know turns a handled error into a reported one.
///
/// So the two sets genuinely differ, and the difference is now written down rather than
/// implied by two literals that happened not to match. `osLogger` is the closed roster of
/// `os.Logger`'s own methods; `anyLogger` adds the spellings third-party loggers use.
/// Before this, `CatchWithoutHandlingVisitor` carried the union as its own literal and the
/// relationship between the two was invisible — the shape `ParallelListDrift` reports.
enum LoggingMethod {

    /// `os.Logger`'s logging methods. Closed: this is an API surface, not a convention.
    static let osLogger: Set<String> = [
        "log", "trace", "debug", "info",
        "notice", "warning", "error", "critical", "fault"
    ]

    /// Spellings that are *not* on `os.Logger` but are what other logging libraries call
    /// the same levels — SwiftyBeaver's `verbose`, CocoaLumberjack's `warn`.
    static let thirdPartyOnly: Set<String> = ["verbose", "warn"]

    /// Any method name that reads as a logging call, whichever library it came from.
    static let anyLogger: Set<String> = osLogger.union(thirdPartyOnly)
}
