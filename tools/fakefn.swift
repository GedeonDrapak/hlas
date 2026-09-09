import CoreGraphics
import Foundation
let src = CGEventSource(stateID: .hidSystemState)
let down = CGEvent(keyboardEventSource: src, virtualKey: 63, keyDown: true)!
down.type = .flagsChanged
down.flags = .maskSecondaryFn
down.post(tap: .cghidEventTap)
let holdSeconds = min(30, max(0.1, Double(CommandLine.arguments.dropFirst().first ?? "1.5") ?? 1.5))
Thread.sleep(forTimeInterval: holdSeconds)
let up = CGEvent(keyboardEventSource: src, virtualKey: 63, keyDown: false)!
up.type = .flagsChanged
up.flags = []
up.post(tap: .cghidEventTap)
// macOS can coalesce a synthetic modifier release during audio route changes.
Thread.sleep(forTimeInterval: 0.1)
up.post(tap: .cghidEventTap)
print("posted fn down+up")
