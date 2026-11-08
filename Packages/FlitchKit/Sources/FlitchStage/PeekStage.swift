import AppKit
import FlitchCharacter
import FlitchCore
import SwiftUI

/// Callbacks from the stage to the app.
@MainActor
public struct StageActions {
    public var openAnswer: () -> Void = {}
    public var otterClicked: () -> Void = {}
    public var errorAction: (StageModel.ErrorAction) -> Void = { _ in }
    /// ✓ (true) or ✗ (false) on a pending memory.
    public var answerMemory: (StageModel.MemoryChip, Bool) -> Void = { _, _ in }
    public init() {}
}

/// Where and how the otter peeks in.
public struct StagePresentation: Sendable, Equatable {
    public var corner: FlitchSettings.Corner
    /// Points per sprite pixel (integer for crisp pixels).
    public var scale: CGFloat
    public var visibleRows: Int
    public var shortcutName: String

    public init(corner: FlitchSettings.Corner, scale: CGFloat = 3, visibleRows: Int = 23, shortcutName: String = "⌥") {
        self.corner = corner
        self.scale = scale
        self.visibleRows = visibleRows
        self.shortcutName = shortcutName
    }
}

/// Discreet mode: a transparent panel in a corner of the screen under the mouse.
@MainActor
public final class PeekStage {
    public let model: StageModel
    public var actions = StageActions()
    public private(set) var presentation: StagePresentation

    private let sprites: SpriteSheet
    private var player: AnimationPlayer
    private var panel: NSPanel?
    private var slide: Double = 0  // 0 hidden … 1 fully in
    private var showing = false

    public init(model: StageModel, sprites: SpriteSheet, presentation: StagePresentation) {
        self.model = model
        self.sprites = sprites
        self.presentation = presentation
        self.player = AnimationPlayer(pack: sprites.character.pack)
        var p = presentation
        p.visibleRows = sprites.character.pack.effectivePeek.visibleRows
        self.presentation = p
    }

    public func update(presentation new: StagePresentation) {
        var p = new
        p.visibleRows = sprites.character.pack.effectivePeek.visibleRows
        guard p != presentation else { return }
        presentation = p
        panel?.orderOut(nil)
        panel = nil
    }

    /// Call ~60 times per second. Returns whether the mouse is over the bubble or the otter.
    @discardableResult
    public func tick(_ dt: Double) -> Bool {
        if model.visible && !showing { show() }
        showing = model.visible
        let slideSeconds = max(0.05, sprites.character.pack.effectivePeek.slideSeconds)
        slide = min(1, max(0, slide + (model.visible ? 1 : -1) * dt / slideSeconds))
        // move in whole sprite pixels, like a real pixel-art game
        model.shownRows = Int((Double(presentation.visibleRows) * easeOut(slide)).rounded())
        if !model.visible && slide == 0 { panel?.orderOut(nil) }

        player.play(model.animation)
        _ = player.tick(dt, level: model.speakingLevel)
        if model.frameIndex != player.frame { model.frameIndex = player.frame }
        return updateMouse()
    }

    private func easeOut(_ t: Double) -> Double { 1 - pow(1 - t, 3) }

    // MARK: - Panel

    private func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        place(panel)
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let size = NSSize(width: 520, height: 320)
        let p = NSPanel(
            contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.ignoresMouseEvents = true
        p.isMovable = false
        p.hidesOnDeactivate = false
        let root = StageRootView(model: model, presentation: presentation, sprites: sprites, actions: actions)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]
        p.contentView = host
        return p
    }

    /// Corner of the screen that holds the mouse; top corners sit just under the menu bar.
    private func place(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return }
        let size = panel.frame.size
        let margin: CGFloat = 24
        let x = presentation.corner.isLeft ? screen.frame.minX + margin : screen.frame.maxX - margin - size.width
        let y = presentation.corner.isTop ? screen.visibleFrame.maxY - size.height : screen.frame.minY
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// Clicks pass through the panel except over the otter and the bubble.
    private func updateMouse() -> Bool {
        guard let panel, panel.isVisible, let content = panel.contentView else { return false }
        let p = panel.convertPoint(fromScreen: NSEvent.mouseLocation)
        let swiftUIPoint = CGPoint(x: p.x, y: content.bounds.height - p.y)
        let over = model.bubbleFrame.contains(swiftUIPoint) || model.otterFrame.contains(swiftUIPoint)
        if panel.ignoresMouseEvents == over { panel.ignoresMouseEvents = !over }
        return over
    }
}
