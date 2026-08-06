import CoreAudio
import Foundation
import SwiftUI

struct AudioInputDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let uid: String
    let name: String
    let transport: UInt32

    var isBuiltIn: Bool { transport == kAudioDeviceTransportTypeBuiltIn }
    var isBluetooth: Bool {
        transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    /// SF Symbol for the pill indicator.
    var icon: String {
        if isBluetooth { return "airpodspro" }
        if transport == kAudioDeviceTransportTypeUSB { return "mic.fill" }
        if isBuiltIn { return "laptopcomputer" }
        return "mic"
    }
}

/// CoreAudio HAL queries for input devices. Pure functions, no state.
enum AudioDevices {
    static func list() -> [AudioInputDevice] {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var ids = [AudioDeviceID](repeating: 0, count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            guard hasInput(id) else { return nil }
            return AudioInputDevice(
                id: id,
                uid: stringProperty(id, kAudioDevicePropertyDeviceUID) ?? "",
                name: stringProperty(id, kAudioObjectPropertyName) ?? "Unknown",
                transport: uint32Property(id, kAudioDevicePropertyTransportType) ?? 0
            )
        }
    }

    static func defaultInputID() -> AudioDeviceID? {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id) == noErr,
              id != 0 else { return nil }
        return id
    }

    static func device(uid: String) -> AudioInputDevice? {
        list().first { $0.uid == uid }
    }

    static func builtIn() -> AudioInputDevice? {
        list().first { $0.isBuiltIn }
    }

    static func device(id: AudioDeviceID) -> AudioInputDevice? {
        list().first { $0.id == id }
    }

    // MARK: property helpers

    private static func hasInput(_ id: AudioDeviceID) -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr else { return false }
        return size > 0
    }

    private static func stringProperty(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var ref: CFString? = nil
        var size = UInt32(MemoryLayout<CFString?>.size)
        let err = withUnsafeMutablePointer(to: &ref) { ptr in
            AudioObjectGetPropertyData(id, &addr, 0, nil, &size, ptr)
        }
        guard err == noErr, let ref else { return nil }
        return ref as String
    }

    private static func uint32Property(_ id: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var addr = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }
}

@MainActor
final class AudioDeviceMonitor: ObservableObject {
    static let shared = AudioDeviceMonitor()

    @Published private(set) var devices: [AudioInputDevice] = []
    @Published private(set) var revision = 0
    private let listenerQueue = DispatchQueue(label: "hlas.audio-device-monitor")
    private var listeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    private init() {
        devices = AudioDevices.list()
        listen(for: kAudioHardwarePropertyDevices)
        listen(for: kAudioHardwarePropertyDefaultInputDevice)
    }

    func refresh() {
        devices = AudioDevices.list()
    }

    private func listen(for selector: AudioObjectPropertySelector) {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.revision += 1
                self?.refresh()
            }
        }
        guard AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            listenerQueue,
            block
        ) == noErr else { return }
        listeners.append((address, block))
    }
}

/// Settings dropdown: system default / pinned built-in / specific device.
struct InputDevicePicker: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var monitor = AudioDeviceMonitor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Menu {
                Button { settings.inputDeviceUID = "" } label: {
                    row("System default", checked: settings.inputDeviceUID.isEmpty)
                }
                Button { settings.inputDeviceUID = "builtin" } label: {
                    row("Built-in mic - always (ignore AirPods switch)", checked: settings.inputDeviceUID == "builtin")
                }
                if !monitor.devices.isEmpty { Divider() }
                ForEach(monitor.devices) { device in
                    Button { settings.inputDeviceUID = device.uid } label: {
                        row(device.name, checked: settings.inputDeviceUID == device.uid)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: currentIcon).font(.system(size: 11)).foregroundStyle(DS.fg2)
                    Text(currentLabel).font(.system(size: 12)).foregroundStyle(DS.fg)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9)).foregroundStyle(DS.fg3)
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: DS.radiusSm).fill(Color.white.opacity(0.06)))
            }
            .menuStyle(.borderlessButton)
            .onAppear { monitor.refresh() }
            .accessibilityLabel("Microphone")
            .accessibilityValue(currentLabel)
            .accessibilityHint("Choose which microphone Hlas records from")

            Text("Pin the built-in mic to keep dictation quality when Bluetooth headphones connect.")
                .font(.system(size: 10)).foregroundStyle(DS.fg3)
        }
    }

    private func row(_ title: String, checked: Bool) -> some View {
        HStack {
            if checked { Image(systemName: "checkmark") }
            Text(title)
        }
    }

    private var currentLabel: String {
        switch settings.inputDeviceUID {
        case "": return "System default"
        case "builtin": return "Built-in mic (always)"
        case let uid: return monitor.devices.first { $0.uid == uid }?.name ?? "Unavailable - using default"
        }
    }

    private var currentIcon: String {
        switch settings.inputDeviceUID {
        case "": return "gearshape"
        case "builtin": return "laptopcomputer"
        case let uid: return monitor.devices.first { $0.uid == uid }?.icon ?? "questionmark.circle"
        }
    }
}
