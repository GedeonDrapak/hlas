import AppKit
import SwiftUI

@MainActor final class ResultWindow {
    static let shared = ResultWindow()
    private var window: NSWindow?
    func show(text: String, original: String, message: String) {
        let window = self.window ?? NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 390),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Your text"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 420, height: 320)
        let host = NSHostingView(rootView: ResultView(text: text, original: original, message: message))
        host.sizingOptions = []
        window.contentView = host
        if self.window == nil { window.setContentSize(NSSize(width: 520, height: 390)) }
        if self.window == nil { window.center() }
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct ResultView: View {
    let text: String
    let original: String
    let message: String
    @State private var showOriginal = false
    @State private var copied = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(message).font(DS.text(13)).foregroundStyle(DS.fg2).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                Text(showOriginal ? original : text).font(DS.text(14)).foregroundStyle(DS.fg)
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                if original != text { Toggle("Original transcript", isOn: $showOriginal).toggleStyle(.switch) }
                Spacer()
                Button(copied ? "Copied" : "Copy text") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(showOriginal ? original : text, forType: .string)
                    copied = true
                }.buttonStyle(.borderedProminent).tint(DS.brand)
            }
        }.padding(24).background(DS.bg).preferredColorScheme(.dark)
    }
}
