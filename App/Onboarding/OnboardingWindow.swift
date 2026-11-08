import AVFoundation
import AppKit
import FlitchCore
import FlitchStage
import FlitchVoice
import SwiftUI

/// First launch: hello → brain → microphone → shortcut → voice → try it.
@MainActor
final class OnboardingWindow {
    private weak var app: AppController?
    private var window: NSWindow?

    init(app: AppController) { self.app = app }

    func show() {
        guard let app else { return }
        if window == nil {
            let w = NSWindow(
                contentViewController: NSHostingController(
                    rootView: OnboardingView(app: app) { [weak self] in
                        self?.finish()
                    }))
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        app?.settings.onboardingDone = true
        window?.close()
    }
}

struct OnboardingView: View {
    let app: AppController
    let done: () -> Void
    @State private var step = 0
    @State private var micGranted = AVAudioApplication.shared.recordPermission == .granted
    @State private var inputMonitoring = HotkeyMonitor.inputMonitoringGranted
    private let steps = 6

    var body: some View {
        VStack(spacing: 0) {
            otter.padding(.top, 36)
            Group {
                switch step {
                case 0: hello
                case 1: brain
                case 2: microphone
                case 3: shortcut
                case 4: voice
                default: tryIt
                }
            }
            .frame(maxWidth: 480)
            .padding(.top, 22)
            .padding(.horizontal, 40)
            Spacer(minLength: 12)
            footer
        }
        .frame(width: 680, height: 560)
        .tint(FlitchColors.accent)
        .animation(.easeInOut(duration: 0.2), value: step)
    }

    private var otter: some View {
        let animation = ["wave", "idle", "listen", "listen", "talk", "happy"][min(step, 5)]
        return Group {
            if let image = try? SpriteSheet(character: app.character).frame(animation, 0) {
                Image(decorative: image, scale: 1).interpolation(.none).resizable().frame(width: 96, height: 96)
            }
        }
        .frame(width: 112, height: 112)
        .background(FlitchColors.accentBright.opacity(0.1), in: .rect(cornerRadius: 28))
        .accessibilityHidden(true)
    }

    // MARK: Steps

    private var hello: some View {
        VStack(spacing: 10) {
            Text("Hi, I'm Flitch").font(.largeTitle.bold())
            Text(
                "A little otter who lives in a corner of your screen. Hold a key, ask your question, and I answer out loud."
            )
            .multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
    }

    private var brain: some View {
        VStack(spacing: 10) {
            Text("Connect my brain").font(.title.bold())
            Text("Your sign-in stays in your Mac's Keychain.").foregroundStyle(.secondary).padding(.bottom, 6)
            if let label = app.connector.connectedLabel {
                Label(label, systemImage: "checkmark.circle.fill").foregroundStyle(FlitchColors.accent).font(.headline)
            }
            ConnectButton(title: "Continue with ChatGPT", subtitle: "Uses your Plus or Pro plan", prominent: true) {
                Task { if await app.connector.continueWithChatGPT() { step = 2 } }
            }
            ConnectButton(title: "Sign in with OpenRouter", subtitle: "One account for Claude, Gemini, Grok, Mistral…")
            {
                Task { if await app.connector.signInWithOpenRouter() { step = 2 } }
            }
            HStack(spacing: 18) {
                Button("I have an API key") { app.settingsWindow.show(tab: .brain) }
                Button("Use a local model") { app.settingsWindow.show(tab: .brain) }
            }
            .buttonStyle(.link).font(.callout)
            if app.connector.busy { ProgressView().controlSize(.small) }
            if let e = app.connector.errorMessage { Text(e).foregroundStyle(.red).font(.callout) }
        }
    }

    private var microphone: some View {
        VStack(spacing: 10) {
            Text("Can I hear you?").font(.title.bold())
            Text("I only listen while you hold the key. Your voice is transcribed on your Mac and nothing is recorded.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            if micGranted {
                Label("Microphone allowed", systemImage: "checkmark.circle.fill").foregroundStyle(FlitchColors.accent)
            }
        }
    }

    private var shortcut: some View {
        VStack(spacing: 12) {
            Text("Your talk key").font(.title.bold())
            Text(app.shortcutName)
                .font(.title2.weight(.semibold)).padding(.horizontal, 20).padding(.vertical, 10)
                .background(.quaternary, in: .rect(cornerRadius: 10))
            Text("Hold to talk, release to send. macOS will ask for “Input Monitoring”: I never read any other key.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Use ⌃⌥Space instead") {
                app.settings.useRightOption = false
                step = 4
            }
            .buttonStyle(.link).font(.callout)
        }
    }

    private var voice: some View {
        VStack(spacing: 10) {
            Text("Choose my voice").font(.title.bold())
            ForEach([FlitchSettings.VoiceEngine.animal, .apple], id: \.self) { engine in
                let info = VoiceCatalog.info(engine)
                HStack {
                    Image(systemName: app.settings.voiceEngine == engine ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(app.settings.voiceEngine == engine ? FlitchColors.accentBright : .secondary)
                    VStack(alignment: .leading) {
                        Text(info.name).fontWeight(.semibold)
                        Text(info.detail).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        app.preview.play(engine)
                    } label: {
                        Image(systemName: "play.fill")
                    }
                    .accessibilityLabel(Text("Test"))
                }
                .padding(12)
                .background(
                    .quaternary.opacity(app.settings.voiceEngine == engine ? 1 : 0.4), in: .rect(cornerRadius: 12)
                )
                .contentShape(Rectangle())
                .onTapGesture { app.settings.voiceEngine = engine }
            }
            Button("Premium voices (ElevenLabs, OpenAI…)") { app.settingsWindow.show(tab: .voice) }
                .buttonStyle(.link).font(.callout)
        }
    }

    private var tryIt: some View {
        VStack(spacing: 10) {
            Text(app.model.answer.isEmpty ? "It's ready!" : "Perfect!").font(.largeTitle.bold())
            Text(
                "Hold \(app.shortcutName) and ask me something, like “Tell me about Napoleon” or “What's in the news today?”"
            )
            .multilineTextAlignment(.center).foregroundStyle(.secondary)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(0..<steps, id: \.self) { i in
                    Capsule().fill(i <= step ? FlitchColors.accentBright : Color.secondary.opacity(0.3))
                        .frame(width: i == step ? 22 : 6, height: 6)
                }
            }
            .accessibilityHidden(true)
            Spacer()
            if step > 0 { Button("Back") { step -= 1 }.controlSize(.large) }
            Button(action: next) { Text(nextTitle).frame(minWidth: 90) }
                .buttonStyle(.borderedProminent).tint(FlitchColors.accent).controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(24)
    }

    private var nextTitle: LocalizedStringKey {
        switch step {
        case 0: "Start"
        case 2: micGranted ? "Continue" : "Allow the microphone"
        case 3: inputMonitoring || !app.settings.useRightOption ? "Continue" : "Allow"
        case 5: "Done"
        default: "Continue"
        }
    }

    private func next() {
        switch step {
        case 2 where !micGranted:
            Task {
                micGranted = (try? await AudioCapture.ensurePermission()) != nil
                if micGranted { step = 3 }
            }
        case 3 where app.settings.useRightOption && !inputMonitoring:
            inputMonitoring = HotkeyMonitor.requestInputMonitoring()
            app.restartHotkey()
            step = 4
        case 5:
            done()
        default:
            step += 1
        }
    }
}
