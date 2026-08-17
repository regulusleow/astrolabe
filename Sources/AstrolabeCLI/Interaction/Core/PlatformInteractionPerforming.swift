//
//  PlatformInteractionPerforming.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/8/17.
//

package struct InteractionProviderDescriptor: Equatable {
    /// Stable identifier for this interaction Provider.
    package let identifier: String

    /// Runtime platform supported by this Provider.
    package let platform: RuntimeUIPlatform

    /// Device categories supported by this Provider.
    package let supportedDeviceKinds: Set<InteractionDeviceKind>

    /// Action kinds supported by this Provider.
    package let supportedActionKinds: Set<InteractionActionKind>

    package init(
        identifier: String,
        platform: RuntimeUIPlatform,
        supportedDeviceKinds: Set<InteractionDeviceKind>,
        supportedActionKinds: Set<InteractionActionKind>
    ) throws {
        guard !identifier.isEmpty else {
            throw InteractionError.invalidInput("Interaction Provider identifier must not be empty")
        }
        guard !supportedDeviceKinds.isEmpty else {
            throw InteractionError.invalidInput("Interaction Provider device kinds must not be empty")
        }
        guard !supportedActionKinds.isEmpty else {
            throw InteractionError.invalidInput("Interaction Provider action kinds must not be empty")
        }
        self.identifier = identifier
        self.platform = platform
        self.supportedDeviceKinds = supportedDeviceKinds
        self.supportedActionKinds = supportedActionKinds
    }
}

package protocol PlatformInteractionPerforming {
    var descriptor: InteractionProviderDescriptor { get }
    func canHandle(target: InteractionTarget) -> Bool
    func perform(_ request: InteractionRequest) throws -> InteractionResult
}
