//
//  UIBaselineStore.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import Foundation

struct LoadedBaseline {
    /// Absolute path to the baseline manifest JSON.
    let manifestPath: String

    /// Baseline name.
    let name: String

    /// Absolute path to the expected screenshot PNG.
    let screenshotPath: String

    /// Reusable screenshot ignore regions stored in the baseline manifest.
    let ignoreRegions: [ScreenshotIgnoreRegion]

    /// Node ignore-region descriptions stored in the baseline manifest.
    let ignoredNodeRegions: [[String: Any]]

    /// Named-mask ignore-region descriptions stored in the baseline manifest.
    let ignoredMaskRegions: [[String: Any]]

    /// Unresolved named masks stored in the baseline manifest.
    let unresolvedIgnoreMasks: [String]

    /// Node-query ignore-region descriptions stored in the baseline manifest.
    let ignoredQueryRegions: [[String: Any]]

    /// Unresolved node-query descriptions stored in the baseline manifest.
    let unresolvedIgnoreQueries: [[String: Any]]

    /// Absolute path to the baseline node index JSON.
    let nodeIndexPath: String?

    /// Lightweight runtime node snapshots saved during baseline recording.
    let baselineNodes: [[String: Any]]

    /// Absolute path to the baseline node-detail index JSON.
    let nodeDetailIndexPath: String?

    /// Node-detail semantic summaries saved during baseline recording.
    let baselineNodeDetails: [[String: Any]]
}

struct UIBaselineStore {
    private static let schemaVersion = 2

    private let decoder: ScreenshotPayloadDecoder

    init(decoder: ScreenshotPayloadDecoder = ScreenshotPayloadDecoder()) {
        self.decoder = decoder
    }

    func record(
        appId: String,
        screenshotPayload: [String: Any],
        hierarchy: [String: Any],
        nodeIndex: [String: Any],
        nodeDetailIndex: [String: Any],
        command: BaselineRecordCommand,
        ignoredNodeRegions: [[String: Any]] = [],
        ignoredMaskRegions: [[String: Any]] = [],
        unresolvedIgnoreMasks: [String] = [],
        ignoredQueryRegions: [[String: Any]] = [],
        unresolvedIgnoreQueries: [[String: Any]] = []
    ) throws -> [String: Any] {
        let outputDirectory = URL(fileURLWithPath: command.outputDirectory, isDirectory: true)
        let fileStem = sanitizedFileStem(from: command.name)
        let screenshotURL = outputDirectory.appendingPathComponent("\(fileStem).png")
        let hierarchyURL = outputDirectory.appendingPathComponent("\(fileStem).hierarchy.json")
        let nodeIndexURL = outputDirectory.appendingPathComponent("\(fileStem).nodes.json")
        let nodeDetailIndexURL = outputDirectory.appendingPathComponent("\(fileStem).node-details.json")
        let manifestURL = outputDirectory.appendingPathComponent("\(fileStem).baseline.json")
        let decodedScreenshot = try decoder.decode(rawPayload: screenshotPayload)
        var screenshotMetadata = decodedScreenshot.metadata
        screenshotMetadata.removeValue(forKey: "base64")
        let masks: [String: Any] = [
            "ignoreRegions": command.ignoreRegions.map(\.dictionary),
            "ignoredNodeRegions": ignoredNodeRegions,
            "ignoredMaskRegions": ignoredMaskRegions,
            "unresolvedIgnoreMasks": unresolvedIgnoreMasks,
            "ignoredQueryRegions": ignoredQueryRegions,
            "unresolvedIgnoreQueries": unresolvedIgnoreQueries
        ]

        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try decodedScreenshot.data.write(to: screenshotURL, options: .atomic)
        try writeJSONObject(hierarchy, to: hierarchyURL)
        try writeJSONObject(nodeIndex, to: nodeIndexURL)
        try writeJSONObject(nodeDetailIndex, to: nodeDetailIndexURL)

        let manifest: [String: Any] = [
            "schemaVersion": Self.schemaVersion,
            "kind": "astrolabe-baseline",
            "name": command.name,
            "appId": appId,
            "createdAt": ISO8601DateFormatter().string(from: Date()),
            "files": [
                "screenshot": screenshotURL.lastPathComponent,
                "hierarchy": hierarchyURL.lastPathComponent,
                "nodeIndex": nodeIndexURL.lastPathComponent,
                "nodeDetails": nodeDetailIndexURL.lastPathComponent
            ],
            "masks": masks,
            "screenshot": screenshotMetadata,
            "nodeIndex": [
                "schemaVersion": nodeIndex["schemaVersion"] ?? Self.schemaVersion,
                "nodeCount": nodeIndex["nodeCount"] ?? 0
            ],
            "nodeDetails": [
                "schemaVersion": nodeDetailIndex["schemaVersion"] ?? Self.schemaVersion,
                "detailCount": nodeDetailIndex["detailCount"] ?? 0,
                "failedDetailCount": nodeDetailIndex["failedDetailCount"] ?? 0
            ]
        ]
        try writeJSONObject(manifest, to: manifestURL)

        return [
            "name": command.name,
            "appId": appId,
            "files": [
                "manifestPath": manifestURL.standardizedFileURL.path,
                "screenshotPath": screenshotURL.standardizedFileURL.path,
                "hierarchyPath": hierarchyURL.standardizedFileURL.path,
                "nodeIndexPath": nodeIndexURL.standardizedFileURL.path,
                "nodeDetailsPath": nodeDetailIndexURL.standardizedFileURL.path
            ],
            "masks": masks,
            "screenshot": screenshotMetadata,
            "nodeIndex": [
                "schemaVersion": nodeIndex["schemaVersion"] ?? Self.schemaVersion,
                "nodeCount": nodeIndex["nodeCount"] ?? 0
            ],
            "nodeDetails": [
                "schemaVersion": nodeDetailIndex["schemaVersion"] ?? Self.schemaVersion,
                "detailCount": nodeDetailIndex["detailCount"] ?? 0,
                "failedDetailCount": nodeDetailIndex["failedDetailCount"] ?? 0
            ]
        ]
    }

