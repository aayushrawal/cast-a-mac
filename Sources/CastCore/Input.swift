import Foundation

public struct KeyModifiers: OptionSet, Codable, Equatable, Sendable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let shift = KeyModifiers(rawValue: 1 << 0)
    public static let control = KeyModifiers(rawValue: 1 << 1)
    public static let option = KeyModifiers(rawValue: 1 << 2)
    public static let command = KeyModifiers(rawValue: 1 << 3)
    public static let capsLock = KeyModifiers(rawValue: 1 << 4)
}

public enum PointerButton: String, Codable, Equatable, Sendable {
    case primary
    case secondary
    case middle
}

public enum InputEvent: Codable, Equatable, Sendable {
    case pointerMoved(position: CastPoint)
    case pointerButton(button: PointerButton, isPressed: Bool, position: CastPoint)
    case scroll(deltaX: Double, deltaY: Double)
    case key(keyCode: UInt16, isPressed: Bool, modifiers: KeyModifiers)
    case text(String)
}

public struct InputEnvelope: Codable, Equatable, Sendable {
    public let sequenceNumber: UInt64
    public let timestamp: TimeInterval
    public let event: InputEvent

    public init(
        sequenceNumber: UInt64,
        timestamp: TimeInterval,
        event: InputEvent
    ) {
        self.sequenceNumber = sequenceNumber
        self.timestamp = timestamp
        self.event = event
    }
}
