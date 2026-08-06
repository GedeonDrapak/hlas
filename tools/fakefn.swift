import CoreGraphics
import Foundation
let src = CGEventSource(stateID: .hidSystemState)
let down = CGEvent(keyboardEventSource: src, virtualKey: 63, keyDown: true)!
down.type = .flagsChanged
down.flags = .maskSecondaryFn
down.post(tap: .cghidEventTap)
Thread.sleep(forTimeInterval: 1.5)
let up = CGEvent(keyboardEventSource: src, virtualKey: 63, keyDown: false)!
up.type = .flagsChanged
up.flags = []
up.post(tap: .cghidEventTap)
print("posted fn down+up")
