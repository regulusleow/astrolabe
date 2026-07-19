//
//  CLICommandTestSupport.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/7/3.
//

import AstrolabeProtocol
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest

@testable import AstrolabeCLI
@testable import AstrolabeIOSDeviceSupport
@testable import AstrolabeIOSHost
@testable import AstrolabeIOSInspection
@testable import AstrolabeIOSScreenshot

enum CLICommandTestFixtures {
    final class FakeInspectorService:
        RuntimeUIProviderTargeting,
        RuntimeApplicationDiscovering,
        RuntimeUIHierarchyCapturing,
        RuntimeUINodeDetailProviding,
        RuntimeUIPatchCatalogProviding,
        RuntimeUIAttributePatching,
        RuntimeUIInspecting {
        /// Platform, identifier, and capability declaration of the fake Provider.
        var descriptor = RuntimeUIProviderDescriptor(
            identifier: "fake-provider",
            platform: .ios,
            capabilities: [
                .appDiscovery,
                .hierarchy,
                .nodeDetail,
                .attributePatchDiscovery,
                .attributePatching
            ]
        )

        /// Set of app IDs handled by the current fake Provider.
        var handledAppIds: Set<String> = []

        /// Simulated target-platform resolution failure.
        var platformResolutionError: Error?

        /// App list returned by the list-apps stub.
        var apps: [InspectableAppRecord] = []

        /// Hierarchy JSON returned by the capture-hierarchy stub.
        var hierarchy: [String: Any] = [:]

        /// Attribute JSON returned by the node-detail stub.
        var detail: [String: Any] = [:]

        /// Attribute JSON returned by the node-detail stub, keyed by OID.
        var detailsByOid: [String: [String: Any]] = [:]

        /// Screenshot JSON returned by the capture-screenshot stub.
        var screenshot: [String: Any] = [:]

        /// JSON returned by the attribute-patch command stub.
        var attributePatchResult: [String: Any] = [:]

        /// Patchable attribute catalog returned by the Runtime stub.
        var patchableAttributeCatalog = RuntimePatchableAttributesPayload(
            attributes: []
        )

        /// Service methods invoked by the command layer.
        var calls: [Call] = []

        func canHandle(appId: String) -> Bool {
            handledAppIds.contains(appId)
        }

        func platform(for appId: String) throws -> RuntimeUIPlatform {
            if let platformResolutionError {
                throw platformResolutionError
            }
            return descriptor.platform
        }

        func fetchApps() throws -> [InspectableAppRecord] {
            calls.append(.fetchApps)
            return apps
        }

        func appDiscoveryDiagnostics() -> [RuntimeAppDiscoveryDiagnostic] {
            []
        }

        func fetchHierarchy(appId: String) throws -> [String: Any] {
            calls.append(.fetchHierarchy(appId))
            return hierarchy
        }

        func fetchNodeDetail(appId: String, oid: String) throws -> [String: Any] {
            calls.append(.fetchNodeDetail(appId, oid))
            return detailsByOid[oid] ?? detail
        }

        func applyAttributePatch(
            appId: String,
            oid: String,
            attributeIdentifier: String,
            value: RuntimeAttributeValue
        ) throws -> [String: Any] {
            calls.append(.applyAttributePatch(appId, oid, attributeIdentifier, value))
            return attributePatchResult
        }

        func fetchPatchableAttributeCatalog(
            appId: String
        ) throws -> RuntimePatchableAttributesPayload {
            calls.append(.fetchPatchableAttributeCatalog(appId))
            return patchableAttributeCatalog
        }

        func fetchAttributePatches(appId: String) throws -> [String: Any] {
            calls.append(.fetchAttributePatches(appId))
            return attributePatchResult
        }

        func revertAttributePatch(appId: String, patchID: String) throws -> [String: Any] {
            calls.append(.revertAttributePatch(appId, patchID))
            return attributePatchResult
        }

        func clearAttributePatches(appId: String) throws -> [String: Any] {
            calls.append(.clearAttributePatches(appId))
            return attributePatchResult
        }

    }

    static func makePlatformModule(
        provider: FakeInspectorService
    ) throws -> HostPlatformModule {
        var builder = HostPlatformModuleBuilder(provider: provider)
        if provider.descriptor.capabilities.contains(.appDiscovery) {
            builder = builder.applicationDiscovery(provider)
        }
        if provider.descriptor.capabilities.contains(.hierarchy) {
            builder = builder
                .hierarchyCapture(provider)
                .screenInspectionBuilder(ScreenInspectionBuilder(
                    qualityPolicy: FakeScreenInspectionTargetQualityPolicy()
                ))
                .semanticRoleClassifier(NodeSemanticRoleClassifier())
        }
        if provider.descriptor.capabilities.contains(.nodeDetail) {
            builder = builder
                .nodeDetail(provider)
                .nodeDetailSemanticMapper(UIKitNodeDetailAttributeSemanticMapper())
                .nodeDetailIssueInterpreter(UIKitNodeDetailSemanticIssueInterpreter())
        }
        if provider.descriptor.capabilities.contains(.attributePatchDiscovery) {
            builder = builder.patchCatalog(provider)
        }
        if provider.descriptor.capabilities.contains(.attributePatching) {
            builder = builder.attributePatching(provider)
        }
        return try builder.build()
    }

