import AppKit
import Foundation
import SwiftUI

/// Hlas Cloud: the paid subscription. Stripe handles billing; our Worker
/// (cloud/ in this repo) checks the license key and forwards audio to Groq.
enum HlasCloud {
    /// One place to switch when the API moves to its own domain.
    static let baseURL = URL(string: "https://api.hlas.dev")!
    /// Stripe Payment Link for the yearly subscription.
    static let buyURL = URL(string: "https://buy.stripe.com/5kQ8wIdAe58W1YB1zI3Je00")!
    /// Stripe customer portal sign-in, for people without a working key.
    static let portalLoginURL = URL(string: "https://billing.stripe.com/p/login/5kQ8wIdAe58W1YB1zI3Je00")!

    static var transcriptionEndpoint: URL { baseURL.appendingPathComponent("v1/audio/transcriptions") }

    /// Random id of this install: one free trial per install, and the 5-computer limit.
    static var installID: String {
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: "hlasInstallID"), id.count >= 16 { return id }
        let id = "mac-" + UUID().uuidString
        defaults.set(id, forKey: "hlasInstallID")
        return id
    }

    /// Adds the install id to requests bound for Hlas Cloud (and only those).
    static func tag(_ request: inout URLRequest) {
        guard request.url?.host == baseURL.host else { return }
        request.setValue(installID, forHTTPHeaderField: "X-Hlas-Device")
    }

    enum TrialResult: Equatable { case started(key: String), ended(key: String), refused(String) }

    /// Free 7-day trial for this install. Asking again returns the same key.
    static func startTrial() async -> TrialResult {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/trial"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["device": installID])
        request.timeoutInterval = 15
        struct Reply: Decodable { let key: String; let active: Bool }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return .refused("Could not reach Hlas Cloud. Check your connection.") }
        if http.statusCode == 429 { return .refused("Too many trials from this network today. Try again tomorrow.") }
        guard http.statusCode == 200, let reply = try? JSONDecoder().decode(Reply.self, from: data),
              let key = normalize(reply.key) else { return .refused("Hlas Cloud could not start a trial. Try again later.") }
        return reply.active ? .started(key: key) : .ended(key: key)
    }
    static var chatEndpoint: URL { baseURL.appendingPathComponent("v1/chat/completions") }

    /// Accepts the key as shown on the welcome page, lower case or with stray spaces.
    static func normalize(_ raw: String) -> String? {
        var body = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.lowercased().hasPrefix("hlas_") { body.removeFirst(5) }
        body = body.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
        guard body.count == 25 else { return nil }
        let groups = stride(from: 0, to: 25, by: 5).map { i -> String in
            let start = body.index(body.startIndex, offsetBy: i)
            return String(body[start..<body.index(start, offsetBy: 5)])
        }
        return "hlas_" + groups.joined(separator: "-")
    }

    struct Account: Decodable {
        let email: String?
        let active: Bool
        let period_end: Double?
        let trial: Bool?

        var renews: Date? { period_end.map { Date(timeIntervalSince1970: $0) } }
    }

    enum Status: Equatable {
        case unknown, checking, active(email: String?, renews: Date?), trial(ends: Date?), inactive(email: String?), trialEnded, invalidKey, unreachable
    }

    static func account(key: String) async -> Status {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/account"))
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return .unreachable }
        if http.statusCode == 401 { return .invalidKey }
        guard http.statusCode == 200, let account = try? JSONDecoder().decode(Account.self, from: data) else { return .unreachable }
        if account.trial == true { return account.active ? .trial(ends: account.renews) : .trialEnded }
        return account.active ? .active(email: account.email, renews: account.renews) : .inactive(email: account.email)
    }

    /// A one-time Stripe customer portal link for this key, or the portal sign-in page.
    static func portalURL(key: String) async -> URL {
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/portal"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        struct Reply: Decodable { let url: String }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let reply = try? JSONDecoder().decode(Reply.self, from: data),
              let url = URL(string: reply.url) else { return portalLoginURL }
        return url
    }

    /// Handles hlas://activate?key=... from the post-checkout page.
    @MainActor static func handle(_ url: URL) -> Bool {
        guard url.scheme == "hlas", url.host == "activate",
              let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "key" })?.value,
              let key = normalize(raw) else { return false }
        let settings = Settings.shared
        settings.hlasCloudKey = key
        settings.engine = .hlasCloud
        Log.write("Hlas Cloud activated from link")
        return true
    }
}

