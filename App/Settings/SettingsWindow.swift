import AppKit
import FlitchCore
import FlitchStage
import SwiftUI

/// Settings, in the style of macOS System Settings (see docs/mockups).
@MainActor
final class SettingsWindow {
    enum Tab: String, CaseIterable, Identifiable {
        case general, brain, voice, personality, memory, history
        var id: String { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .general: "General"
            case .brain: "Brain"
            case .voice: "Voice"
            case .personality: "Personality"
            case .memory: "Memory"
            case .history: "History"
            }
        }

        var icon: String {
            switch self {
            case .general: "gearshape.fill"
            case .brain: "brain.head.profile.fill"
            case .voice: "waveform"
            case .personality: "face.smiling.inverse"
            case .memory: "brain.fill"
            case .history: "clock.arrow.circlepath"
            }
        }

        var color: Color {
            switch self {
            case .general: .gray
            case .brain: .indigo
            case .voice: .orange
            case .personality: .pink
            case .memory: .teal
            case .history: .blue
            }
        }
    }

    @MainActor @Observable final class Selection {
        var tab: Tab = .general
    }

    private weak var app: AppController?
    private var window: NSWindow?
    private let selection = Selection()

    init(app: AppController) { self.app = app }

    func show(tab: Tab) {
        guard let app else { return }
        selection.tab = tab
        if window == nil {
            let root = SettingsView(app: app, selection: selection)
            let w = NSWindow(contentViewController: NSHostingController(rootView: root))
            w.title = String(localized: "Flitch Settings")
            w.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
            w.setContentSize(NSSize(width: 760, height: 540))
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    let app: AppController
    @Bindable var selection: SettingsWindow.Selection

    var body: some View {
        NavigationSplitView {
            List(SettingsWindow.Tab.allCases, selection: $selection.tab) { tab in
                Label {
                    Text(tab.title)
                } icon: {
                    Image(systemName: tab.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(tab.color.gradient, in: .rect(cornerRadius: 6))
                }
                .tag(tab)
            }
            .navigationSplitViewColumnWidth(200)
            .safeAreaInset(edge: .top) { header }
        } detail: {
            switch selection.tab {
            case .general: GeneralPane(app: app)
            case .brain: BrainPane(connector: app.connector, settings: app.settings, loadModels: app.availableModels)
            case .voice: VoicePane(app: app)
            case .personality: PersonalityPane(settings: app.settings)
            case .memory: MemoryPane(app: app)
            case .history: HistoryPane(app: app)
            }
        }
        .frame(minWidth: 720, minHeight: 500)
        .tint(FlitchColors.accent)
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let image = app.iconImage {
                Image(decorative: image, scale: 1).interpolation(.none).resizable().frame(width: 36, height: 36)
                    .padding(2).background(.background, in: .rect(cornerRadius: 9))
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("Flitch").font(.headline)
                Text("Otter · v\(Bundle.main.shortVersion)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12).padding(.bottom, 8)
    }
}

extension Bundle {
    var shortVersion: String { infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }
}
