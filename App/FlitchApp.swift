import AppKit
import FlitchCore
import FlitchProviders

/// Flitch lives in the menu bar (LSUIElement): no Dock icon, no main window.
@main
@MainActor
enum FlitchMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController?
    private var demo: StageDemo?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let c = try AppController()
            controller = c
            if let i = CommandLine.arguments.firstIndex(of: "--demo-stage") {
                let corner = CommandLine.arguments.dropFirst(i + 1).first ?? "topLeft"
                demo = try StageDemo(controller: c, corner: corner)
                return
            }
            try c.start()
            if let i = CommandLine.arguments.firstIndex(of: "--open-settings") {
                let tab = CommandLine.arguments.dropFirst(i + 1).first.flatMap(SettingsWindow.Tab.init) ?? .general
                c.settingsWindow.show(tab: tab)
            } else if !c.settings.onboardingDone || c.settings.providerID == nil {
                c.onboarding.show()
            }
        } catch {
            let a = NSAlert()
            a.messageText = "Flitch couldn't start"
            a.informativeText = String(describing: error)
            a.runModal()
            NSApp.terminate(nil)
        }
    }

    private func alert(_ title: String, _ text: String) {
        NSApp.activate()
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }
}
