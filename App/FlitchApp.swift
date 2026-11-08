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
    private var statusItem: NSStatusItem?
    private let credentials = CredentialStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "Flitch"
        let menu = NSMenu()
        // Temporary until the onboarding flow (#29).
        menu.addItem(
            withTitle: String(localized: "Sign in with OpenRouter…"), action: #selector(signInWithOpenRouter),
            keyEquivalent: ""
        ).target = self
        menu.addItem(.separator())
        menu.addItem(
            withTitle: String(localized: "Quit Flitch"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        item.menu = menu
        statusItem = item
    }

    @objc private func signInWithOpenRouter() {
        Task {
            do {
                let key = try await OpenRouterAuth().signIn { url in
                    await MainActor.run { _ = NSWorkspace.shared.open(url) }
                }
                try await credentials.save(.apiKey(key), for: "openrouter")
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
