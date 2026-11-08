import AppKit
import SwiftUI

/// Settings window (filled in by the settings tickets).
@MainActor
final class SettingsWindow {
    enum Tab: String, CaseIterable { case general, brain, voice, personality }

    private weak var app: AppController?
    private var window: NSWindow?

    init(app: AppController) { self.app = app }

    func show(tab: Tab) {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
