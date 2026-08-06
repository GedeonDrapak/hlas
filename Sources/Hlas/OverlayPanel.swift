import AppKit
import SwiftUI

enum OverlayState: Equatable {
    case hidden
    case recording
    case transcribing
    case error(String)
}

@MainActor
final class OverlayModel: ObservableObject {
    @Published var state: OverlayState = .hidden
    @Published var levels: [Float] = Array(repeating: 0, count: 24)

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
        model.state = state
        if panel == nil { makePanel() }
        position()
        panel?.orderFrontRegardless()
    }

    func hide() {
        model.state = .hidden
        model.levels = Array(repeating: 0, count: model.levels.count)
        panel?.orderOut(nil)
    }

    private func makePanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: OverlayView(model: model))
        self.panel = panel
    }

    private func position() {
        guard let panel, let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(
            x: f.midX - size.width / 2,
            y: f.minY + 24
        ))
    }
}

struct OverlayView: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        HStack(spacing: 10) {
            switch model.state {
            case .recording:
                Circle().fill(DS.brand).frame(width: 7, height: 7)
                waveform(color: DS.brand)
            case .transcribing:
                ProgressView().controlSize(.small).tint(DS.fg2)
                Text("TRANSCRIBING")
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
        .frame(height: 40)
        .background(
            Capsule()
                .fill(Color(hex: 0x0F0F0F).opacity(0.94))
                .overlay(Capsule().strokeBorder(DS.border, lineWidth: 1))
                .shadow(color: .black.opacity(0.35), radius: 18, y: 6)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.18), value: model.state)
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
        .animation(.linear(duration: 0.06), value: model.levels)
    }
}
