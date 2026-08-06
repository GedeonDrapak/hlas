import AppKit
import SwiftUI

private enum HlasMarkGeometry {
    private static let sourceBounds = CGRect(x: 401, y: 328, width: 450, height: 599)

    static func path(in rect: CGRect) -> CGPath {
        let scale = min(rect.width / sourceBounds.width, rect.height / sourceBounds.height)
        let fitted = CGSize(width: sourceBounds.width * scale, height: sourceBounds.height * scale)
        let origin = CGPoint(
            x: rect.midX - fitted.width / 2,
            y: rect.midY - fitted.height / 2
        )
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(
                x: origin.x + (x - sourceBounds.minX) * scale,
                y: origin.y + (y - sourceBounds.minY) * scale
            )
        }

        let path = CGMutablePath()
        path.move(to: point(478, 328))
        path.addCurve(to: point(401, 405), control1: point(435, 328), control2: point(401, 362))
        path.addLine(to: point(401, 850))
        path.addCurve(to: point(478, 927), control1: point(401, 893), control2: point(435, 927))
        path.addCurve(to: point(556, 850), control1: point(521, 927), control2: point(556, 893))
        path.addLine(to: point(556, 711))
        path.addCurve(to: point(616, 643), control1: point(556, 673), control2: point(580, 643))
        path.addLine(to: point(660, 643))
        path.addCurve(to: point(715, 699), control1: point(692, 643), control2: point(715, 667))
        path.addLine(to: point(715, 738))
        path.addCurve(to: point(783, 806), control1: point(715, 776), control2: point(745, 806))
        path.addCurve(to: point(851, 738), control1: point(821, 806), control2: point(851, 776))
        path.addLine(to: point(851, 523))
        path.addCurve(to: point(783, 455), control1: point(851, 485), control2: point(821, 455))
        path.addCurve(to: point(715, 523), control1: point(745, 455), control2: point(715, 485))
        path.addLine(to: point(715, 557))
        path.addCurve(to: point(661, 611), control1: point(715, 588), control2: point(692, 611))
        path.addLine(to: point(612, 611))
        path.addCurve(to: point(556, 554), control1: point(580, 611), control2: point(556, 586))
        path.addLine(to: point(556, 405))
        path.addCurve(to: point(478, 328), control1: point(556, 362), control2: point(521, 328))
        path.closeSubpath()
        return path
    }
}

struct HlasMark: Shape {
    func path(in rect: CGRect) -> Path {
        Path(HlasMarkGeometry.path(in: rect))
    }
}

enum HlasMarkImage {
    static let menuBar: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setFillColor(NSColor(calibratedWhite: 0.06, alpha: 1).cgColor)
            context.addPath(HlasMarkGeometry.path(in: rect.insetBy(dx: 2.5, dy: 1.5)))
            context.fillPath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Hlas"
        return image
    }()
}
