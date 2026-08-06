import AppKit

/// Global hold-to-talk hotkey via CGEventTap.
/// Default: hold the Fn/Globe key (keycode 63) - press starts recording,
/// release stops. A modifier-only key never conflicts with app shortcuts.
final class Hotkey {
    enum Trigger {
        case fnKey                // flagsChanged, keycode 63
        case keyCode(Int64)       // plain key hold (e.g. F13)
    }

    var trigger: Trigger = .fnKey
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onEscape: (() -> Void)?

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
        case .keyCode(let code):
            guard keycode == code else { break }
            if type == .keyDown && !isDown {
                isDown = true
                DispatchQueue.main.async { self.onPress?() }
                return nil // swallow the trigger key
            } else if type == .keyUp && isDown {
                isDown = false
                DispatchQueue.main.async { self.onRelease?() }
                return nil
            }
        }
        return Unmanaged.passUnretained(event)
    }

    static func hasAccessibilityPermission(prompt: Bool) -> Bool {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
