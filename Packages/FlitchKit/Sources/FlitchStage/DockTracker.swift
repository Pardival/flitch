import AppKit
@preconcurrency import ApplicationServices

/// Where the Dock is and whether it is on screen (Cocoa screen coordinates).
public struct DockState: Equatable, Sendable {
    public var visible: Bool
    /// Top edge of the Dock: where the otter's feet go.
    public var groundY: CGFloat
    public var minX: CGFloat
    public var maxX: CGFloat
    public var screenFrame: CGRect
}

/// The Dock's own settings (`com.apple.dock` preferences).
public struct DockPrefs: Equatable, Sendable {
    public var autohide = false
    public var orientation = "bottom"
    public var tileSize: CGFloat = 48
    public var autohideDelay: Double = 0
    public var persistentApps: [String] = []
    public var persistentOthers = 0
    public var recentApps: [String] = []

    public init() {}

    static func read() -> DockPrefs {
        let app = "com.apple.dock" as CFString
        CFPreferencesAppSynchronize(app)
        func val(_ k: String) -> Any? { CFPreferencesCopyAppValue(k as CFString, app) }
        func bundleIDs(_ list: Any?) -> [String] {
            ((list as? [[String: Any]]) ?? []).compactMap {
                ($0["tile-data"] as? [String: Any])?["bundle-identifier"] as? String
            }
        }
        var p = DockPrefs()
        p.autohide = val("autohide") as? Bool ?? false
        p.orientation = val("orientation") as? String ?? "bottom"
        p.tileSize = CGFloat(val("tilesize") as? Double ?? 48)
        p.autohideDelay = val("autohide-delay") as? Double ?? 0
        p.persistentApps = bundleIDs(val("persistent-apps"))
        p.persistentOthers = ((val("persistent-others") as? [Any]) ?? []).count
        p.recentApps = (val("show-recents") as? Bool ?? true) ? bundleIDs(val("recent-apps")) : []
        return p
    }
}

/// Pure Dock maths, unit-tested.
public enum DockGeometry {
    /// Dock width without Accessibility: icons × tile size, plus separators and padding.
    public static func estimatedWidth(prefs: DockPrefs, runningApps: [String], screenWidth: CGFloat) -> CGFloat {
        let pinned = Set(prefs.persistentApps)
        let extra = Set(runningApps.filter { $0 != "com.apple.finder" }).union(prefs.recentApps).subtracting(pinned)
            .count
        let icons = 1 + prefs.persistentApps.count + extra + prefs.persistentOthers + 1  // Finder … Trash
        let separators = 1 + (extra > 0 ? 1 : 0)
        let w = CGFloat(icons) * (prefs.tileSize + 1.2) + CGFloat(separators) * 14 + 20
        return min(w, screenWidth - 8)
    }

    /// Height of the Dock band above the bottom of the screen.
    public static func height(prefs: DockPrefs, reserved: CGFloat) -> CGFloat {
        prefs.autohide ? prefs.tileSize + 18 : max(reserved, prefs.tileSize + 18)
    }
}

/// Follows the auto-hidden Dock: it shows when the mouse rests on the bottom edge and hides when it leaves.
public struct AutohideReveal: Sendable {
    public private(set) var revealed = false
    private var touchSince: Double?

    public init() {}

    public mutating func update(
        mouse: CGPoint, screen: CGRect, dockHeight: CGFloat, minX: CGFloat, maxX: CGFloat, delay: Double, now: Double
    ) -> Bool {
        let atBottom = mouse.y <= screen.minY + 2 && mouse.x >= screen.minX && mouse.x <= screen.maxX
        if atBottom {
            if touchSince == nil { touchSince = now }
            if now - (touchSince ?? now) >= delay { revealed = true }
        } else {
            touchSince = nil
        }
        if revealed && (mouse.y > screen.minY + dockHeight + 12 || mouse.x < minX - 20 || mouse.x > maxX + 20) {
            revealed = false
        }
        return revealed
    }
}