    static func makePlatformRegistry(
        providers: [FakeInspectorService]
    ) throws -> HostPlatformModuleRegistry {
        try HostPlatformModuleRegistry(
            modules: providers.map(makePlatformModule(provider:))
        )
    }

    private struct FakeScreenInspectionTargetQualityPolicy:
        ScreenInspectionTargetQualityEvaluating {
        func isEligible(_ context: ScreenInspectionTargetEligibilityContext) -> Bool {
            !context.semanticRoles.contains(.window)
        }

        func priority(
            className: String,
            semanticRoles: Set<NodeSemanticRole>,
            reason: ScreenInspectionTargetReason
        ) -> Int {
            0
        }
    }

    final class FakeScreenshotProvider: ScreenshotProviding {
        /// Fixed screenshot payload to return.
        var payload: [String: Any]?

        /// Requests received by the Provider.
        var requests: [Request] = []

        func capture(
            appId: String,
            options: ScreenshotCaptureOptions,
            screenMetadata: () throws -> [String: Any]
        ) throws -> [String: Any] {
            requests.append(Request(appId: appId, captureOptions: options))
            guard let payload else {
                throw CLIError.invalidScreenshot("Test screenshot payload is not configured")
            }
            return payload
        }

        struct Request {
            /// App ID being captured.
            let appId: String

            /// Screenshot source configuration.
            let captureOptions: ScreenshotCaptureOptions
        }
    }

    final class FakePlatformScreenshotProvider: PlatformScreenshotProviding {
        /// Screenshot payload returned by the platform policy.
        let payload: [String: Any]

        /// App ID actually passed to the current policy.
        var capturedAppIds: [String] = []

        init(payload: [String: Any] = [:]) {
            self.payload = payload
        }

        func capture(
            appId: String,
            options: ScreenshotCaptureOptions,
            screenMetadata: () throws -> [String: Any]
        ) throws -> [String: Any] {
            capturedAppIds.append(appId)
            return payload
        }
    }

    struct FakeSimulatorScreenshotCapturer: SimulatorScreenshotCapturing {
        /// UDID of the single booted simulator.
        var bootedSimulatorUDID = "SIM-UDID"

        /// Simulator screenshot PNG data.
        var pngData = Data("simulator-png".utf8)

        func singleBootedSimulatorUDID() throws -> String {
            bootedSimulatorUDID
        }

        func captureScreenshot(udid: String) throws -> Data {
            pngData
        }
    }

    struct FakeDeviceScreenshotCapturer: DeviceScreenshotCapturing {
        /// Physical-device screenshot PNG data.
        let pngData: Data

        func captureScreenshot(deviceIdentifier: String) throws -> Data {
            pngData
        }
    }

    struct FakeDeviceIdentifierResolver: DeviceIdentifierResolving {
        /// Resolved devicectl device identifier.
        let deviceIdentifier: String?

        func resolvePhysicalIOSDeviceIdentifier(
            usbMuxDeviceIdentifier: String,
            requestedIdentifier: String?
        ) throws -> String {
            guard let deviceIdentifier else {
                throw CLIError.invalidScreenshot("Unable to bind the physical USB device")
            }
            if let requestedIdentifier,
                requestedIdentifier != deviceIdentifier
            {
                throw CLIError.invalidArgument(
                    "--target-id does not match the physical device running the USB Runtime"
                )
            }
            return deviceIdentifier
        }
    }

    struct FakeScreenshotUSBMuxDeviceDiscovery: USBMuxDeviceDiscovering {
        /// usbmux device identity returned by the test.
        let devices: [USBMuxDeviceIdentity]

        func connectedDevices() throws -> [USBMuxDeviceIdentity] {
            devices
        }
    }

    final class FakeDeviceLockStateReader: DeviceLockStateReading {
        /// Physical-device lock states returned in call order.
        private var states: [DeviceLockState]

        init(states: [DeviceLockState]) {
            self.states = states
        }

        func lockState(deviceIdentifier: String) throws -> DeviceLockState {
            guard !states.isEmpty else {
                throw CLIError.commandFailed("No physical-device lock state is available")
            }
            return states.removeFirst()
        }
    }

    struct FakeScreenshotImageContentInspector:
        ScreenshotImageContentInspecting
    {
        /// Whether the simulated screenshot is entirely black.
        let isBlack: Bool

        func isCompletelyBlack(_ data: Data) throws -> Bool {
            isBlack
        }
    }

