import XCTest
import AstrolabeProtocol
@testable import AstrolabeCLI

final class SemanticWorkflowTests: XCTestCase {
    private let node: [String: Any] = ["oid": "semantic-A-1", "className": "SwiftUI.AccessibilityNode", "kind": "semantic", "runtimeRole": "text", "customDisplayTitle": "Title", "subitems": []]

    func testSemanticNodesRemainInspectableWithoutInventingRenderFacts() throws {
        let extractor = HierarchyNodeExtractor()
        let records = extractor.collectNodeRecords(in: ["displayItems": [], "semanticItems": [node]])
        XCTAssertEqual(records.count, 1)
        let query = try FindNodesCommandParser().parse(arguments: []).query
        XCTAssertNotNil(HierarchyNodeFinder().firstNodeSnapshot(in: ["semanticItems": [node]], query: query))
        XCTAssertNil(extractor.visibility(from: node).onscreen)
        XCTAssertNil(extractor.visibility(from: node).hierarchyVisible)
        let snapshot = extractor.nodeSnapshot(from: node)
        for key in ["bounds", "hidden", "alpha", "visible", "onscreen", "hierarchyVisible", "frame"] {
            XCTAssertNil(snapshot[key], key)
        }
        let projection = HierarchyNodeSearchProjectionBuilder().buildProjection(from: HierarchyNodeRecord(node: node, hierarchyPath: "semantic[0]", depth: 0, siblingIndex: 0))
        XCTAssertNil(projection["visible"])
        for visible in [true, false] {
            let checked = NodeExpectationChecker().check(node: snapshot, expectation: NodeExpectation(className: nil, text: nil, visible: visible, frame: nil, tolerance: 0))
            XCTAssertEqual(checked["passed"] as? Bool, false)
        }
    }

    func testCaptureSelectorsRejectHistoricalAndNonsemanticWindowRequests() throws {
        XCTAssertThrowsError(try PageSnapshotArgumentParser().parse(arguments: ["--window-id", "window-1"]))
        XCTAssertThrowsError(try PageSnapshotArgumentParser().parse(arguments: ["--snapshot-id", UUID().uuidString, "--include-semantics"]))
        XCTAssertThrowsError(try PageSnapshotArgumentParser().parse(arguments: ["--snapshot-id", UUID().uuidString, "--include-semantics", "--window-id", "window-1"]))
    }

    func testFrozenDetailUsesOriginalRuntimeIdentityAndTimeAcrossNewCaptureAndOfflineCache() throws {
        let service = SemanticService()
        let store = SemanticStore()
        let resolver = PageHierarchyResolver(service: service, snapshotStore: store, now: { Date(timeIntervalSince1970: 900) })
        let captured = try resolver.resolve(appId: "app", snapshotIdentifier: nil, semanticCapture: RuntimeSemanticCaptureOptions())
        XCTAssertEqual(captured.snapshot.hierarchy["runtimeSnapshotId"] as? String, "runtime-A")
        XCTAssertEqual(captured.snapshot.hierarchy["runtimeCapturedAtUnixTime"] as? Double, 100)
        XCTAssertNotEqual(captured.snapshot.identifier, "runtime-A")
        service.runtimeID = "runtime-B"
        _ = try resolver.resolve(appId: "app", snapshotIdentifier: nil, semanticCapture: RuntimeSemanticCaptureOptions())
        let details = PageNodeDetailResolver(service: service, snapshotStore: store)
        let first = try details.resolve(appId: "app", oid: "semantic-A-1", snapshot: captured.snapshot)
        XCTAssertEqual(service.detailRequests, ["runtime-A"])
        XCTAssertEqual(first.capturedAt.timeIntervalSince1970, 100)
        XCTAssertEqual(first.source.rawValue, "runtimeSnapshot")
        service.offline = true
        let cached = try details.resolve(appId: "app", oid: "semantic-A-1", snapshot: captured.snapshot)
        XCTAssertEqual(cached.source.rawValue, "runtimeSnapshot")
        XCTAssertEqual(cached.capturedAt.timeIntervalSince1970, 100)
        XCTAssertEqual(service.detailRequests.count, 1)
        XCTAssertEqual(service.liveCalls, 0)
    }

    func testSemanticDetailRejectsMissingContextAndMismatchedFrozenTupleWithoutLiveFallback() throws {
        let service = SemanticService()
        let store = SemanticStore()
        let details = PageNodeDetailResolver(service: service, snapshotStore: store)
        XCTAssertThrowsError(try details.resolve(appId: "app", oid: "semantic-A-1", snapshot: nil))
        XCTAssertEqual(service.bareDetailRequests, 1)
        let page = try PageHierarchyResolver(service: service, snapshotStore: store).resolve(appId: "app", snapshotIdentifier: nil, semanticCapture: RuntimeSemanticCaptureOptions()).snapshot
        for field in ["snapshotID", "capturedAtUnixTime", "resolvedOid", "source"] {
            service.mismatch = field
            XCTAssertThrowsError(try details.resolve(appId: "app", oid: "semantic-A-1", snapshot: page), field)
        }
        service.mismatch = nil
        service.offline = true
        XCTAssertThrowsError(try details.resolve(appId: "app", oid: "semantic-A-1", snapshot: page))
        XCTAssertEqual(service.liveCalls, 0)
        store.pages.removeAll()
        XCTAssertThrowsError(try details.resolve(appId: "app", oid: "semantic-A-1", snapshotIdentifier: page.identifier))
    }

