import AppKit
import Carbon.HIToolbox
import FlitchCore
import FlitchStage
import ServiceManagement
import SwiftUI

struct GeneralPane: View {
    let app: AppController
    @Bindable var settings: FlitchSettings

    init(app: AppController) {
        self.app = app
        self.settings = app.settings
    }

    var body: some View {
        Form {
            Section {
                Picker("Mode", selection: $settings.mode) {
                    Text("Discreet").tag(FlitchSettings.Mode.discreet)
                    Text("On the Dock").tag(FlitchSettings.Mode.dock)
                }
                .pickerStyle(.segmented)
                if settings.mode == .discreet {
                    LabeledContent {
                        CornerPicker(corner: $settings.corner)
                    } label: {
                        Text("Screen corner")
                        Text("At the top, she comes down head first").font(.caption).foregroundStyle(.secondary)
                    }
                    LabeledContent("Screen") { Text("The one with the mouse").foregroundStyle(.secondary) }
                } else {
                    Text("She walks on your Dock, plays and naps. Click her to talk.")
                        .foregroundStyle(.secondary)
                    LabeledContent {
                        if DockTracker.accessibilityGranted {
                            Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(FlitchColors.accent)
                        } else {
                            Button("Allow") { DockTracker.requestAccessibility() }
                        }
                    } label: {
                        Text("Exact Dock width")
                        Text("Optional: uses the Accessibility permission to read the Dock's size.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Toggle(isOn: $settings.useRightOption) {
                    Text("Hold right ⌥ to talk")
                    Text("Needs the Input Monitoring permission. Flitch never reads other keys.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .onChange(of: settings.useRightOption) { _, on in
                    if on && !HotkeyMonitor.inputMonitoringGranted { HotkeyMonitor.requestInputMonitoring() }
                }
                LabeledContent(settings.useRightOption ? "Fallback shortcut" : "Shortcut") {
                    ShortcutRecorder(keyCode: $settings.fallbackKeyCode, modifiers: $settings.fallbackModifiers)
                }
                Picker("Language", selection: $settings.language) {
                    Text(verbatim: "English").tag(AppLanguage.english)
                    Text(verbatim: "Français").tag(AppLanguage.french)
                    Text(verbatim: "Español").tag(AppLanguage.spanish)
                }
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { _, on in LaunchAtLogin.set(on) }
            }
            Section("Advanced") {
                Toggle(isOn: $settings.showTimings) {
                    Text("Show response timings")
                    Text("Shows how long each step takes, in the bubble.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(Text("General"))
    }
}

/// Four buttons laid out like the screen's corners.
struct CornerPicker: View {
    @Binding var corner: FlitchSettings.Corner

    var body: some View {
        Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            GridRow {
                cell(.topLeft, "Top left")
                cell(.topRight, "Top right")
            }
            GridRow {
                cell(.bottomLeft, "Bottom left")
                cell(.bottomRight, "Bottom right")
            }
        }
        .padding(4)
        .background(Color(red: 0.16, green: 0.23, blue: 0.32), in: .rect(cornerRadius: 8))
    }

    private func cell(_ c: FlitchSettings.Corner, _ label: LocalizedStringKey) -> some View {
        Button {
            corner = c
        } label: {
            RoundedRectangle(cornerRadius: 4)
                .fill(corner == c ? FlitchColors.accentBright : Color.white.opacity(0.15))
                .frame(width: 30, height: 18)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .accessibilityAddTraits(corner == c ? .isSelected : [])
    }
}

/// Click, then press the new combination (with at least one of ⌃⌥⌘).
struct ShortcutRecorder: View {
    @Binding var keyCode: Int
    @Binding var modifiers: Int
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? String(localized: "Press keys…") : combo.displayString)
                .monospaced()
                .frame(minWidth: 90)
        }
        .onDisappear { stop() }
    }

    private var combo: KeyCombo { KeyCombo(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers)) }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stop()
                return nil
            }
            let carbon = Self.carbonModifiers(event.modifierFlags)
            guard carbon & (controlKey | optionKey | cmdKey) != 0 else { return nil }
            keyCode = Int(event.keyCode)
            modifiers = carbon
            stop()
            return nil
        }
    }

    private func stop() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> Int {
        var m = 0
        if flags.contains(.control) { m |= controlKey }
        if flags.contains(.option) { m |= optionKey }
        if flags.contains(.shift) { m |= shiftKey }
        if flags.contains(.command) { m |= cmdKey }
        return m
    }
}

enum LaunchAtLogin {
    static func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            FlitchLog.info("launch at login: \(error.localizedDescription)")
        }
    }
}