    struct FakeScreenshotImageMetadataReader: ScreenshotImageMetadataReading {
        /// PNG pixel width.
        let pixelWidth: Int

        /// PNG pixel height.
        let pixelHeight: Int

        func metadata(from data: Data) throws -> ScreenshotImageMetadata {
            ScreenshotImageMetadata(pixelWidth: pixelWidth, pixelHeight: pixelHeight)
        }
    }

    struct FakeCommandRunner: CommandRunning {
        /// JSON object written to json-output after command execution.
        let jsonObject: [String: Any]

        func run(_ executable: String, arguments: [String]) throws -> Data {
            guard let outputFlagIndex = arguments.firstIndex(of: "--json-output"),
                outputFlagIndex + 1 < arguments.count
            else {
                throw CLIError.missingArgument("--json-output")
            }
            let outputPath = arguments[outputFlagIndex + 1]
            let data = try JSONSerialization.data(withJSONObject: jsonObject)
            if outputPath == "-" {
                return data
            }
            try data.write(to: URL(fileURLWithPath: outputPath))
            return Data()
        }
    }

    static func makeIOSSystemScreenshotProvider(
        lockStates: [DeviceLockState] = [unlockedDeviceState],
        isBlack: Bool = false
    ) -> IOSSystemScreenshotProvider {
        IOSSystemScreenshotProvider(
            simctl: FakeSimulatorScreenshotCapturer(),
            devicectl: FakeDeviceScreenshotCapturer(
                pngData: Data("device-png".utf8)
            ),
            deviceIdentifierResolver: FakeDeviceIdentifierResolver(
                deviceIdentifier: "DEVICE-UDID"
            ),
            deviceLockStateReader: FakeDeviceLockStateReader(states: lockStates),
            imageContentInspector: FakeScreenshotImageContentInspector(
                isBlack: isBlack
            ),
            payloadBuilder: ScreenshotPayloadBuilder(
                imageMetadataReader: FakeScreenshotImageMetadataReader(
                    pixelWidth: 1170,
                    pixelHeight: 2532
                )
            )
        )
    }

    static let unlockedDeviceState = DeviceLockState(
        passcodeRequired: false
    )

    static let lockedDeviceState = DeviceLockState(
        passcodeRequired: true
    )

    static func makeRunner(
        service: FakeInspectorService,
        paginationSnapshotDirectory: URL? = nil,
        pageSnapshotDirectory: URL? = nil
    ) -> CLICommandRunner {
        let screenshotProvider = FakeScreenshotProvider()
        screenshotProvider.payload = service.screenshot
        let paginationSnapshotStore: any HierarchyPaginationSnapshotStoring
        if let paginationSnapshotDirectory {
            paginationSnapshotStore = FileHierarchyPaginationSnapshotStore(
                directoryURL: paginationSnapshotDirectory
            )
        } else {
            paginationSnapshotStore = InMemoryHierarchyPaginationSnapshotStore()
        }
        let pageSnapshotStore: any PageSnapshotStoring
        if let pageSnapshotDirectory {
            pageSnapshotStore = FilePageSnapshotStore(directoryURL: pageSnapshotDirectory)
        } else {
            pageSnapshotStore = InMemoryPageSnapshotStore()
        }
        return CLICommandRunner(
            service: service,
            screenshotProvider: screenshotProvider,
            paginationSnapshotStore: paginationSnapshotStore,
            pageSnapshotStore: pageSnapshotStore,
            screenshotCaptureOptionsBuilders: [
                .ios: IOSSystemScreenshotCaptureOptionsBuilder()
            ],
            screenInspectionBuilders: [
                .ios: ScreenInspectionBuilder(
                    qualityPolicy: UIKitScreenInspectionTargetQualityPolicy()
                )
            ],
            semanticRoleClassifiers: [
                .ios: UIKitNodeSemanticRoleClassifier()
            ],
            namedMaskResolvers: [
                .ios: IOSSystemScreenshotNamedMaskResolver()
            ],
            nodeDetailSemanticMapper: UIKitNodeDetailAttributeSemanticMapper(),
            nodeDetailIssueInterpreter: UIKitNodeDetailSemanticIssueInterpreter(),
            visualDiffIssueInterpreter: UIKitVisualDiffIssueInterpreter()
        )
    }

