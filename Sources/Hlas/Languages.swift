import SwiftUI

struct Lang: Identifiable, Equatable {
    let code: String
    let name: String
    var id: String { code }
}

/// Whisper-supported languages, native names. "auto" is a pseudo-language.
enum Languages {
    static let auto = Lang(code: "auto", name: "Auto-detect")

    static let all: [Lang] = [
        Lang(code: "cs", name: "Čeština"),
        Lang(code: "sk", name: "Slovenčina"),
        Lang(code: "en", name: "English"),
        Lang(code: "de", name: "Deutsch"),
        Lang(code: "es", name: "Español"),
        Lang(code: "fr", name: "Français"),
        Lang(code: "it", name: "Italiano"),
        Lang(code: "pl", name: "Polski"),
        Lang(code: "pt", name: "Português"),
        Lang(code: "ru", name: "Русский"),
        Lang(code: "uk", name: "Українська"),
        Lang(code: "nl", name: "Nederlands"),
        Lang(code: "sv", name: "Svenska"),
        Lang(code: "no", name: "Norsk"),
        Lang(code: "da", name: "Dansk"),
        Lang(code: "fi", name: "Suomi"),
        Lang(code: "hu", name: "Magyar"),
        Lang(code: "ro", name: "Română"),
        Lang(code: "bg", name: "Български"),
        Lang(code: "hr", name: "Hrvatski"),
        Lang(code: "sr", name: "Srpski"),
        Lang(code: "sl", name: "Slovenščina"),
        Lang(code: "el", name: "Ελληνικά"),
        Lang(code: "tr", name: "Türkçe"),
        Lang(code: "ar", name: "العربية"),
        Lang(code: "he", name: "עברית"),
        Lang(code: "hi", name: "हिन्दी"),
        Lang(code: "zh", name: "中文 (Mandarin)"),
        Lang(code: "yue", name: "粵語 (Cantonese)"),
        Lang(code: "ja", name: "日本語"),
        Lang(code: "ko", name: "한국어"),
        Lang(code: "vi", name: "Tiếng Việt"),
        Lang(code: "th", name: "ไทย"),
        Lang(code: "id", name: "Bahasa Indonesia"),
        Lang(code: "ms", name: "Bahasa Melayu"),
        Lang(code: "ca", name: "Català"),
        Lang(code: "gl", name: "Galego"),
        Lang(code: "eu", name: "Euskara"),
        Lang(code: "et", name: "Eesti"),
        Lang(code: "lv", name: "Latviešu"),
        Lang(code: "lt", name: "Lietuvių"),
        Lang(code: "fa", name: "فارسی"),
        Lang(code: "ur", name: "اردو"),
        Lang(code: "ta", name: "தமிழ்"),
        Lang(code: "te", name: "తెలుగు"),
        Lang(code: "bn", name: "বাংলা"),
        Lang(code: "mr", name: "मराठी"),
        Lang(code: "sw", name: "Kiswahili"),
        Lang(code: "af", name: "Afrikaans"),
        Lang(code: "kk", name: "Қазақша"),
        Lang(code: "az", name: "Azərbaycanca"),
        Lang(code: "ka", name: "ქართული"),
        Lang(code: "hy", name: "Հայերեն"),
        Lang(code: "sq", name: "Shqip"),
        Lang(code: "mk", name: "Македонски"),
        Lang(code: "bs", name: "Bosanski"),
        Lang(code: "is", name: "Íslenska"),
        Lang(code: "ga", name: "Gaeilge"),
        Lang(code: "cy", name: "Cymraeg"),
        Lang(code: "mt", name: "Malti"),
        Lang(code: "lb", name: "Lëtzebuergesch"),
        Lang(code: "be", name: "Беларуская"),
        Lang(code: "tl", name: "Tagalog"),
        Lang(code: "la", name: "Latina"),
    ]

    static func name(for code: String) -> String {
        if code == "auto" { return auto.name }
        return all.first { $0.code == code }?.name ?? code
    }
}

/// Favorite-language chips + searchable add/remove popover.
/// Selecting a chip sets the active dictation language.
struct LanguagePicker: View {
    @ObservedObject var settings = Settings.shared
    @State private var showEditor = false
    @State private var search = ""

    var body: some View {
        // Wrapping chip row: favorites + Auto + edit button
        FlowChips(spacing: 6) {
            ForEach(settings.favoriteLanguages, id: \.self) { code in
                chip(code)
            }
            chip("auto")
            Button { showEditor.toggle() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DS.fg2)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Color.white.opacity(0.07)))
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showEditor, arrowEdge: .bottom) { editor }
        }
    }

    private func chip(_ code: String) -> some View {
        let active = settings.language == code
        return Button { settings.language = code } label: {
            Text(Languages.name(for: code))
                .font(.system(size: 11, weight: active ? .semibold : .regular))
                .foregroundStyle(active ? Color(hex: 0x0F0F0F) : DS.fg2)
                .padding(.horizontal, 11)
                .frame(height: 26)
                .background(
                    Capsule().fill(active ? DS.brand : Color.white.opacity(0.07))
                )
        }
        .buttonStyle(.plain)
    }

    private var editor: some View {
        VStack(spacing: 0) {
            TextField("Search languages…", text: $search)
                .textFieldStyle(.plain)
                .padding(10)
                .background(Color.white.opacity(0.05))

            Divider().overlay(DS.border)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { lang in
                        let isFav = settings.favoriteLanguages.contains(lang.code)
                        Button { toggle(lang.code, isFav: isFav) } label: {
                            HStack {
                                Text(lang.name).font(.system(size: 12)).foregroundStyle(DS.fg)
                                Text(lang.code).font(DS.label(9)).foregroundStyle(DS.fg3)
                                Spacer()
                                Image(systemName: isFav ? "checkmark.circle.fill" : "plus.circle")
                                    .font(.system(size: 13))
                                    .foregroundStyle(isFav ? DS.brand : DS.fg3)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(width: 240, height: 260)
        }
        .background(DS.bg)
        .preferredColorScheme(.dark)
    }

    private var filtered: [Lang] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return Languages.all }
        return Languages.all.filter {
            $0.name.lowercased().contains(q) || $0.code.contains(q)
        }
    }

    private func toggle(_ code: String, isFav: Bool) {
        if isFav {
            settings.favoriteLanguages.removeAll { $0 == code }
            // Active language must stay valid
            if settings.language == code {
                settings.language = settings.favoriteLanguages.first ?? "auto"
            }
        } else {
            settings.favoriteLanguages.append(code)
            settings.language = code
        }
    }
}

/// Minimal wrapping layout for chips (macOS 13+ Layout protocol).
struct FlowChips: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            sub.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}