    func load(path: String) throws -> LoadedBaseline {
        let manifestURL = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: manifestURL)
        let manifest = try jsonObject(from: data, artifactName: "manifest")
        try validateSchema(
            in: manifest,
            expectedKind: "astrolabe-baseline",
            artifactName: "manifest"
        )
        guard let files = manifest["files"] as? [String: Any],
              let screenshotPath = files["screenshot"] as? String else {
            throw CLIError.invalidBaseline("manifest is missing files.screenshot")
        }

        let screenshotURL: URL
        if screenshotPath.hasPrefix("/") {
            screenshotURL = URL(fileURLWithPath: screenshotPath)
        } else {
            screenshotURL = manifestURL.deletingLastPathComponent().appendingPathComponent(screenshotPath)
        }
        let nodeIndex = try loadNodeIndex(from: files, relativeTo: manifestURL)
        let nodeDetails = try loadNodeDetails(from: files, relativeTo: manifestURL)
        return LoadedBaseline(
            manifestPath: manifestURL.standardizedFileURL.path,
            name: manifest["name"] as? String ?? "",
            screenshotPath: screenshotURL.standardizedFileURL.path,
            ignoreRegions: try ignoreRegions(from: manifest),
            ignoredNodeRegions: ignoredNodeRegions(from: manifest),
            ignoredMaskRegions: ignoredMaskRegions(from: manifest),
            unresolvedIgnoreMasks: unresolvedIgnoreMasks(from: manifest),
            ignoredQueryRegions: ignoredQueryRegions(from: manifest),
            unresolvedIgnoreQueries: unresolvedIgnoreQueries(from: manifest),
            nodeIndexPath: nodeIndex.path,
            baselineNodes: nodeIndex.nodes,
            nodeDetailIndexPath: nodeDetails.path,
            baselineNodeDetails: nodeDetails.details
        )
    }

    private func sanitizedFileStem(from name: String) -> String {
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = name.unicodeScalars.map { scalar in
            allowedCharacters.contains(scalar) ? Character(scalar) : "_"
        }
        let sanitized = String(scalars)
        return sanitized.isEmpty ? "baseline" : sanitized
    }

    private func writeJSONObject(_ object: [String: Any], to url: URL) throws {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw CLIError.invalidJSONObject
        }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }

    private func ignoreRegions(from manifest: [String: Any]) throws -> [ScreenshotIgnoreRegion] {
        guard let masks = manifest["masks"] as? [String: Any] else {
            return []
        }
        guard let regions = masks["ignoreRegions"] as? [[String: Any]] else {
            return []
        }
        return try regions.map(ScreenshotIgnoreRegion.init(dictionary:))
    }

    private func ignoredNodeRegions(from manifest: [String: Any]) -> [[String: Any]] {
        guard let masks = manifest["masks"] as? [String: Any],
              let regions = masks["ignoredNodeRegions"] as? [[String: Any]] else {
            return []
        }
        return regions
    }

    private func ignoredMaskRegions(from manifest: [String: Any]) -> [[String: Any]] {
        guard let masks = manifest["masks"] as? [String: Any],
              let regions = masks["ignoredMaskRegions"] as? [[String: Any]] else {
            return []
        }
        return regions
    }

    private func unresolvedIgnoreMasks(from manifest: [String: Any]) -> [String] {
        guard let masks = manifest["masks"] as? [String: Any],
              let names = masks["unresolvedIgnoreMasks"] as? [String] else {
            return []
        }
        return names
    }

    private func ignoredQueryRegions(from manifest: [String: Any]) -> [[String: Any]] {
        guard let masks = manifest["masks"] as? [String: Any],
              let regions = masks["ignoredQueryRegions"] as? [[String: Any]] else {
            return []
        }
        return regions
    }

    private func unresolvedIgnoreQueries(from manifest: [String: Any]) -> [[String: Any]] {
        guard let masks = manifest["masks"] as? [String: Any],
              let queries = masks["unresolvedIgnoreQueries"] as? [[String: Any]] else {
            return []
        }
        return queries
    }

    private func loadNodeIndex(from files: [String: Any], relativeTo manifestURL: URL) throws -> (path: String?, nodes: [[String: Any]]) {
        guard let nodeIndexPath = files["nodeIndex"] as? String, !nodeIndexPath.isEmpty else {
            return (nil, [])
        }
        let nodeIndexURL: URL
        if nodeIndexPath.hasPrefix("/") {
            nodeIndexURL = URL(fileURLWithPath: nodeIndexPath)
        } else {
            nodeIndexURL = manifestURL.deletingLastPathComponent().appendingPathComponent(nodeIndexPath)
        }
        let data = try Data(contentsOf: nodeIndexURL)
        let nodeIndex = try jsonObject(from: data, artifactName: "node index")
        try validateSchema(in: nodeIndex, expectedKind: nil, artifactName: "node index")
        guard let nodes = nodeIndex["nodes"] as? [[String: Any]] else {
            throw CLIError.invalidBaseline("node index is missing nodes")
        }
        return (nodeIndexURL.standardizedFileURL.path, nodes)
    }

    private func loadNodeDetails(from files: [String: Any], relativeTo manifestURL: URL) throws -> (path: String?, details: [[String: Any]]) {
        guard let nodeDetailsPath = files["nodeDetails"] as? String, !nodeDetailsPath.isEmpty else {
            return (nil, [])
        }
        let nodeDetailsURL: URL
        if nodeDetailsPath.hasPrefix("/") {
            nodeDetailsURL = URL(fileURLWithPath: nodeDetailsPath)
        } else {
            nodeDetailsURL = manifestURL.deletingLastPathComponent().appendingPathComponent(nodeDetailsPath)
        }
        let data = try Data(contentsOf: nodeDetailsURL)
        let nodeDetails = try jsonObject(
            from: data,
            artifactName: "node detail index"
        )
        try validateSchema(
            in: nodeDetails,
            expectedKind: nil,
            artifactName: "node detail index"
        )
        guard let details = nodeDetails["details"] as? [[String: Any]] else {
            throw CLIError.invalidBaseline("node detail index is missing details")
        }
        return (nodeDetailsURL.standardizedFileURL.path, details)
    }

    private func validateSchema(
        in object: [String: Any],
        expectedKind: String?,
        artifactName: String
    ) throws {
        guard let schemaVersion = object["schemaVersion"] as? NSNumber,
              schemaVersion.intValue == Self.schemaVersion else {
            throw CLIError.invalidBaseline("\(artifactName) has an unsupported schemaVersion")
        }
        if let expectedKind,
           object["kind"] as? String != expectedKind {
            throw CLIError.invalidBaseline("\(artifactName) has an invalid kind")
        }
    }

    private func jsonObject(
        from data: Data,
        artifactName: String
    ) throws -> [String: Any] {
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CLIError.invalidBaseline("\(artifactName) is not a JSON object")
            }
            return object
        } catch let error as CLIError {
            throw error
        } catch {
            throw CLIError.invalidBaseline("\(artifactName) JSON could not be parsed")
        }
    }
}
