//
//  RuntimeUIInspecting.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/10.
//

import AstrolabeProtocol
import Foundation

package enum RuntimeUIPlatform: String, Encodable, Hashable {
    case ios
    case android
}

package enum RuntimeUICapability: String, Encodable, Hashable {
    case appDiscovery
    case hierarchy
    case nodeDetail
    case attributePatchDiscovery
    case attributePatching
}

package struct RuntimeUIProviderDescriptor {
    /// Stable Provider identifier used to distinguish platforms or runtime data implementations.
    package let identifier: String

    /// Platform inspected by the Provider.
    package let platform: RuntimeUIPlatform

    /// Runtime UI capabilities currently provided by the Provider.
    package let capabilities: Set<RuntimeUICapability>

    package init(
        identifier: String,
        platform: RuntimeUIPlatform,
        capabilities: Set<RuntimeUICapability>
    ) {
        self.identifier = identifier
        self.platform = platform
        self.capabilities = capabilities
    }
}

package struct RuntimeNodeDetailBatch {
    /// Node details indexed by requested OID.
    package let detailsByOID: [String: [String: Any]]

    /// Failure descriptions indexed by requested OID.
    package let failuresByOID: [String: String]
}

package protocol RuntimeUIPlatformResolving {
    func platform(for appId: String) throws -> RuntimeUIPlatform
}

package protocol RuntimeUIProviderTargeting {
    var descriptor: RuntimeUIProviderDescriptor { get }
    func canHandle(appId: String) -> Bool
}

package protocol RuntimeUIProviderLifecycle {
    func close()
}

package protocol RuntimeApplicationDiscovering {
    func fetchApps() throws -> [InspectableAppRecord]
}

package protocol RuntimeUIHierarchyCapturing {
    func fetchHierarchy(appId: String) throws -> [String: Any]
}

package protocol RuntimeUINodeDetailProviding {
    func fetchNodeDetail(appId: String, oid: String) throws -> [String: Any]
    func fetchNodeDetails(appId: String, oids: [String]) throws -> RuntimeNodeDetailBatch
}

extension RuntimeUINodeDetailProviding {
    package func fetchNodeDetails(
        appId: String,
        oids: [String]
    ) throws -> RuntimeNodeDetailBatch {
        var detailsByOID = [String: [String: Any]]()
        var failuresByOID = [String: String]()
        for oid in oids {
            do {
                detailsByOID[oid] = try fetchNodeDetail(appId: appId, oid: oid)
            } catch {
                failuresByOID[oid] = String(describing: error)
            }
        }
        return RuntimeNodeDetailBatch(
            detailsByOID: detailsByOID,
            failuresByOID: failuresByOID
        )
    }
}

package protocol RuntimeUIPatchCatalogProviding {
    func fetchPatchableAttributeCatalog(
        appId: String
    ) throws -> RuntimePatchableAttributesPayload
}

package protocol RuntimeUIAttributePatching {
    func applyAttributePatch(
        appId: String,
        oid: String,
        attributeIdentifier: String,
        value: RuntimeAttributeValue
    ) throws -> [String: Any]
    func fetchAttributePatches(appId: String) throws -> [String: Any]
    func revertAttributePatch(appId: String, patchID: String) throws -> [String: Any]
    func clearAttributePatches(appId: String) throws -> [String: Any]
}

package protocol RuntimeUIAppDiscoveryDiagnosing {
    func appDiscoveryDiagnostics() -> [RuntimeAppDiscoveryDiagnostic]
}

package protocol RuntimeUIInspecting:
    RuntimeUIPlatformResolving,
    RuntimeApplicationDiscovering,
    RuntimeUIAppDiscoveryDiagnosing,
    RuntimeUIHierarchyCapturing,
    RuntimeUINodeDetailProviding,
    RuntimeUIPatchCatalogProviding,
    RuntimeUIAttributePatching {}
