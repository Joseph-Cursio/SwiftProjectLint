import SwiftProjectLintModels

/// Every order a cross-file visitor could be handed a fixture's files in.
///
/// A harness that walks a `[String: …]` file cache in its own iteration order walks it in hash-seed order, which
/// changes on every launch. A visitor whose result depends on that order then passes or fails by the seed: a mutation
/// tester sees a mutant in `PrimitiveNamedForDomainTypeVisitor` or `ContextSymbolTable` killed in some runs and not
/// others. Walking every order, and requiring the same result from each, makes that order-dependence fail every time.
/// Fixtures hold a handful of files, so the n! orders stay cheap.
enum WalkOrders {
    /// Every permutation of `paths`, the sorted order first.
    static func of(_ paths: [String]) -> [[String]] {
        let sorted = paths.sorted()
        guard sorted.count > 1 else { return [sorted] }
        return sorted.indices.flatMap { index in
            var rest = sorted
            let first = rest.remove(at: index)
            return of(rest).map { [first] + $0 }
        }
    }

    /// What two walks' issues are compared by: rule, message and locations, in an order of their own.
    static func signature(of issues: [LintIssue]) -> [String] {
        issues.map { issue in
            let locations = issue.locations.map { "\($0.filePath):\($0.lineNumber)" }.joined(separator: ",")
            return "\(issue.ruleName)|\(issue.message)|\(locations)"
        }
        .sorted()
    }
}
