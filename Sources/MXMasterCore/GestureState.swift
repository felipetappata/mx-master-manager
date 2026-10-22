import Foundation

/// Decides whether the thumb button was tapped or used for a zoom drag.
/// Raw motion is relative device motion; negative Y means toward the screen.
public struct GestureState {
    public enum Output: Equatable, Sendable {
        case smartZoom
        case beginZoom
        case magnify(Double)
        case endZoom(cancelled: Bool)
    }

    public private(set) var isPressed = false
    public private(set) var isZooming = false
    public let movementThreshold: Double
    public let maximumTapDuration: TimeInterval

    private var pressedAt: TimeInterval = 0
    private var totalX = 0.0
    private var totalY = 0.0
    private var dragged = false

    public init(movementThreshold: Double = 12, maximumTapDuration: TimeInterval = 0.45) {
        self.movementThreshold = movementThreshold.isFinite ? max(1, movementThreshold) : 12
        self.maximumTapDuration = maximumTapDuration.isFinite ? max(0, maximumTapDuration) : 0.45
    }

    public mutating func press(at time: TimeInterval) {
        // Duplicate held reports must not restart a drag or manufacture a tap.
        guard !isPressed else { return }
        isPressed = true
        pressedAt = time
        totalX = 0
        totalY = 0
        dragged = false
        isZooming = false
    }

    public mutating func move(dx: Int, dy: Int, sensitivity: Double = 1) -> [Output] {
        guard isPressed else { return [] }
        totalX += Double(dx)
        totalY += Double(dy)
        if hypot(totalX, totalY) >= movementThreshold { dragged = true }

        let multiplier = sensitivity.isFinite ? min(10, max(0.05, sensitivity)) : 1
        let amount: Double
        var output: [Output] = []
        if isZooming {
            // Use each fresh delta, so reversing direction takes effect immediately.
            amount = -Double(dy) * 0.0015 * multiplier
        } else {
            guard abs(totalY) >= movementThreshold else { return [] }
            isZooming = true
            dragged = true
            output.append(.beginZoom)
            // Consume the deadzone once; crossing it must not cause a zoom jump.
            let excess = totalY - (totalY < 0 ? -movementThreshold : movementThreshold)
            amount = -excess * 0.0015 * multiplier
        }
        if amount != 0 {
            // A malformed or delayed report cannot produce an enormous single jump.
            output.append(.magnify(min(0.25, max(-0.25, amount))))
        }
        return output
    }

    public mutating func release(at time: TimeInterval) -> [Output] {
        guard isPressed else { return [] }
        let duration = time - pressedAt
        let output: [Output]
        if isZooming {
            output = [.endZoom(cancelled: false)]
        } else if !dragged && duration >= 0 && duration <= maximumTapDuration {
            output = [.smartZoom]
        } else {
            output = []
        }
        reset()
        return output
    }

    /// Teardown/disconnection is never interpreted as a thumb-button tap.
    public mutating func cancel() -> [Output] {
        let output: [Output] = isZooming ? [.endZoom(cancelled: true)] : []
        reset()
        return output
    }

    private mutating func reset() {
        isPressed = false
        isZooming = false
        totalX = 0
        totalY = 0
        dragged = false
    }
}
