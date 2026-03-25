import Testing
import Core
@testable import CLI

@Suite
struct SeverityThresholdTests {

    // swiftprojectlint:disable Test Missing Require
    @Test func errorThresholdMapsToErrorSeverity() {
        #expect(SeverityThreshold.error.issueSeverity == .error)
    }

    // swiftprojectlint:disable Test Missing Require
    @Test func warningThresholdMapsToWarningSeverity() {
        #expect(SeverityThreshold.warning.issueSeverity == .warning)
    }

    // swiftprojectlint:disable Test Missing Require
    @Test func infoThresholdMapsToInfoSeverity() {
        #expect(SeverityThreshold.info.issueSeverity == .info)
    }

    // swiftprojectlint:disable Test Missing Require
    @Test func allCasesAreCovered() {
        #expect(SeverityThreshold.allCases.count == 3)
    }

    // swiftprojectlint:disable Test Missing Require
    @Test func rawValuesMatchExpectedStrings() {
        #expect(SeverityThreshold.error.rawValue == "error")
        #expect(SeverityThreshold.warning.rawValue == "warning")
        #expect(SeverityThreshold.info.rawValue == "info")
    }
}
