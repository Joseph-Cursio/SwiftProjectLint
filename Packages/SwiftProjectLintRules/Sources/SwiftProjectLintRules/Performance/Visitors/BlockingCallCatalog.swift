import SwiftSyntax

/// A synchronous call that holds its thread until a disk, a server or another thread answers.
struct BlockingCall {

    enum Kind {
        case fileRead, urlLoad, fileWrite, fileSystem, network, wait, sleep

        /// What the call does to the main actor, phrased to follow the call's name in a message.
        var phrase: String {
            switch self {
            case .fileRead: "reads a file synchronously on the main actor"
            case .urlLoad: "loads its URL synchronously on the main actor"
            case .fileWrite: "writes a file synchronously on the main actor"
            case .fileSystem: "does synchronous file-system work on the main actor"
            case .network: "makes a synchronous network request on the main actor"
            case .wait: "blocks the main actor until another thread signals it"
            case .sleep: "puts the main actor's thread to sleep"
            }
        }
    }

    /// The call as written, with its argument labels: `String(contentsOf:encoding:)`.
    let display: String
    let kind: Kind
}

/// The blocking calls `Blocking I/O On Main Actor` looks for.
///
/// Three blocking calls are left out on purpose, because another rule already reports them
/// wherever they appear. Reporting them here as well would put two findings on one line:
/// - `Data(contentsOf:)` with a URL that reads as remote → `Synchronous Network Call`.
/// - `Thread.sleep(...)` → `Thread Sleep`.
/// - a wait in an async scope that also creates the `DispatchSemaphore` → `Dispatch Semaphore
///   in Async` (`isReportedBySemaphoreRule`).
enum BlockingCallCatalog {

    /// Types whose `init(contentsOf:)` / `init(contentsOfFile:)` loads the whole resource before
    /// returning.
    private static let contentsInitializerTypes: Set<String> = [
        "Data", "NSData", "String", "NSString", "NSArray", "NSDictionary",
        "NSImage", "UIImage", "XMLParser"
    ]

    private static let contentsLabels: Set<String> = ["contentsOf", "contentsOfFile"]

    /// Member calls, keyed by `name|firstLabel`. The first label is `_` for an unlabeled first
    /// argument and empty for a call with no arguments. Each name is distinctive enough that
    /// the receiver's type need not be known: `contentsOfDirectory(atPath:)` is `FileManager`,
    /// `readDataToEndOfFile()` is `FileHandle`, `waitUntilExit()` is `Process`.
    private static let memberCalls: [String: BlockingCall.Kind] = [
        "contents|atPath": .fileRead,
        "readDataToEndOfFile|": .fileRead,
        "readToEnd|": .fileRead,
        "readData|ofLength": .fileRead,
        "read|upToCount": .fileRead,
        "write|to": .fileWrite,
        "write|toFile": .fileWrite,
        "contentsOfDirectory|atPath": .fileSystem,
        "contentsOfDirectory|at": .fileSystem,
        "subpathsOfDirectory|atPath": .fileSystem,
        "subpaths|atPath": .fileSystem,
        "copyItem|at": .fileSystem,
        "copyItem|atPath": .fileSystem,
        "sendSynchronousRequest|_": .network,
        "wait|": .wait,
        "wait|timeout": .wait,
        "wait|wallTimeout": .wait,
        "waitUntilExit|": .wait,
        "waitUntilAllOperationsAreFinished|": .wait,
        "waitUntilFinished|": .wait
    ]

    /// Free functions from the C library, each taking one unlabeled argument.
    private static let sleepFunctions: Set<String> = ["sleep", "usleep"]

