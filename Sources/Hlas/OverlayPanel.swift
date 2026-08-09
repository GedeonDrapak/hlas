import AppKit
import SwiftUI

enum OverlayState: Equatable {
    case hidden
    case recording
    case transcribing
    case cancelled
    case error(String)
}

@MainActor
final class OverlayModel: ObservableObject {
    @Published var state: OverlayState = .hidden
    @Published var levels: [Float] = Array(repeating: 0, count: 24)
    /// Set when recording from anything other than the built-in mic.
    @Published var sourceIcon: String?
    @Published var sourceName: String?

    func push(level: Float) {
        levels.removeFirst()
        levels.append(level)
    }
}

/// Floating pill at the bottom-center of the active screen.
/// Non-activating: it never steals focus from the app being dictated into.
@MainActor
final class OverlayPanel {
    private var panel: NSPanel?
    let model = OverlayModel()

    func show(_ state: OverlayState) {
        let previous = model.state
        model.state = state
        if panel == nil { makePanel() }
        // Re-assert on every show: the panel outlives Space switches, and the
        // window server only re-evaluates Space membership when the behavior
        // is set. Without this the pill can stay stuck on the Space where it
        // was first created.
        panel?.collectionBehavior = Self.collectionBehavior
        position()
        panel?.orderFrontRegardless()
        if state != previous { announce(state) }
    }

    func hide() {
        model.state = .hidden
        model.levels = Array(repeating: 0, count: model.levels.count)
        panel?.orderOut(nil)
    }

    /// `.canJoinAllSpaces` puts the pill on every Space, including the one the
    /// user is on right now. `.stationary` (used previously) belongs to the
    /// mutually exclusive Exposé group with `.managed`/`.transient` and marks
    /// the window as unmanaged by Space handling - it fought `canJoinAllSpaces`
    /// and pinned the pill to its creation Space. `.ignoresCycle` keeps it out
    /// of Cmd-` without touching Space behavior.
    private static let collectionBehavior: NSWindow.CollectionBehavior =
        [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

    /// The capsule is `pillHeight` tall and centred in the panel. The drop
    /// shadow (radius 18, y-offset 6) draws OUTSIDE the capsule but is clipped
    /// by the window, so the panel carries `shadowPad` of transparent margin on
    /// every side. Without it the shadow survives left and right - where the
    /// capsule is narrower than the panel - but is sheared off top and bottom.
    enum Metrics {
        static let pillHeight: CGFloat = 40
        static let shadowPad: CGFloat = 32
        static let width: CGFloat = 320
        static let height: CGFloat = pillHeight + shadowPad * 2
        /// Gap between the screen's visible bottom edge and the capsule.
        static let bottomGap: CGFloat = 24
        /// Panel origin sits below the capsule by the padding we added.
        static let originOffset: CGFloat = bottomGap - shadowPad
    }

    private func makePanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Metrics.width, height: Metrics.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        // NOT isFloatingPanel: it forces level .floating (3) and would clobber
        // the .statusBar (25) level set above, dropping the pill under other
        // floating windows.
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = Self.collectionBehavior
        panel.contentView = NSHostingView(rootView: OverlayView(model: model))
        self.panel = panel
    }

    private func position() {
        guard let panel, let screen = targetScreen() else { return }
        let f = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: f.midX - size.width / 2,
            y: f.minY + Metrics.originOffset
        ))
    }

    private func announce(_ state: OverlayState) {
        let message: String
        switch state {
        case .recording: message = "Recording started"
        case .transcribing: message = "Transcribing"
        case .cancelled: message = "Dictation cancelled"
        case .error(let error): message = "Dictation failed. \(error)"
        case .hidden: return
        }
        NSAccessibility.post(
            element: NSApplication.shared,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.medium.rawValue,
            ]
        )
    }

    private func targetScreen() -> NSScreen? {
        if let app = NSWorkspace.shared.frontmostApplication,
           let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
           let window = windows.first(where: {
               ($0[kCGWindowOwnerPID as String] as? pid_t) == app.processIdentifier
                   && ($0[kCGWindowLayer as String] as? Int) == 0
           }),
           let bounds = window[kCGWindowBounds as String] as? [String: Any],
           let x = (bounds["X"] as? NSNumber)?.doubleValue,
           let y = (bounds["Y"] as? NSNumber)?.doubleValue,
           let width = (bounds["Width"] as? NSNumber)?.doubleValue,
           let height = (bounds["Height"] as? NSNumber)?.doubleValue {
            let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
            let displayFrame = CGRect(
                x: CGFloat(x),
                y: primaryTop - CGFloat(y) - CGFloat(height),
                width: CGFloat(width),
                height: CGFloat(height)
            )
            if let best = NSScreen.screens.max(by: {
                $0.frame.intersection(displayFrame).area < $1.frame.intersection(displayFrame).area
            }), best.frame.intersects(displayFrame) {
                return best
            }
        }
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}

struct OverlayView: View {
    @ObservedObject var model: OverlayModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            switch model.state {
            case .recording:
                Circle().fill(DS.brand).frame(width: 7, height: 7)
                waveform(color: DS.brand)
                if let icon = model.sourceIcon {
                    HStack(spacing: 4) {
                        Image(systemName: icon).font(.system(size: 10))
                        if let name = model.sourceName {
                            Text(name).font(.system(size: 10)).lineLimit(1)
                        }
                    }
                    .foregroundStyle(DS.fg2)
                    .frame(maxWidth: 110)
                }
            case .transcribing:
                ProgressView().controlSize(.small).tint(DS.fg2)
                Text("TRANSCRIBING")
                    .font(DS.display(11))
                    .tracking(3)
                    .foregroundStyle(DS.fg2)
            case .cancelled:
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(DS.fg2)
                Text("CANCELLED")
                    .font(DS.label())
                    .tracking(3)
                    .foregroundStyle(DS.fg2)
            case .error(let message):
                Circle().fill(DS.destructive).frame(width: 7, height: 7)
                Text(message)
                    .font(DS.label())
                    .foregroundStyle(DS.fg2)
                    .lineLimit(1)
            case .hidden:
                EmptyView()
            }
        }
        .padding(.horizontal, 18)
        .frame(height: OverlayPanel.Metrics.pillHeight)
        .background(
            ZStack {
                VisualEffectBlur(material: .hudWindow)
                Color(hex: 0x0F0F0F).opacity(0.35) // dark tint over the blur
            }
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 18, y: 6)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: model.state)
    }

    private func waveform(color: Color) -> some View {
        HStack(spacing: 2.5) {
            ForEach(Array(model.levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(color)
                    .frame(width: 2.5, height: max(3, CGFloat(level) * 22))
            }
        }
        .frame(height: 24)
        .animation(reduceMotion ? nil : .linear(duration: 0.06), value: model.levels)
    }
}