    func testGraphDerivesSeparateSemanticTreeEdges() throws {
        let id = UUID().uuidString
        var root = node
        root["subitems"] = [["oid": "semantic-child", "className": "AXChild", "runtimeRole": "button", "kind": "semantic", "subitems": []]]
        let page = PageHierarchySnapshot(identifier: id, createdAt: Date(), appId: "app", platform: .ios, hierarchy: ["snapshotId": id, "runtimeCapabilities": ["uiGraphRelations"], "displayItems": [], "semanticItems": [root], "relations": []])
        let graph = try RuntimeUIGraphIndexBuilder().build(from: RuntimeUIGraphSnapshotAdapter().adapt(page))
        XCTAssertEqual(graph.relations.map(\.type.rawValue), ["tree.semanticChild"])
    }

    func testSummaryExposesSemanticCandidatesWithoutClaimingVisibility() throws {
        let summary = HierarchySummaryBuilder().buildSummary(from: ["displayItems": [], "semanticItems": [node]])
        XCTAssertEqual(summary["visibleNodeCount"] as? Int, 0)
        let candidates = try XCTUnwrap(summary["semanticItems"] as? [[String: Any]])
        XCTAssertEqual(candidates.first?["oid"] as? String, "semantic-A-1")
        XCTAssertNil(candidates.first?["visible"])
    }

    func testMissingCandidateStyleCannotPassButPartialCanonicalFieldCan() throws {
        let context: [String: Any] = ["availability": "partial", "textCandidates": [["fields": [["attribute": ["identifier": "common.text.fontSize", "value": 28]]]]]]
        let builder = NodeDetailSummaryBuilder()
        let checker = NodeDetailExpectationChecker()
        let missing = builder.buildSummary(from: ["semanticContext": context, "attributeGroups": []], appId: "app")
        let expectation = NodeDetailExpectation(attribute: "fontSize", expectedValue: "28", contains: false, tolerance: nil)
        let refused = checker.check(summary: missing, expectation: expectation)
        XCTAssertEqual(refused["passed"] as? Bool, false)
        XCTAssertEqual(refused["verification"] as? String, "unableToVerify")
        let canonical = builder.buildSummary(from: ["semanticContext": context, "attributeGroups": [["identifier": "common.text", "sections": [["identifier": "properties", "attributes": [["identifier": "fontSize", "semanticPath": "common.text.fontSize", "attrTypeName": "measurement", "value": ["value": 28, "unit": "scaledLogical"]]]]]]]], appId: "app")
        XCTAssertEqual(checker.check(summary: canonical, expectation: expectation)["passed"] as? Bool, true)
        XCTAssertNotNil(canonical["semanticContext"])
        var ambiguous = canonical
        let attributes = try XCTUnwrap(canonical["attributes"] as? [[String: Any]])
        ambiguous["attributes"] = attributes + attributes
        let rejected = checker.check(summary: ambiguous, expectation: expectation)
        XCTAssertEqual(rejected["passed"] as? Bool, false)
        XCTAssertEqual(rejected["verification"] as? String, "unableToVerify")
    }
}

private final class SemanticService: RuntimeUIHierarchyCapturing, RuntimeUIPlatformResolving, RuntimeUINodeDetailProviding {
    var runtimeID = "runtime-A"
    var mismatch: String?
    var offline = false
    var detailRequests: [String] = []
    var liveCalls = 0
    var bareDetailRequests = 0
    func platform(for appId: String) throws -> RuntimeUIPlatform { .ios }
    func fetchHierarchy(appId: String) throws -> [String: Any] { liveCalls += 1; throw CLIError.nodeNotFound }
    func fetchHierarchy(appId: String, semanticCapture: RuntimeSemanticCaptureOptions?) throws -> [String: Any] {
        ["snapshotId": runtimeID, "capturedAtUnixTime": 100.0, "semanticCapture": ["source": "ios.accessibility"], "displayItems": [], "semanticItems": [["oid": "semantic-A-1", "kind": "semantic", "className": "SwiftUI.AccessibilityNode", "subitems": []]]]
    }
    func fetchNodeDetail(appId: String, oid: String) throws -> [String: Any] {
        bareDetailRequests += 1
        throw RuntimeError(code: .invalidParameters, message: "Semantic detail requires a saved context", recoverySuggestion: nil)
    }
    func fetchNodeDetail(appId: String, oid: String, runtimeSnapshotID: String) throws -> [String: Any] {
        detailRequests.append(runtimeSnapshotID)
        if offline { throw CLIError.hierarchySnapshotExpired }
        var context: [String: Any] = ["snapshotID": runtimeSnapshotID, "capturedAtUnixTime": 100.0, "source": "ios.accessibility", "availability": "partial", "issues": [], "wasTruncated": false, "textCandidates": []]
        if let mismatch { context[mismatch] = mismatch == "capturedAtUnixTime" ? 200.0 : "wrong" }
        return ["requestedOid": oid, "resolvedOid": mismatch == "resolvedOid" ? "wrong" : oid, "semanticContext": context, "attributeGroups": [], "extensions": ["vendor.test": true]]
    }
}

private final class SemanticStore: PageSnapshotStoring {
    var pages: [String: PageHierarchySnapshot] = [:]
    var details: [String: PageNodeDetailSnapshot] = [:]
    func saveHierarchy(_ snapshot: PageHierarchySnapshot) throws { pages[snapshot.identifier] = snapshot }
    func loadHierarchy(identifier: String, appId: String) throws -> PageHierarchySnapshot {
        guard let page = pages[identifier] else { throw CLIError.hierarchySnapshotExpired }
        return page
    }
    func saveNodeDetail(_ snapshot: PageNodeDetailSnapshot) throws { details[snapshot.snapshotIdentifier + snapshot.oid] = snapshot }
    func loadNodeDetail(snapshotIdentifier: String, appId: String, oid: String) throws -> PageNodeDetailSnapshot? { details[snapshotIdentifier + oid] }
}