    /// The blocking call `node` makes, or `nil` when it isn't one this rule reports.
    static func match(_ node: FunctionCallExprSyntax) -> BlockingCall? {
        if let declRef = node.calledExpression.as(DeclReferenceExprSyntax.self) {
            return matchTypeOrFunction(named: declRef.baseName.text, node: node, isInitCall: false)
        }
        guard let member = node.calledExpression.as(MemberAccessExprSyntax.self) else { return nil }
        let name = member.declName.baseName.text
        // `String.init(contentsOf:)` is the explicit spelling of `String(contentsOf:)`.
        if name == "init", let base = member.base?.as(DeclReferenceExprSyntax.self) {
            return matchTypeOrFunction(named: base.baseName.text, node: node, isInitCall: true)
        }
        guard let kind = memberCalls["\(name)|\(firstLabelKey(of: node))"] else { return nil }
        return BlockingCall(display: display(name, node), kind: kind)
    }

    private static func matchTypeOrFunction(
        named name: String,
        node: FunctionCallExprSyntax,
        isInitCall: Bool
    ) -> BlockingCall? {
        if contentsInitializerTypes.contains(name) {
            return matchContentsInitializer(typeName: name, node: node, isInitCall: isInitCall)
        }
        guard isInitCall == false, sleepFunctions.contains(name),
              node.arguments.count == 1, node.arguments.first?.label == nil else { return nil }
        return BlockingCall(display: display(name, node), kind: .sleep)
    }

    private static func matchContentsInitializer(
        typeName: String,
        node: FunctionCallExprSyntax,
        isInitCall: Bool
    ) -> BlockingCall? {
        guard let first = node.arguments.first, let label = first.label?.text,
              contentsLabels.contains(label) else { return nil }
        if label == "contentsOfFile" {
            return BlockingCall(display: display(typeName, node), kind: .fileRead)
        }
        // A URL is remote, or a file, or — for a plain `url` — either; the call blocks all the same.
        guard NetworkingVisitor.isLikelyLocalURL(first.expression) else {
            // `Synchronous Network Call` reports exactly this spelling with a remote-looking URL.
            let isReportedElsewhere = typeName == "Data" && isInitCall == false
            return isReportedElsewhere ? nil : BlockingCall(display: display(typeName, node), kind: .network)
        }
        return BlockingCall(display: display(typeName, node), kind: .urlLoad)
    }

    /// Whether `Dispatch Semaphore in Async` already covers this wait. That rule reports a
    /// `DispatchSemaphore(...)` created in an async function or closure; a wait in the same scope
    /// is the rest of that one defect.
    static func isReportedBySemaphoreRule(_ wait: FunctionCallExprSyntax) -> Bool {
        guard DispatchSemaphoreInAsyncVisitor.isInsideAsyncContext(Syntax(wait)),
              let scope = innermostScope(of: Syntax(wait)) else { return false }
        let finder = SemaphoreCreationFinder(viewMode: .sourceAccurate)
        finder.walk(scope)
        return finder.creations.contains { innermostScope(of: Syntax($0))?.id == scope.id }
    }

    /// The nearest function or closure — the scope `Dispatch Semaphore in Async` judges.
    private static func innermostScope(of node: Syntax) -> Syntax? {
        var current = node
        while let parent = current.parent {
            if parent.is(FunctionDeclSyntax.self) || parent.is(ClosureExprSyntax.self) {
                return parent
            }
            current = parent
        }
        return nil
    }

    private static func firstLabelKey(of node: FunctionCallExprSyntax) -> String {
        guard let first = node.arguments.first else {
            // A trailing closure is still an argument; `wait { }` is not `wait()`.
            return node.trailingClosure == nil ? "" : "_"
        }
        return first.label?.text ?? "_"
    }

    /// `name(label:label:)`, with `_` for unlabeled arguments.
    private static func display(_ name: String, _ node: FunctionCallExprSyntax) -> String {
        let labels = node.arguments.map { "\($0.label?.text ?? "_"):" }.joined()
        return "\(name)(\(labels))"
    }
}

/// The `DispatchSemaphore(...)` calls in a subtree.
private final class SemaphoreCreationFinder: SyntaxVisitor {
    private(set) var creations: [FunctionCallExprSyntax] = []

    override func visit(_ node: FunctionCallExprSyntax) -> SyntaxVisitorContinueKind {
        if node.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "DispatchSemaphore" {
            creations.append(node)
        }
        return .visitChildren
    }
}
