import AppKit

/// User-selectable hold-to-talk key. Modifiers and F13-F19 only: they work on
/// keyboards without Fn/Globe and never swallow a typing key.
enum HotkeyChoice: String, CaseIterable {
    case fn, rightOption, rightCommand, rightControl, f13, f14, f15, f16, f17, f18, f19

    var title: String {
        switch self {
        case .fn: return "Fn / Globe"
        case .rightOption: return "Right Option"
        case .rightCommand: return "Right Command"
        case .rightControl: return "Right Control"
        default: return rawValue.uppercased()
        }
    }

    /// Short name for inline copy ("Hold Fn and speak").
    var shortName: String { self == .fn ? "Fn" : title }

    var trigger: Hotkey.Trigger {
        // Device-dependent flag masks (NX_DEVICER*KEYMASK) tell right from left.
        switch self {
        case .fn: return .fnKey
        case .rightOption: return .modifier(keyCode: 61, deviceMask: 0x40)
        case .rightCommand: return .modifier(keyCode: 54, deviceMask: 0x10)
        case .rightControl: return .modifier(keyCode: 62, deviceMask: 0x2000)
        case .f13: return .keyCode(105)
        case .f14: return .keyCode(107)
        case .f15: return .keyCode(113)
        case .f16: return .keyCode(106)
        case .f17: return .keyCode(64)
        case .f18: return .keyCode(79)
        case .f19: return .keyCode(80)
        }
    }
}

/// Global hold-to-talk hotkey via CGEventTap.
/// Default: hold the Fn/Globe key (keycode 63) - press starts recording,
/// release stops. A modifier-only key never conflicts with app shortcuts.
final class Hotkey {
    enum Trigger {
        case fnKey                                      // flagsChanged, keycode 63
        case modifier(keyCode: Int64, deviceMask: UInt64) // one side of a modifier pair
        case keyCode(Int64)                             // plain key hold (e.g. F13)
    }

    var trigger: Trigger = .fnKey { didSet { isDown = false } }
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onEscape: (() -> Void)?
    /// Another key went down while a modifier trigger was held (Right Cmd+C):
    /// a shortcut, not dictation.
    var onChord: (() -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var healthTimer: Timer?
    private var isDown = false

    func start() -> Bool {
        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let hotkey = Unmanaged<Hotkey>.fromOpaque(refcon!).takeUnretainedValue()
            return hotkey.handle(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        self.tap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        // macOS silently disables taps under load; FluidVoice-style health check.
        healthTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            guard let self, let tap = self.tap else { return }
            if !CGEvent.tapIsEnabled(tap: tap) {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS disables taps that stall; re-enable.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let keycode = event.getIntegerValueField(.keyboardEventKeycode)

        if type == .keyDown, keycode == 53, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
            DispatchQueue.main.async { self.onEscape?() }
        }

        switch trigger {
        case .fnKey:
            guard type == .flagsChanged, keycode == 63 else { break }
            let fnActive = event.flags.contains(.maskSecondaryFn)
            if fnActive && !isDown {
                isDown = true
                DispatchQueue.main.async { self.onPress?() }
            } else if !fnActive && isDown {
                isDown = false
                DispatchQueue.main.async { self.onRelease?() }
            }
        case .modifier(let code, let mask):
            if type == .keyDown, isDown {
                DispatchQueue.main.async { self.onChord?() }
                break
            }
            guard type == .flagsChanged, keycode == code else { break }
            let active = event.flags.rawValue & mask != 0
            if active && !isDown {
                isDown = true
                DispatchQueue.main.async { self.onPress?() }
            } else if !active && isDown {
                isDown = false
                DispatchQueue.main.async { self.onRelease?() }
            }
        case .keyCode(let code):
            guard keycode == code, type == .keyDown || type == .keyUp else { break }
            if type == .keyDown && !isDown {
                isDown = true
                DispatchQueue.main.async { self.onPress?() }
            } else if type == .keyUp && isDown {
                isDown = false
                DispatchQueue.main.async { self.onRelease?() }
            }
            return nil // swallow the trigger key, autorepeats included
        }
        return Unmanaged.passUnretained(event)
    }

    static func hasAccessibilityPermission(prompt: Bool) -> Bool {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
