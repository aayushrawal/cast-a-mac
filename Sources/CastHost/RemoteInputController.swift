#if os(macOS)
import ApplicationServices
import CastCore
import Foundation

final class RemoteInputController: @unchecked Sendable {
    private let displayBounds: CGRect

    init(displayID: CGDirectDisplayID) {
        displayBounds = CGDisplayBounds(displayID)
    }

    static func requestAccessibilityPermission() {
        let options = [
            "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    func handle(_ message: ControlMessage) {
        guard case let .input(envelope) = message else {
            return
        }

        switch envelope.event {
        case let .pointerMoved(position):
            postMouse(type: .mouseMoved, position: position, button: .left)
        case let .pointerButton(button, isPressed, position):
            let cgButton = button.cgButton
            let eventType = button.eventType(isPressed: isPressed)
            postMouse(type: eventType, position: position, button: cgButton)
        case let .scroll(deltaX, deltaY):
            let event = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .pixel,
                wheelCount: 2,
                wheel1: Int32(deltaY),
                wheel2: Int32(deltaX),
                wheel3: 0
            )
            event?.post(tap: .cghidEventTap)
        case let .key(keyCode, isPressed, modifiers):
            let event = CGEvent(
                keyboardEventSource: nil,
                virtualKey: CGKeyCode(keyCode),
                keyDown: isPressed
            )
            event?.flags = modifiers.cgFlags
            event?.post(tap: .cghidEventTap)
        case let .text(text):
            var units = Array(text.utf16)
            for isKeyDown in [true, false] {
                guard let event = CGEvent(
                    keyboardEventSource: nil,
                    virtualKey: 0,
                    keyDown: isKeyDown
                ) else { continue }
                event.keyboardSetUnicodeString(
                    stringLength: units.count,
                    unicodeString: &units
                )
                event.post(tap: .cghidEventTap)
            }
        }
    }

    private func postMouse(
        type: CGEventType,
        position: CastPoint,
        button: CGMouseButton
    ) {
        let point = CGPoint(
            x: displayBounds.minX + min(max(position.x, 0), 1) * displayBounds.width,
            y: displayBounds.minY + min(max(position.y, 0), 1) * displayBounds.height
        )
        CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: button
        )?.post(tap: .cghidEventTap)
    }
}

private extension PointerButton {
    var cgButton: CGMouseButton {
        switch self {
        case .primary: .left
        case .secondary: .right
        case .middle: .center
        }
    }

    func eventType(isPressed: Bool) -> CGEventType {
        switch (self, isPressed) {
        case (.primary, true): .leftMouseDown
        case (.primary, false): .leftMouseUp
        case (.secondary, true): .rightMouseDown
        case (.secondary, false): .rightMouseUp
        case (.middle, true): .otherMouseDown
        case (.middle, false): .otherMouseUp
        }
    }
}

private extension KeyModifiers {
    var cgFlags: CGEventFlags {
        var flags: CGEventFlags = []
        if contains(.shift) { flags.insert(.maskShift) }
        if contains(.control) { flags.insert(.maskControl) }
        if contains(.option) { flags.insert(.maskAlternate) }
        if contains(.command) { flags.insert(.maskCommand) }
        if contains(.capsLock) { flags.insert(.maskAlphaShift) }
        return flags
    }
}
#endif
