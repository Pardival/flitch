import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// A key combination for the fallback shortcut (Carbon key code + Carbon modifier flags).
public struct KeyCombo: Codable, Hashable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// ⌃⌥Space: the default when Input Monitoring isn't granted.
    public static let controlOptionSpace = KeyCombo(
        keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey))

    /// "⌃⌥Space"
    public var displayString: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + Self.keyName(keyCode)
    }

    static func keyName(_ code: UInt32) -> String {
        switch Int(code) {
        case kVK_Space: "Space"
        case kVK_Return: "↩"
        case kVK_Tab: "⇥"
        case kVK_Escape: "⎋"
        default:
            if let n = Self.functionNumbers[Int(code)] {
                "F\(n)"
            } else if let c = Self.letters[Int(code)] {
                String(c)
            } else {
                "#\(code)"
            }
        }
    }

    private static let functionNumbers: [Int: Int] = [
        kVK_F1: 1, kVK_F2: 2, kVK_F3: 3, kVK_F4: 4, kVK_F5: 5, kVK_F6: 6, kVK_F7: 7, kVK_F8: 8, kVK_F9: 9,
        kVK_F10: 10, kVK_F11: 11, kVK_F12: 12, kVK_F13: 13, kVK_F14: 14, kVK_F15: 15, kVK_F16: 16,
        kVK_F17: 17, kVK_F18: 18, kVK_F19: 19, kVK_F20: 20,
    ]

    private static let letters: [Int: Character] = [
        kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E", kVK_ANSI_F: "F",
        kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
        kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R",
        kVK_ANSI_S: "S", kVK_ANSI_T: "T", kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
        kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z",
    ]
}

/// Pure logic for "hold right ⌥": press, release, and cancel when another key is typed
/// while ⌥ is held (⌥ is used to type characters like { } | on many layouts).
public struct RightOptionDetector: Sendable {
    public enum Action: Equatable, Sendable { case press, release, cancel }

    private(set) var holding = false
    private(set) var cancelled = false

    public init() {}

    /// Modifier change. `rightOptionDown` reflects the right ⌥ device flag after the change.
    public mutating func flagsChanged(keyCode: Int, rightOptionDown: Bool, otherModifiersDown: Bool) -> Action? {
        if !holding, keyCode == kVK_RightOption, rightOptionDown, !otherModifiersDown {
            holding = true
            cancelled = false
            return .press
        }
        if holding, !rightOptionDown {
            holding = false
            return cancelled ? nil : .release
        }
        if holding, otherModifiersDown, !cancelled {  // ⌘⌥…: a shortcut, not a talk
            cancelled = true
            return .cancel
        }
        return nil
    }

    /// Any non-modifier key went down.
    public mutating func keyDown() -> Action? {
        guard holding, !cancelled else { return nil }
        cancelled = true
        return .cancel
    }
}

/// Global push-to-talk shortcut.
///
/// - `.rightOption` (default) needs the **Input Monitoring** permission: a listen-only event tap that
///   reads modifier flags, and only notices *that* another key was pressed (never which one).
/// - `.combo` uses a Carbon hot key: press and release events, no permission needed.
@MainActor
public final class HotkeyMonitor {
    public enum Mode: Hashable, Sendable {
        case rightOption
        case combo(KeyCombo)
    }

    public var onPress: () -> Void = {}
    public var onRelease: () -> Void = {}
    /// Right ⌥ was used to type something: drop the recording silently.
    public var onCancel: () -> Void = {}

    public private(set) var activeMode: Mode?

    private var detector = RightOptionDetector()
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    public init() {}

    public static var inputMonitoringGranted: Bool { CGPreflightListenEventAccess() }

    /// Shows the system prompt (once); returns the current state.
    @discardableResult
    public static func requestInputMonitoring() -> Bool { CGRequestListenEventAccess() }

    /// Starts `preferred`; falls back to `fallback` if right ⌥ can't be monitored. Returns the active mode.
    @discardableResult
    public func start(preferred: Mode = .rightOption, fallback: KeyCombo = .controlOptionSpace) -> Mode? {
        stop()
        if case .rightOption = preferred, Self.inputMonitoringGranted, installTap() {
            activeMode = .rightOption
        } else {
            let combo: KeyCombo = if case .combo(let c) = preferred { c } else { fallback }
            activeMode = registerHotKey(combo) ? .combo(combo) : nil
        }
        return activeMode
    }

    public func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        }
        tap = nil
        tapSource = nil
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
        detector = RightOptionDetector()
        activeMode = nil
    }

    // MARK: - Right ⌥ (event tap)

    private func installTap() -> Bool {
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                eventsOfInterest: CGEventMask(mask), callback: hotkeyTapCallback, userInfo: refcon)
        else { return false }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        self.tapSource = source
        return true
    }

    fileprivate func handleTap(type: CGEventType, flags: CGEventFlags, keyCode: Int) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        case .flagsChanged:
            let rightOption = flags.rawValue & UInt64(NX_DEVICERALTKEYMASK) != 0
            let others: CGEventFlags = [.maskCommand, .maskControl, .maskShift]
            let action = detector.flagsChanged(
                keyCode: keyCode, rightOptionDown: rightOption, otherModifiersDown: !flags.intersection(others).isEmpty)
            perform(action)
        case .keyDown:
            perform(detector.keyDown())
        default:
            break
        }
    }

    private func perform(_ action: RightOptionDetector.Action?) {
        switch action {
        case .press: onPress()
        case .release: onRelease()
        case .cancel: onCancel()
        case nil: break
        }
    }

    // MARK: - Combo (Carbon hot key)

    private func registerHotKey(_ combo: KeyCombo) -> Bool {
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var handler: EventHandlerRef?
        guard
            InstallEventHandler(GetApplicationEventTarget(), hotkeyCarbonHandler, 2, &types, refcon, &handler) == noErr
        else { return false }
        var ref: EventHotKeyRef?
        let id = EventHotKeyID(signature: OSType(0x464C_5443), id: 1)  // "FLTC"
        guard
            RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr
        else {
            if let handler { RemoveEventHandler(handler) }
            return false
        }
        handlerRef = handler
        hotKeyRef = ref
        return true
    }

    fileprivate func handleHotKey(kind: UInt32) {
        if kind == UInt32(kEventHotKeyPressed) {
            onPress()
        } else if kind == UInt32(kEventHotKeyReleased) {
            onRelease()
        }
    }
}

private func hotkeyTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if let refcon {
        let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
        let flags = event.flags
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        MainActor.assumeIsolated { monitor.handleTap(type: type, flags: flags, keyCode: keyCode) }
    }
    return Unmanaged.passUnretained(event)
}

private func hotkeyCarbonHandler(
    _ next: EventHandlerCallRef?, _ event: EventRef?, _ refcon: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let refcon else { return OSStatus(eventNotHandledErr) }
    let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
    let kind = GetEventKind(event)
    MainActor.assumeIsolated { monitor.handleHotKey(kind: kind) }
    return noErr
}