/// Settings > Engine when Hlas Cloud is selected: license key, status, buy/manage.
struct HlasCloudControls: View {
    @ObservedObject var settings: Settings
    @State private var draft = ""
    @State private var status: HlasCloud.Status = .unknown
    @State private var trialMessage: String?
    @State private var startingTrial = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SecureField("License key (hlas_…)", text: $draft)
                .textFieldStyle(.plain)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: DS.radiusSm).fill(DS.surfaceHover))
                .onSubmit(save)
                .onChange(of: draft) { save() }
            statusLine
            if let trialMessage {
                Text(trialMessage).font(DS.text(11)).foregroundStyle(DS.destructive)
            }
            HStack(spacing: 12) {
                if settings.hlasCloudKey.isEmpty {
                    Button(startingTrial ? "Starting…" : "Try free for 7 days") { startTrial() }
                        .buttonStyle(.borderedProminent).tint(DS.brand.opacity(0.9))
                        .disabled(startingTrial)
                    Button("Get Hlas Cloud - €35 a year") { NSWorkspace.shared.open(HlasCloud.buyURL) }
                        .buttonStyle(.borderless).foregroundStyle(DS.fg2)
                } else if status == .invalidKey || isInactive || isTrial {
                    Button("Get Hlas Cloud - €35 a year") { NSWorkspace.shared.open(HlasCloud.buyURL) }
                        .buttonStyle(.borderedProminent).tint(DS.brand.opacity(0.9))
                }
                if !settings.hlasCloudKey.isEmpty && !isTrial {
                    Button("Manage subscription") {
                        let key = settings.hlasCloudKey
                        Task { NSWorkspace.shared.open(await HlasCloud.portalURL(key: key)) }
                    }
                    .buttonStyle(.borderless).foregroundStyle(DS.fg2)
                }
            }
            Text("Unlimited dictation and Smart text through our servers, no API keys and no model download. Audio is sent to Hlas Cloud (Groq) for transcription and not stored.")
                .font(.system(size: 10)).foregroundStyle(DS.fg3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear {
            draft = settings.hlasCloudKey
            refresh()
        }
        .onChange(of: settings.hlasCloudKey) {
            if draft != settings.hlasCloudKey { draft = settings.hlasCloudKey }
            refresh()
        }
    }

    private var isInactive: Bool {
        if case .inactive = status { return true }
        return status == .trialEnded
    }

    private var isTrial: Bool {
        if case .trial = status { return true }
        return status == .trialEnded
    }

    private func startTrial() {
        startingTrial = true
        trialMessage = nil
        Task {
            let result = await HlasCloud.startTrial()
            startingTrial = false
            switch result {
            case .started(let key), .ended(let key):
                settings.hlasCloudKey = key
                settings.engine = .hlasCloud
                Log.write("Hlas Cloud trial key stored")
            case .refused(let message):
                trialMessage = message
            }
        }
    }

    @ViewBuilder private var statusLine: some View {
        switch status {
        case .unknown:
            Text(settings.hlasCloudKey.isEmpty
                 ? "Start a free trial, or paste the key from the page you saw after paying."
                 : " ")
                .font(DS.text(11)).foregroundStyle(DS.fg2)
        case .checking:
            Text("Checking license…").font(DS.text(11)).foregroundStyle(DS.fg3)
        case .active(let email, let renews):
            Label {
                Text(["Active", email, renews.map { "renews \($0.formatted(date: .abbreviated, time: .omitted))" }]
                    .compactMap { $0 }.joined(separator: " · "))
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.brand)
            }
            .font(DS.text(11)).foregroundStyle(DS.fg2)
        case .trial(let ends):
            Label {
                Text("Free trial" + (ends.map { " until \($0.formatted(date: .abbreviated, time: .omitted))" } ?? "") + " · 30 min a day")
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(DS.brand)
            }
            .font(DS.text(11)).foregroundStyle(DS.fg2)
        case .trialEnded:
            Text("Your free trial has ended. Get Hlas Cloud to keep dictating, or switch back to Local.")
                .font(DS.text(11)).foregroundStyle(DS.destructive)
        case .inactive(let email):
            Text("Subscription not active\(email.map { " for \($0)" } ?? ""). Renew to keep dictating with Hlas Cloud.")
                .font(DS.text(11)).foregroundStyle(DS.destructive)
        case .invalidKey:
            Text("This license key is not recognised.").font(DS.text(11)).foregroundStyle(DS.destructive)
        case .unreachable:
            Text("Could not reach Hlas Cloud to check the license.").font(DS.text(11)).foregroundStyle(DS.fg3)
        }
    }

    private func save() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = HlasCloud.normalize(trimmed) ?? trimmed
        if normalized != settings.hlasCloudKey { settings.hlasCloudKey = normalized }
    }

    private func refresh() {
        let key = settings.hlasCloudKey
        guard HlasCloud.normalize(key) != nil else {
            status = key.isEmpty ? .unknown : .invalidKey
            return
        }
        status = .checking
        Task {
            let result = await HlasCloud.account(key: key)
            if key == settings.hlasCloudKey { status = result }
        }
    }
}
