//
//  InteractionModels.swift
//  astrolabe
//
//  Created by 轩辕十四 on 2026/8/17.
//

import Foundation

package enum InteractionActionKind: String, Equatable, Hashable {
    case tap
    case longPress
    case inputText
    case swipe
    case pressKey
}

package struct InteractionPoint: Equatable {
    /// Horizontal position in the logical viewport coordinate space.
    package let x: Double

    /// Vertical position in the logical viewport coordinate space.
    package let y: Double

    package init(x: Double, y: Double) throws {
        guard x.isFinite, y.isFinite, x >= 0, y >= 0 else {
            throw InteractionError.invalidInput("Interaction point must be finite and nonnegative")
        }
        self.x = x
        self.y = y
    }
}

package struct InteractionViewport: Equatable {
    /// Logical viewport width.
    package let width: Double

    /// Logical viewport height.
    package let height: Double

    package init(width: Double, height: Double) throws {
        guard width.isFinite, height.isFinite, width > 0, height > 0 else {
            throw InteractionError.invalidInput("Interaction viewport dimensions must be finite and positive")
        }
        self.width = width
        self.height = height
    }

    func contains(_ point: InteractionPoint) -> Bool {
        point.x <= width && point.y <= height
    }
}

package enum InteractionOrientation: Equatable {
    case portrait
    case landscape
}

package enum InteractionDeviceKind: Equatable, Hashable {
    case virtual
    case physical
}

package enum InteractionLocator: Equatable {
    case stableIdentifier(String)
    case accessibilityLabel(String)
    case alias(String)
    case point(InteractionPoint)
}

package enum InteractionAction: Equatable {
    case tap
    case longPress(duration: TimeInterval)
    case inputText(String)
    case swipe(to: InteractionPoint, duration: TimeInterval)
    case pressKey(String)

    package var kind: InteractionActionKind {
        switch self {
        case .tap:
            .tap
        case .longPress:
            .longPress
        case .inputText:
            .inputText
        case .swipe:
            .swipe
        case .pressKey:
            .pressKey
        }
    }

    package init(validating action: InteractionAction) throws {
        try action.validate()
        self = action
    }

    func validate() throws {
        switch self {
        case .longPress(let duration), .swipe(_, let duration):
            guard duration.isFinite, duration > 0 else {
                throw InteractionError.invalidInput("Interaction duration must be finite and positive")
            }
        case .pressKey(let key):
            guard !key.isEmpty else {
                throw InteractionError.invalidInput("Interaction key must not be empty")
            }
        case .tap, .inputText:
            break
        }
    }
}

package struct InteractionTarget: Equatable {
    /// Runtime app identifier resolved by the platform resolver.
    package let appId: String

    /// Physical or virtual device identifier where the interaction occurs.
    package let deviceIdentifier: String

    /// Device category used for Provider routing.
    package let deviceKind: InteractionDeviceKind

    /// Foreground app process identifier observed before interaction.
    package let processIdentifier: String

    /// Unix timestamp when the target state was observed.
    package let observedAtUnixTime: TimeInterval

    /// Orientation observed with the target state.
    package let orientation: InteractionOrientation

    /// Logical viewport observed with the target state.
    package let viewport: InteractionViewport

    /// Semantic or coordinate locator for the interaction target.
    package let locator: InteractionLocator

    package init(
        appId: String,
        deviceIdentifier: String,
        deviceKind: InteractionDeviceKind,
        processIdentifier: String,
        observedAtUnixTime: TimeInterval,
        orientation: InteractionOrientation,
        viewport: InteractionViewport,
        locator: InteractionLocator
    ) throws {
        guard !appId.isEmpty, !deviceIdentifier.isEmpty, !processIdentifier.isEmpty else {
            throw InteractionError.invalidInput("Interaction identifiers must not be empty")
        }
        guard observedAtUnixTime.isFinite, observedAtUnixTime >= 0 else {
            throw InteractionError.invalidInput("Interaction observation time must be finite and nonnegative")
        }
        if case .stableIdentifier(let identifier) = locator, identifier.isEmpty {
            throw InteractionError.invalidInput("Interaction stable identifier must not be empty")
        }
        if case .accessibilityLabel(let label) = locator, label.isEmpty {
            throw InteractionError.invalidInput("Interaction accessibility label must not be empty")
        }
        if case .alias(let alias) = locator, alias.isEmpty {
            throw InteractionError.invalidInput("Interaction alias must not be empty")
        }
        if case .point(let point) = locator, !viewport.contains(point) {
            throw InteractionError.invalidInput("Interaction point must be inside the viewport")
        }
        self.appId = appId
        self.deviceIdentifier = deviceIdentifier
        self.deviceKind = deviceKind
        self.processIdentifier = processIdentifier
        self.observedAtUnixTime = observedAtUnixTime
        self.orientation = orientation
        self.viewport = viewport
        self.locator = locator
    }
}

package struct InteractionRequest: Equatable {
    /// Requested user interaction.
    package let action: InteractionAction

    /// Current target context for the interaction.
    package let target: InteractionTarget

    package init(action: InteractionAction, target: InteractionTarget) throws {
        try action.validate()
        if case .swipe(let destination, _) = action, !target.viewport.contains(destination) {
            throw InteractionError.invalidInput("Interaction swipe destination must be inside the viewport")
        }
        self.action = action
        self.target = target
    }
}

package enum InteractionExecutionStatus: Equatable {
    case sent
    case confirmed
    case uncertain
}

package struct InteractionResult: Equatable {
    /// Exact request accepted by the selected Provider.
    package let request: InteractionRequest

    /// Execution certainty reported by the selected Provider.
    package let status: InteractionExecutionStatus

    package init(request: InteractionRequest, status: InteractionExecutionStatus) {
        self.request = request
        self.status = status
    }
}

package enum InteractionError: Error, Equatable {
    case invalidInput(String)
    case duplicateProviderIdentifier(String)
    case providerUnavailable(platform: RuntimeUIPlatform, deviceKind: InteractionDeviceKind)
    case unsupportedAction(InteractionActionKind)
    case ambiguousProviders([String])
    case staleTarget
    case foregroundAppChanged
    case coordinateContextChanged
    case executionFailed(String)
}
