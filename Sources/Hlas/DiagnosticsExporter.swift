import AppKit
import AVFoundation
import Foundation
import UniformTypeIdentifiers

@MainActor
enum DiagnosticsExporter {
    static func present() {
        do {
            guard let url = try export() else { return }
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Could not export diagnostics"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    private static func export() throws -> URL? {
        let panel = NSSavePanel()
        panel.title = "Export Hlas Diagnostics"
        panel.nameFieldStringValue = "Hlas-diagnostics.txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return nil }

        try report().write(to: destination, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: destination.path
        )
        return destination
    }

    private static func report() -> String {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let settings = Settings.shared
        let microphone = microphoneDescription(for: settings.inputDeviceUID)
        let microphonePermission = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let accessibilityPermission = Hotkey.hasAccessibilityPermission(prompt: false)

        return """
        Hlas diagnostics
        Created: \(ISO8601DateFormatter().string(from: Date()))
        Privacy: This report contains no transcripts or API keys.

        App version: \(version) (\(build))
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        Architecture: \(architecture)
        Engine: \(settings.engine.displayName)
        Language: \(Languages.name(for: settings.language))
        Microphone preference: \(microphone)
        Microphone permission: \(microphonePermission ? "granted" : "missing")
        Accessibility permission: \(accessibilityPermission ? "granted" : "missing")

        Debug log
        \(Log.snapshot())
        """
    }

    private static func microphoneDescription(for preference: String) -> String {
        switch preference {
        case "":
            return "System default"
        case "builtin":
            return AudioDevices.builtIn()?.name ?? "Built-in microphone"
        default:
            return AudioDevices.device(uid: preference)?.name ?? "Selected microphone unavailable"
        }
    }

    private static var architecture: String {
        #if arch(arm64)
        return "Apple Silicon (arm64)"
        #else
        return "Unsupported"
        #endif
    }
}
