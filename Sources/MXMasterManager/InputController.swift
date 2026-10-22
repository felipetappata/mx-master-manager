import AppKit
import ApplicationServices
import Carbon
import CoreGraphics
import MXMasterCore

/// Main-runloop owner of output events. HID++ supplies diverted input directly;
/// no global mouse/keyboard event tap is installed.
final class InputController {
    var zoomSensitivity: Double = 1
    var onStatus: ((String) -> Void)?
    var backAction: ButtonAction = .back
    var forwardAction: ButtonAction = .forward
    var tapAction: ButtonAction = .smartZoom

    private var gesture = GestureState()
    private var gestureAnchor: CGPoint?
    private var nativeZoomActive = false

    static var accessibilityGranted: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    func handle(_ input: MouseInput) {
        precondition(Thread.isMainThread, "InputController must run on the main thread")
        switch input {
        case .gesturePressed:
            if !gesture.isPressed { gestureAnchor = CGEvent(source: nil)?.location }
            gesture.press(at: ProcessInfo.processInfo.systemUptime)
        case .gestureReleased:
            emit(gesture.release(at: ProcessInfo.processInfo.systemUptime))
            gestureAnchor = nil
        case .gestureCancelled:
            stop()
        case let .gestureMoved(dx, dy):
            emit(gesture.move(dx: dx, dy: dy, sensitivity: zoomSensitivity))
        case .backPressed:
            perform(backAction)
        case .forwardPressed:
            perform(forwardAction)
        }
    }

    /// Call before releasing HID diversion, on disconnect, and before quitting.
    func stop() {
        precondition(Thread.isMainThread, "InputController must run on the main thread")
        emit(gesture.cancel())
        gestureAnchor = nil
    }

    private func emit(_ output: [GestureState.Output]) {
        for action in output {
            switch action {
            case .smartZoom:
                perform(tapAction)
            case .beginZoom:
                guard canPost else { continue }
                guard let event = NativeGesture.make(.magnify(0, phase: .began), location: gestureAnchor) else {
                    onStatus?("Pinch zoom is unavailable on this macOS version. No keyboard substitute was sent.")
                    continue
                }
                event.post(tap: .cghidEventTap)
                nativeZoomActive = true
                // A zero changed frame lets AppKit establish the magnification
                // gesture before its first displacement, avoiding initial lag.
                NativeGesture.make(.magnify(0, phase: .changed), location: gestureAnchor)?.post(tap: .cghidEventTap)
            case let .magnify(amount):
                guard nativeZoomActive else { continue }
                guard Self.accessibilityGranted else {
                    finishZoom(cancelled: true)
                    onStatus?("Enable Accessibility for MX Master Manager to send gestures and shortcuts.")
                    continue
                }
                guard let event = NativeGesture.make(.magnify(amount, phase: .changed), location: gestureAnchor) else {
                    onStatus?("macOS rejected a pinch update.")
                    finishZoom(cancelled: true)
                    continue
                }
                event.post(tap: .cghidEventTap)
            case let .endZoom(cancelled):
                finishZoom(cancelled: cancelled)
            }
        }
    }

    private func finishZoom(cancelled: Bool) {
        guard nativeZoomActive else { return }
        if let event = NativeGesture.make(.magnify(0, phase: cancelled ? .cancelled : .ended), location: gestureAnchor) {
            event.post(tap: .cghidEventTap)
        } else { onStatus?("macOS rejected the end of a pinch gesture.") }
        nativeZoomActive = false
    }

    private var canPost: Bool {
        guard Self.accessibilityGranted else {
            onStatus?("Enable Accessibility for MX Master Manager to send gestures and shortcuts.")
            return false
        }
        return true
    }

    private func perform(_ action: ButtonAction) {
        switch action {
        case .none: break
        case .back: postBracket("[", fallback: 33)
        case .forward: postBracket("]", fallback: 30)
        case .smartZoom:
            guard canPost else { return }
            guard let event = NativeGesture.make(.smartZoom, location: gestureAnchor) else {
                onStatus?("Smart Zoom is unavailable on this macOS version.")
                return
            }
            event.post(tap: .cghidEventTap)
        }
    }

    private func postBracket(_ character: Character, fallback: CGKeyCode) {
        guard canPost else { return }
        // Carbon's Command layer also handles layouts such as Dvorak-QWERTY Cmd.
        let key = Self.keyCode(for: character) ?? fallback
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false) else {
            onStatus?("macOS could not create the navigation shortcut.")
            return
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    /// Only an unmodified Command-layer match is safe: adding Option/Shift to
    /// reach a bracket can invoke a different application shortcut. When a layout
    /// has none, preserve the familiar physical Command-[ / Command-] positions.
    private static func keyCode(for character: Character) -> CGKeyCode? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let rawData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(rawData).takeUnretainedValue()
        guard CFDataGetLength(data) > 0, let bytes = CFDataGetBytePtr(data) else { return nil }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        let typingKeys = Array(UInt16(0)...UInt16(0x32)) + [UInt16(0x5d), UInt16(0x5e)]
        for key in typingKeys {
            var deadState: UInt32 = 0
            var count = 0
            var text = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(layout, key, UInt16(kUCKeyActionDown), UInt32(cmdKey >> 8),
                                        UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysMask),
                                        &deadState, text.count, &count, &text)
            if status == noErr && count == 1 && String(utf16CodeUnits: text, count: count) == String(character) {
                return key
            }
        }
        return nil
    }
}

/// These fields are undocumented CGEvent SPI. Keep them together and verify that
/// AppKit decodes every event before posting. Primary references, inspected 2026-10-22:
/// https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/eventtap/TouchEvents.h
/// https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/eventtap/TouchEvents.c
/// Subtype 0x16 is genuine Smart Magnify (two-finger double tap), not keyboard zoom.
enum NativeGesture {
    enum Kind {
        case smartZoom
        case magnify(Double, phase: NSEvent.Phase)
    }

    static func make(_ kind: Kind, location: CGPoint?) -> CGEvent? {
        guard let event = CGEvent(source: nil),
              let type = CGEventType(rawValue: 29),
              let subtypeField = CGEventField(rawValue: 110),
              let phaseField = CGEventField(rawValue: 132),
              let magnificationField = CGEventField(rawValue: 113) else { return nil }
        event.type = type
        event.flags = CGEventFlags(rawValue: 0x100)
        if let location { event.location = location }
        event.setIntegerValueField(.eventSourceUserData, value: 0x4d584d4d)
        switch kind {
        case .smartZoom:
            event.setIntegerValueField(subtypeField, value: 0x16)
            event.setIntegerValueField(phaseField, value: 0)
            guard NSEvent(cgEvent: event)?.type == .smartMagnify else { return nil }
        case let .magnify(amount, phase):
            // Field 132 takes IOHIDEventPhaseBits, whose Changed/Ended/Cancelled
            // values differ from NSEvent.Phase because AppKit adds Stationary.
            // Passing AppKit's raw Changed (4) sends a HID Ended event instead.
            let hidPhase: Int64
            switch phase {
            case .began: hidPhase = 1
            case .changed: hidPhase = 2
            case .ended: hidPhase = 4
            case .cancelled: hidPhase = 8
            default: return nil
            }
            event.setIntegerValueField(subtypeField, value: 8)
            event.setIntegerValueField(phaseField, value: hidPhase)
            event.setDoubleValueField(magnificationField, value: amount)
            guard let native = NSEvent(cgEvent: event), native.type == .magnify,
                  native.phase == phase, abs(native.magnification - amount) < 0.00001 else { return nil }
        }
        return event
    }
}
