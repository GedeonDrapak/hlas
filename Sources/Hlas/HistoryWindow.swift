import AppKit
import SwiftUI

@MainActor
final class HistoryWindow {
    static let shared = HistoryWindow()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 520),
                styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.backgroundColor = .clear
            window.minSize = NSSize(width: 420, height: 360)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: HistoryView())
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct HistoryView: View {
    @ObservedObject private var history = History.shared
    @State private var search = ""
    @State private var confirmClear = false

    private var entries: [History.Entry] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return history.entries }
        return history.entries.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("HISTORY")
                        .font(DS.text(18, weight: .bold))
                        .tracking(5)
                        .foregroundStyle(DS.fg)
                    Text("Stored only on this Mac")
                        .font(DS.text(11))
                        .foregroundStyle(DS.fg3)
                }
                Spacer()
                if !history.entries.isEmpty {
                    Button("Clear") { confirmClear = true }
                        .buttonStyle(.borderless)
                        .foregroundStyle(DS.destructive)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 16)

            TextField("Search transcripts", text: $search)
                .textFieldStyle(.plain)
                .font(DS.text(12))
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(RoundedRectangle(cornerRadius: DS.radiusSm).fill(DS.surfaceHover))
                .padding(.horizontal, 24)
                .padding(.bottom, 14)

            if entries.isEmpty {
                ContentUnavailableView(
                    search.isEmpty ? "No dictations yet" : "No matching dictations",
                    systemImage: search.isEmpty ? "waveform" : "magnifyingglass"
                )
                .foregroundStyle(DS.fg2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(entries) { entry in
                            historyRow(entry)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
        }
        .frame(minWidth: 420, minHeight: 360)
        .background(
            ZStack {
                VisualEffectBlur(material: .underWindowBackground)
                DS.bg.opacity(0.5)
            }
            .ignoresSafeArea()
        )
        .preferredColorScheme(.dark)
        .alert("Clear history?", isPresented: $confirmClear) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) { history.clear() }
        } message: {
            Text("This removes all locally stored transcripts.")
        }
    }

    private func historyRow(_ entry: History.Entry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.text)
                    .font(DS.text(13))
                    .foregroundStyle(DS.fg)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    .font(DS.text(10))
                    .foregroundStyle(DS.fg3)
            }
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.text, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(DS.fg2)
            .help("Copy transcript")
            .accessibilityLabel("Copy transcript")
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: DS.radiusSm).fill(DS.surface))
    }
}
