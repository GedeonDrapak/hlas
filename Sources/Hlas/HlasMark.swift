import AppKit
import SwiftUI

struct HlasMark: Shape {
    func path(in rect: CGRect) -> Path {
        let unit = min(rect.width, rect.height)
        let x = rect.midX - unit / 2
        let y = rect.midY - unit / 2
        var path = Path()
        path.addRoundedRect(
            in: CGRect(x: x + unit * 0.20, y: y + unit * 0.12, width: unit * 0.25, height: unit * 0.76),
            cornerSize: CGSize(width: unit * 0.125, height: unit * 0.125)
        )
        path.addRoundedRect(
            in: CGRect(x: x + unit * 0.58, y: y + unit * 0.24, width: unit * 0.22, height: unit * 0.52),
            cornerSize: CGSize(width: unit * 0.11, height: unit * 0.11)
        )
        path.addRect(CGRect(x: x + unit * 0.38, y: y + unit * 0.44, width: unit * 0.27, height: unit * 0.14))
        return path
    }
}

enum HlasMarkImage {
    static let menuBar: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            NSColor(calibratedWhite: 0.06, alpha: 1).setFill()
            let path = NSBezierPath()
            path.appendRoundedRect(
                NSRect(x: rect.minX + 3.5, y: rect.minY + 2, width: 4.5, height: 14),
                xRadius: 2.25,
                yRadius: 2.25
            )
            path.appendRoundedRect(
                NSRect(x: rect.minX + 10.5, y: rect.minY + 4, width: 4, height: 10),
                xRadius: 2,
                yRadius: 2
            )
            path.appendRect(NSRect(x: rect.minX + 7, y: rect.minY + 8, width: 5, height: 2.5))
            path.fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Hlas"
        return image
    }()
}
