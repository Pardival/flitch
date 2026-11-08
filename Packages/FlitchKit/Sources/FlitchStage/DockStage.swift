import AppKit
import FlitchCharacter
import FlitchCore
import SwiftUI

/// What the Dock scene draws, updated by `DockStage` every frame.
@MainActor
@Observable
final class DockScene {
    var animation = "idle"
    var frameIndex = 0
    var facingRight = true
    /// Left edge of the otter inside the panel.
    var otterLeft: CGFloat = 0
    var bubbleLeft: CGFloat = 0
}

/// Dock mode: the otter lives on top of the Dock, walks around, plays, naps, and talks from there.
@MainActor
public final class DockStage: Stage {
    public let model: StageModel
    public var actions = StageActions()
    public private(set) var presentation: StagePresentation

    private let sprites: SpriteSheet
    private let tracker = DockTracker()
    private let scene = DockScene()
    private var behavior: DockBehavior
    private var player: AnimationPlayer
    private var panel: NSPanel?
    private var alpha: Double = 0
    private var wasTalking = false
    private var otterX: CGFloat?  // screen x of the otter's center

    static let panelSize = NSSize(width: 440, height: 360)
    static let bubbleWidth: CGFloat = 380

    public init(model: StageModel, sprites: SpriteSheet, presentation: StagePresentation) {
        self.model = model
        self.sprites = sprites
        self.presentation = presentation
        let pack = sprites.character.pack
        self.player = AnimationPlayer(pack: pack)
        self.behavior = DockBehavior(
            tuning: DockBehavior.tuning(for: pack, scale: presentation.scale), startX: 0)
    }

    public func update(presentation new: StagePresentation) {
        guard new != presentation else { return }
        presentation = new
        panel?.contentView = host()
    }

    public func tearDown() {
        panel?.orderOut(nil)
        panel = nil
    }

    private var otterSize: CGFloat { CGFloat(sprites.character.pack.frame.width) * presentation.scale }

    @discardableResult
    public func tick(_ dt: Double) -> Bool {
        let dock = tracker.update(mouse: NSEvent.mouseLocation)
        let talking = model.visible
        let half = otterSize / 2
        let bounds = Double(dock.minX + half)...Double(max(dock.minX + half, dock.maxX - half))
        if otterX == nil {
            behavior = DockBehavior(
                tuning: DockBehavior.tuning(for: sprites.character.pack, scale: presentation.scale),
                startX: (bounds.lowerBound + bounds.upperBound) / 2)
        }
        if talking && !wasTalking { behavior.interact() }
        wasTalking = talking

        let out = talking ? behavior.output : behavior.tick(dt, bounds: bounds)
        otterX = CGFloat(out.x)
        // talking: face the user with the conversation animations
        let animation = talking ? model.animation : out.animation
        player.play(animation)
        _ = player.tick(dt, level: model.speakingLevel)
        scene.animation = animation
        scene.frameIndex = player.frame
        scene.facingRight = talking || out.facingRight

        // shown with the Dock (and always while talking, even in full screen)
        let target: Double = dock.visible || talking ? 1 : 0
        alpha = min(1, max(0, alpha + (target - alpha) * min(1, dt * 10)))
        if target > 0 || alpha > 0.01 {
            let panel = self.panel ?? makePanel()
            self.panel = panel
            place(panel, dock: dock)
            panel.alphaValue = alpha
            if !panel.isVisible { panel.orderFrontRegardless() }
        } else if let panel, panel.isVisible {
            panel.orderOut(nil)
        }
        return updateMouse()
    }

    // MARK: - Panel

    private func host() -> NSView {
        let root = DockRootView(
            model: model, scene: scene, sprites: sprites, presentation: presentation, actions: actions)
        let host = NSHostingView(rootView: root)
        host.frame = NSRect(origin: .zero, size: Self.panelSize)
        host.autoresizingMask = [.width, .height]
        return host
    }

    private func makePanel() -> NSPanel {
        let p = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.ignoresMouseEvents = true
        p.hidesOnDeactivate = false
        p.contentView = host()
        return p
    }

    /// Panel follows the otter in whole points; the otter's feet stand on the Dock.
    private func place(_ panel: NSPanel, dock: DockState) {
        guard let x = otterX else { return }
        let size = Self.panelSize
        let screen = dock.screenFrame
        let left = min(max(screen.minX, (x - size.width / 2).rounded()), screen.maxX - size.width)
        let origin = NSPoint(x: left, y: dock.groundY.rounded())
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
        let otterLeft = (x - left - otterSize / 2).rounded()
        if scene.otterLeft != otterLeft { scene.otterLeft = otterLeft }
        let bubbleLeft = min(max(0, otterLeft + otterSize / 2 - Self.bubbleWidth / 2), size.width - Self.bubbleWidth)
        if scene.bubbleLeft != bubbleLeft { scene.bubbleLeft = bubbleLeft }
    }

    private func updateMouse() -> Bool {
        guard let panel, panel.isVisible, let content = panel.contentView else { return false }
        let p = panel.convertPoint(fromScreen: NSEvent.mouseLocation)
        let point = CGPoint(x: p.x, y: content.bounds.height - p.y)
        let over = model.bubbleFrame.contains(point) || model.otterFrame.contains(point)
        if panel.ignoresMouseEvents == over { panel.ignoresMouseEvents = !over }
        return over
    }
}

/// The otter at the bottom of the panel, the bubble above it.
struct DockRootView: View {
    @Bindable var model: StageModel
    let scene: DockScene
    let sprites: SpriteSheet
    let presentation: StagePresentation
    let actions: StageActions

    var body: some View {
        let size = CGFloat(sprites.character.pack.frame.width) * presentation.scale
        ZStack(alignment: .bottomLeading) {
            Color.clear
            if let image = sprites.frame(scene.animation, scene.frameIndex) {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: size, height: size)
                    .scaleEffect(x: scene.facingRight ? 1 : -1, y: 1)
                    .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { model.otterFrame = $0 }
                    .onTapGesture { actions.otterClicked() }
                    .offset(x: scene.otterLeft)
                    .accessibilityElement()
                    .accessibilityLabel(Text("Flitch", bundle: .module))
            }
            if model.bubble != .none {
                BubbleView(
                    model: model,
                    presentation: StagePresentation(corner: .bottomLeft, shortcutName: presentation.shortcutName),
                    actions: actions
                )
                .fixedSize()
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { model.bubbleFrame = $0 }
                .frame(width: DockStage.bubbleWidth, alignment: .bottom)
                .offset(x: scene.bubbleLeft, y: -(size + 6))
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .bottom)))
            }
        }
        .frame(width: DockStage.panelSize.width, height: DockStage.panelSize.height, alignment: .bottomLeading)
    }
}
