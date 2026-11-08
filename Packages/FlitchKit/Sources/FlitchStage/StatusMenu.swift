import AppKit
import FlitchCore

/// The menu-bar item: a pixel otter head that reflects what Flitch is doing.
@MainActor
public final class StatusMenu: NSObject {
    public enum State { case idle, listening, speaking }

    public var onTalk: () -> Void = {}
    public var onSettings: () -> Void = {}
    public var onAbout: () -> Void = {}
    public var extraItems: [NSMenuItem] = [] {
        didSet { rebuild() }
    }

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    public override init() {
        super.init()
        item.button?.image = Self.icon(.idle)
        item.button?.setAccessibilityLabel("Flitch")
        item.menu = menu
        rebuild()
    }

    public func setState(_ state: State) {
        item.button?.image = Self.icon(state)
    }

    private func rebuild() {
        menu.removeAllItems()
        add(String(localized: "Talk to Flitch", bundle: .main), #selector(talk))
        menu.addItem(.separator())
        extraItems.forEach { menu.addItem($0) }
        if !extraItems.isEmpty { menu.addItem(.separator()) }
        add(String(localized: "Settings…", bundle: .main), #selector(settings), key: ",")
        add(String(localized: "About Flitch", bundle: .main), #selector(about))
        menu.addItem(.separator())
        menu.addItem(
            withTitle: String(localized: "Quit Flitch", bundle: .main), action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
    }

    private func add(_ title: String, _ action: Selector, key: String = "") {
        let i = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        i.target = self
    }

    @objc private func talk() { onTalk() }
    @objc private func settings() { onSettings() }
    @objc private func about() { onAbout() }

    /// 16×16 pixel otter head (template image, so it follows the menu-bar appearance).
    static func icon(_ state: State) -> NSImage {
        let rows = [
            "................",
            "..XX........XX..",
            ".XXXXXXXXXXXXXX.",
            "XXXXXXXXXXXXXXXX",
            "XXX.XXXXXXXX.XXX",
            "XXX.XXXXXXXX.XXX",
            "XXXXXXXXXXXXXXXX",
            "XXXXX......XXXXX",
            "XXXX..XXXX..XXXX",
            ".XXX...XX...XXX.",
            ".XXXX......XXXX.",
            "..XXXXX..XXXXX..",
            "...XXXXXXXXXX...",
            "....XXXXXXXX....",
            "................",
            "................",
        ]
        let px: CGFloat = 1.125
        let size = NSSize(width: 16 * px, height: 16 * px)
        let image = NSImage(size: size, flipped: true) { _ in
            NSColor.black.setFill()
            for (y, row) in rows.enumerated() {
                for (x, ch) in row.enumerated() where ch == "X" {
                    NSRect(x: CGFloat(x) * px, y: CGFloat(y) * px, width: px, height: px).fill()
                }
            }
            switch state {
            case .idle: break
            case .listening:  // sound waves on the right
                NSRect(x: 15 * px, y: 6 * px, width: px, height: 4 * px).fill()
            case .speaking:  // open mouth
                NSColor.clear.setFill()
                NSRect(x: 7 * px, y: 10 * px, width: 2 * px, height: px).fill(using: .clear)
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Flitch"
        return image
    }
}
