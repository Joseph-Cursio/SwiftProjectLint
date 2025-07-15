import Foundation

func getProjectFiles(testProjectPath: String) -> [String] {
    guard let enumerator = FileManager.default.enumerator(atPath: testProjectPath) else {
        return []
    }
    var swiftFiles: [String] = []
    while let filePath = enumerator.nextObject() as? String {
        if filePath.hasSuffix(".swift") {
            swiftFiles.append((testProjectPath as NSString).appendingPathComponent(filePath))
        }
    }
    return swiftFiles
}

// ... Add setupTestProject, setupEmptyTestProject, setupSingleFileProject, setupComplexTestProject, setupDuplicateStateProject, setupArchitectureIssuesProject as needed ... 