    static func makeScreenshotRunner(
        service: FakeInspectorService,
        screenshotProvider: any ScreenshotProviding,
        screenshotCaptureOptionsBuilders: [
            RuntimeUIPlatform: any ScreenshotCaptureOptionsBuilding
        ] = [.ios: IOSSystemScreenshotCaptureOptionsBuilder()]
    ) -> CLICommandRunner {
        CLICommandRunner(
            service: service,
            screenshotProvider: screenshotProvider,
            screenshotCaptureOptionsBuilders: screenshotCaptureOptionsBuilders,
            screenInspectionBuilders: [:],
            semanticRoleClassifiers: [:],
            namedMaskResolvers: [:],
            nodeDetailSemanticMapper: UIKitNodeDetailAttributeSemanticMapper(),
            nodeDetailIssueInterpreter: UIKitNodeDetailSemanticIssueInterpreter(),
            visualDiffIssueInterpreter: UIKitVisualDiffIssueInterpreter()
        )
    }

    static func hierarchyWithLabelOids(_ oids: [Int]) -> [String: Any] {
        [
            "appId": "app-1",
            "displayItems": oids.map { oid in
                [
                    "oid": String(oid),
                    "detailOid": String(oid),
                    "className": "UILabel",
                    "frame": ["x": 0, "y": oid * 20, "width": 80, "height": 20],
                    "hidden": false,
                    "visible": true,
                    "alpha": 1
                ] as [String: Any]
            }
        ]
    }

    static func makeVisibleTextNode(oid: Int, text: String, y: Int) -> [String: Any] {
        [
            "oid": String(oid),
            "detailOid": String(oid),
            "className": "UILabel",
            "customDisplayTitle": text,
            "frame": ["x": 16, "y": y, "width": 120, "height": 20],
            "visible": true
        ]
    }

    static func makeVisibleNode(
        oid: Int,
        className: String,
        y: Int,
        width: Int = 100,
        height: Int = 40,
        semanticRoles: [String] = []
    ) -> [String: Any] {
        var node: [String: Any] = [
            "oid": String(oid),
            "detailOid": String(oid),
            "className": className,
            "frame": ["x": 0, "y": y, "width": width, "height": height],
            "visible": true
        ]
        if !semanticRoles.isEmpty {
            node["semanticRoles"] = semanticRoles
        }
        return node
    }

    enum Call: Equatable {
        case fetchApps
        case fetchHierarchy(String)
        case fetchNodeDetail(String, String)
        case fetchPatchableAttributeCatalog(String)
        case applyAttributePatch(String, String, String, RuntimeAttributeValue)
        case fetchAttributePatches(String)
        case revertAttributePatch(String, String)
        case clearAttributePatches(String)
    }

    static func makePNGData(width: Int, height: Int, pixels: [[UInt8]]) throws -> Data {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixelBytes = pixels.flatMap { $0 }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(
            CGContext(
                data: &pixelBytes,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
        let image = try XCTUnwrap(context.makeImage())
        let data = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    static func devicectlDevicesJSON(_ devices: [[String: Any]]) -> [String: Any] {
        [
            "result": [
                "devices": devices
            ]
        ]
    }

    static func devicectlDevice(
        name: String,
        udid: String,
        platform: String,
        reality: String,
        transportType: String,
        includesScreenshotCapability: Bool = true
    ) -> [String: Any] {
        let capabilities: [[String: Any]]
        if includesScreenshotCapability {
            capabilities = [
                [
                    "featureIdentifier": "com.apple.coredevice.feature.capturescreenshot",
                    "name": "Capture Screenshot"
                ]
            ]
        } else {
            capabilities = []
        }

        return [
            "identifier": "identifier-\(udid)",
            "capabilities": capabilities,
            "connectionProperties": [
                "transportType": transportType
            ],
            "deviceProperties": [
                "name": name
            ],
            "hardwareProperties": [
                "platform": platform,
                "reality": reality,
                "udid": udid
            ]
        ]
    }

    static func removeFileIfNeeded(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        try? FileManager.default.removeItem(at: url)
    }

    static func writeJSONObject(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(
            withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }

    static func makeNodeDetail(oid: String, attributes: [[String: Any]]) -> [String: Any] {
        [
            "appId": "app-1",
            "requestedOid": oid,
            "resolvedOid": oid,
            "attributeGroups": [
                [
                    "identifier": "group",
                    "sections": [
                        [
                            "identifier": "section",
                            "attributes": attributes
                        ]
                    ]
                ]
            ]
        ]
    }

    static func makeNodeAttribute(identifier: String, value: Any, attrTypeName: String = "number")
        -> [String: Any]
    {
        [
            "identifier": identifier,
            "displayTitle": identifier,
            "attrTypeName": attrTypeName,
            "value": value
        ]
    }

    static func makeBaselineDetailSemanticAttributes(_ attributes: [String: [String: Any]])
        -> [String: Any]
    {
        [
            "semanticAttributes": attributes
        ]
    }

    static func makeSemanticAttribute(name: String, path: String, value: Any) -> [String: Any] {
        [
            "semanticName": name,
            "semanticPath": path,
            "value": value,
            "valuePreview": String(describing: value)
        ]
    }
}
