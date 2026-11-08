import FlitchCore
import SwiftUI

/// Teal accent of the mockups (contrast ≥ 4.5:1 on white for text and filled buttons).
public enum FlitchColors {
    public static let accent = Color(red: 0.043, green: 0.490, blue: 0.443)  // #0B7D71
    public static let accentBright = Color(red: 0.059, green: 0.624, blue: 0.561)  // #0F9F8F
}

/// Everything shown in the corner panel: the peeking otter and its bubble.
struct StageRootView: View {
    @Bindable var model: StageModel
    let presentation: StagePresentation
    let sprites: SpriteSheet
    let actions: StageActions

    var body: some View {
        let top = presentation.corner.isTop
        let left = presentation.corner.isLeft
        VStack(spacing: 0) {
            if !top { Spacer(minLength: 0) }
            HStack(alignment: top ? .top : .bottom, spacing: 12) {
                if !left { Spacer(minLength: 0) }
                if left { otter } else { bubble.padding(top ? .top : .bottom, 16) }
                if left { bubble.padding(top ? .top : .bottom, 16) } else { otter }
                if left { Spacer(minLength: 0) }
            }
            if top { Spacer(minLength: 0) }
        }
        .padding(.horizontal, 4)
    }

    private var otter: some View {
        OtterView(model: model, presentation: presentation, sprites: sprites)
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { model.otterFrame = $0 }
            .onTapGesture { actions.otterClicked() }
    }

    @ViewBuilder private var bubble: some View {
        if model.bubble != .none {
            BubbleView(model: model, presentation: presentation, actions: actions)
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { model.bubbleFrame = $0 }
                .transition(
                    .opacity.combined(
                        with: .scale(scale: 0.95, anchor: presentation.corner.isLeft ? .leading : .trailing)))
        }
    }
}

/// The half-body otter, slid in from the screen edge (head-down from the top corners).
struct OtterView: View {
    let model: StageModel
    let presentation: StagePresentation
    let sprites: SpriteSheet

    var body: some View {
        let s = presentation.scale
        let rows = presentation.visibleRows
        let frameSize = CGFloat(sprites.character.pack.frame.width) * s
        let hidden = CGFloat(rows - model.shownRows) * s
        ZStack(alignment: .top) {
            if let image = sprites.frame(model.animation, model.frameIndex) {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: frameSize, height: frameSize)
                    .scaleEffect(x: 1, y: presentation.corner.isTop ? -1 : 1)
                    .offset(
                        y: presentation.corner.isTop
                            ? -(frameSize - CGFloat(rows) * s) - hidden
                            : hidden)
            }
        }
        .frame(width: frameSize, height: CGFloat(rows) * s, alignment: .top)
        .clipped()
        .accessibilityElement()
        .accessibilityLabel(Text("Flitch", bundle: .module))
    }
}

struct BubbleView: View {
    let model: StageModel
    let presentation: StagePresentation
    let actions: StageActions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            .font(.system(size: 15))
            .foregroundStyle(.primary)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: 380, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
            .onHover { model.hovered = $0 }
    }

    @ViewBuilder private var content: some View {
        switch model.bubble {
        case .none:
            EmptyView()
        case .listening(let transcript):
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Waveform(level: model.microphoneLevel, animated: !reduceMotion)
                    Text("I'm listening", bundle: .module).fontWeight(.semibold)
                }
                if !transcript.isEmpty { Text(transcript).foregroundStyle(.secondary) }
                Text("Release \(presentation.shortcutName) to send", bundle: .module)
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 320, alignment: .leading)
        case .thinking:
            ThinkingLabel(animated: !reduceMotion)
        case .speaking(let spoken, let current):
            VStack(alignment: .leading, spacing: 8) {
                // long answers: keep the end visible (the full text is in the answer card)
                (Text(spoken.isEmpty ? "" : spoken + " ").foregroundStyle(.secondary) + Text(current))
                    .lineSpacing(3)
                    .lineLimit(7)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                Label {
                    Text("Press \(presentation.shortcutName) to interrupt", bundle: .module)
                } icon: {
                    Image(systemName: "speaker.wave.2.fill").foregroundStyle(FlitchColors.accent)
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 340, alignment: .leading)
        case .lingering(let text, let progress):
            Button(action: actions.openAnswer) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(text).lineLimit(5).lineSpacing(3).frame(maxWidth: .infinity, alignment: .leading)
                    Text("Open the full answer", bundle: .module)
                        .font(.caption.weight(.semibold)).foregroundStyle(FlitchColors.accent)
                    ProgressView(value: progress).tint(FlitchColors.accentBright).controlSize(.mini)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: 340, alignment: .leading)
        case .error(let error):
            VStack(alignment: .leading, spacing: 10) {
                Text(error.userMessage)
                if let action = StageModel.action(for: error) {
                    Button {
                        actions.errorAction(action)
                    } label: {
                        Text(action.title)
                    }
                    .buttonStyle(.borderedProminent).tint(FlitchColors.accent).controlSize(.small)
                }
            }
            .frame(width: 320, alignment: .leading)
        }
        if !model.timings.isEmpty {
            Text(model.timings.joined(separator: " · ")).font(.caption2.monospaced()).foregroundStyle(.tertiary)
        }
    }
}

extension StageModel.ErrorAction {
    var title: LocalizedStringResource {
        switch self {
        case .openSettings: LocalizedStringResource("Open Settings", bundle: .module)
        case .openPrivacySettings: LocalizedStringResource("Open Privacy Settings", bundle: .module)
        case .retry: LocalizedStringResource("Try again", bundle: .module)
        }
    }
}

/// Seven bars that follow the microphone level.
struct Waveform: View {
    var level: Float
    var animated: Bool
    private let weights: [CGFloat] = [0.5, 0.8, 1, 0.7, 0.9, 0.6, 0.4]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(weights.indices, id: \.self) { i in
                Capsule()
                    .fill(FlitchColors.accentBright)
                    .frame(width: 3, height: max(4, 22 * weights[i] * CGFloat(animated ? level : 0.5)))
            }
        }
        .frame(height: 22)
        .animation(animated ? .easeOut(duration: 0.08) : nil, value: level)
        .accessibilityHidden(true)
    }
}

struct ThinkingLabel: View {
    var animated: Bool
    @State private var phase = false

    var body: some View {
        Text("Thinking…", bundle: .module)
            .fontWeight(.semibold)
            .opacity(animated ? (phase ? 1 : 0.45) : 1)
            .onAppear {
                guard animated else { return }
                withAnimation(.easeInOut(duration: 0.8).repeatForever()) { phase = true }
            }
    }
}
