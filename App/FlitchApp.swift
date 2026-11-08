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
            c.menu.extraItems = [signInItem()]  // temporary until onboarding (#29)
        } catch {
            let a = NSAlert()
            a.messageText = "Flitch couldn't start"
            a.informativeText = String(describing: error)
            a.runModal()
            NSApp.terminate(nil)
        }
    }

    private func signInItem() -> NSMenuItem {
        let item = NSMenuItem(
            title: String(localized: "Sign in with OpenRouter…"), action: #selector(signInWithOpenRouter),
            keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func signInWithOpenRouter() {
        guard let controller else { return }
        Task {
            do {
                let key = try await OpenRouterAuth().signIn { url in
                    await MainActor.run { _ = NSWorkspace.shared.open(url) }
                }
                try await controller.credentials.save(.apiKey(key), for: "openrouter")
                controller.settings.providerID = "openrouter"
                controller.refreshProvider()
                alert(
                    String(localized: "Connected to OpenRouter"),
                    String(localized: "Flitch can now answer with your OpenRouter account."))
            } catch {
                alert(String(localized: "Sign-in failed"), (FlitchError(error) ?? .other("")).userMessage)
            }
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