/// Where the Dock is right now. Exact width with Accessibility (optional), estimated otherwise.
/// Full screen is detected by the Dock's own window disappearing.
@MainActor
public final class DockTracker {
    private var prefs = DockPrefs()
    private var prefsReadAt = -Double.infinity
    private var reveal = AutohideReveal()
    private var dockWindowCache: (at: Double, onScreen: Bool) = (-.infinity, true)
    private var axCache: (at: Double, frame: CGRect?) = (-.infinity, nil)

    public init() {}

    public func update(mouse: CGPoint, now: Double = ProcessInfo.processInfo.systemUptime) -> DockState {
        if now - prefsReadAt > 2 {
            prefs = DockPrefs.read()
            prefsReadAt = now
        }
        let screen =
            NSScreen.screens.first { $0.visibleFrame.minY > $0.frame.minY + 1 } ?? NSScreen.screens.first
        let sf = screen?.frame ?? .zero
        guard let screen, prefs.orientation == "bottom" else {
            // side docks: not supported yet, the otter stays hidden
            return DockState(visible: false, groundY: sf.minY, minX: sf.minX, maxX: sf.maxX, screenFrame: sf)
        }
        let height = DockGeometry.height(prefs: prefs, reserved: screen.visibleFrame.minY - sf.minY)
        var ground = sf.minY + height - 2
        var minX: CGFloat
        var maxX: CGFloat
        if let ax = accessibilityFrame(now: now), ax.width > 50 {
            minX = ax.minX
            maxX = ax.maxX
            if !prefs.autohide { ground = ax.maxY }
        } else {
            let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }
                .compactMap(\.bundleIdentifier)
            let w = DockGeometry.estimatedWidth(prefs: prefs, runningApps: running, screenWidth: sf.width)
            minX = sf.midX - w / 2
            maxX = sf.midX + w / 2
        }
        var visible = dockWindowOnScreen(now: now)
        if visible && prefs.autohide {
            visible = reveal.update(
                mouse: mouse, screen: sf, dockHeight: height, minX: minX, maxX: maxX, delay: prefs.autohideDelay,
                now: now)
        }
        return DockState(visible: visible, groundY: ground, minX: minX, maxX: maxX, screenFrame: sf)
    }

    /// The Dock draws in a system window; in a full-screen space that window is gone.
    private func dockWindowOnScreen(now: Double) -> Bool {
        if now - dockWindowCache.at < 0.3 { return dockWindowCache.onScreen }
        guard
            let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?
                .processIdentifier
        else { return true }
        let list = (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]) ?? []
        let level = Int(CGWindowLevelForKey(.dockWindow))
        let found = list.contains {
            ($0[kCGWindowOwnerPID as String] as? Int32) == pid && ($0[kCGWindowLayer as String] as? Int) == level
        }
        dockWindowCache = (now, found)
        return found
    }

    // MARK: - Accessibility (optional, for the exact width)

    public static var accessibilityGranted: Bool { AXIsProcessTrusted() }

    public static func requestAccessibility() {
        let key = "AXTrustedCheckOptionPrompt"  // kAXTrustedCheckOptionPrompt
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    private func accessibilityFrame(now: Double) -> CGRect? {
        guard AXIsProcessTrusted() else { return nil }
        if now - axCache.at < 1 { return axCache.frame }
        axCache = (now, Self.readAccessibilityFrame())
        return axCache.frame
    }

    private static func readAccessibilityFrame() -> CGRect? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return nil }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXChildrenAttribute as CFString, &children) == .success,
            let list = (children as? [AXUIElement])?.first(where: { el in
                var role: CFTypeRef?
                AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &role)
                return (role as? String) == (kAXListRole as String)
            })
        else { return nil }
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(list, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(list, kAXSizeAttribute as CFString, &sizeRef)
        var pos = CGPoint.zero
        var size = CGSize.zero
        if let p = posRef, CFGetTypeID(p) == AXValueGetTypeID() { AXValueGetValue(p as! AXValue, .cgPoint, &pos) }
        if let s = sizeRef, CFGetTypeID(s) == AXValueGetTypeID() { AXValueGetValue(s as! AXValue, .cgSize, &size) }
        // Accessibility: origin at the top left of the main screen; Cocoa: bottom left
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: pos.x, y: primaryHeight - pos.y - size.height, width: size.width, height: size.height)
    }
}
