import AppKit

#if canImport(Sparkle)
import Sparkle

/// Sparkle updates from the GitHub release feed (SUFeedURL in project.yml).
/// Sparkle asks once, on the second launch, before it checks on its own; the
/// check is a plain download of appcast.xml and sends no system profile.
@MainActor final class Updater: ObservableObject {
    static let shared = Updater()
    private let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)

    var isAvailable: Bool { true }
    var automaticallyChecks: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue; objectWillChange.send() }
    }
    func checkForUpdates() { controller.checkForUpdates(nil) }
}
#else
/// The SwiftPM build used by `swift test` links no Sparkle.
@MainActor final class Updater: ObservableObject {
    static let shared = Updater()
    var isAvailable: Bool { false }
    var automaticallyChecks = false
    func checkForUpdates() {}
}
#endif
