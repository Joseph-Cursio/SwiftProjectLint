import Testing
import Core
@testable import CLI

@Suite
struct SeverityThresholdTests {

    @Test func errorThresholdMapsToErrorSeverity() {
        #expect(SeverityThreshold.error.issueSeverity == .error)
    }

    @Test func warningThresholdMapsToWarningSeverity() {
        #expect(SeverityThreshold.warning.issueSeverity == .warning)
    }

    @Test func infoThresholdMapsToInfoSeverity() {
        #expect(SeverityThreshold.info.issueSeverity == .info)
    }

    @Test func allCasesAreCovered() {
        #expect(SeverityThreshold.allCases.count == 3)
    }

    @Test func rawValuesMatchExpectedStrings() {
        #expect(SeverityThreshold.error.rawValue == "error")
        #expect(SeverityThreshold.warning.rawValue == "warning")
        #expect(SeverityThreshold.info.rawValue == "info")
    }
}
