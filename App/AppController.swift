import AppKit
import FlitchCharacter
import FlitchCore
import FlitchProviders
import FlitchStage
import FlitchVoice
import Observation

/// Wires everything together: settings → providers and voices → orchestrator → stage.
@MainActor
final class AppController {
    let settings = FlitchSettings()
    let credentials = CredentialStore()
    let model = StageModel()
    let card = AnswerCard()
    let menu = StatusMenu()
    let hotkey = HotkeyMonitor()
    let voice = VoiceRouter()
    let character: LoadedCharacter
    private(set) var stage: PeekStage!
    private(set) var orchestrator: ConversationOrchestrator!
    private(set) var provider: (any LLMProvider)?
    private var timer: Timer?
    private var lastTick = Date()
    lazy var settingsWindow = SettingsWindow(app: self)
    lazy var connector = BrainConnector(app: self)
    lazy var preview = VoicePreview(app: self)
    lazy var onboarding = OnboardingWindow(app: self)

    /// First idle frame, for the settings header and onboarding.
    var iconImage: CGImage? { try? SpriteSheet(character: character).frame("idle", 0) }

    init() throws {
        let dir = Bundle.main.resourceURL!.appendingPathComponent("Characters/otter")
        character = try CharacterPackLoader.load(from: dir)
    }

    func start() throws {
        let sprites = try SpriteSheet(character: character)
        stage = PeekStage(model: model, sprites: sprites, presentation: presentation())
        let deps = ConversationOrchestrator.Dependencies(
            recognizer: AppleSpeechRecognizer { state in FlitchLog.info("speech assets: \(state)") },
            speech: voice,
            provider: { [weak self] in self?.provider },
            promptInput: { [weak self] in self?.promptInput() ?? PromptBuilder.Input(persona: "") },
            speed: { [weak self] in self?.settings.speed ?? .balanced },
            webSearch: { [weak self] in self?.settings.webSearch ?? false })
        orchestrator = ConversationOrchestrator(dependencies: deps)
        orchestrator.onEvent = { [weak self] event in self?.handle(event) }
        wireActions()
        model.setTimingsVisible(settings.showTimings)
        observeSettings()
        refreshProvider()
        refreshVoice()
        restartHotkey()
        startTimer()
    }

    // MARK: - Prompt

    func promptInput() -> PromptBuilder.Input {
        PromptBuilder.Input(
            persona: character.persona(settings.language), tone: settings.tone, language: settings.language,
            canSearchWeb: settings.webSearch && (provider?.capabilities.contains(.webSearch) ?? false))
    }

    // MARK: - Events

    private func handle(_ event: ConversationEvent) {
        model.apply(event)
        switch event {
        case .listening: menu.setState(.listening)
        case .sentence: menu.setState(.speaking)
        case .lingering, .dismissed, .error: menu.setState(.idle)
        default: break
        }
    }

    private func wireActions() {
        var actions = StageActions()
        actions.openAnswer = { [weak self] in self?.openAnswerCard() }
        actions.otterClicked = { [weak self] in self?.openAnswerCard() }
        actions.errorAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case .openSettings: settingsWindow.show(tab: .brain)
            case .openPrivacySettings:
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
            case .retry: orchestrator.retry()
            }
        }
        stage.actions = actions
        card.onClose = { [weak self] in self?.orchestrator.dismiss() }
        card.onReplay = { [weak self] text in
            guard let self else { return }
            let language = settings.language
            Task { try? await self.voice.say(text, language: language) }
        }
        menu.onTalk = { [weak self] in
            guard let self else { return }
            if orchestrator.phase == .listening { orchestrator.shortcutUp() } else { orchestrator.shortcutDown() }
        }
        menu.onSettings = { [weak self] in self?.settingsWindow.show(tab: .general) }
        menu.onAbout = {
            NSApp.activate()
            NSApp.orderFrontStandardAboutPanel(nil)
        }
        hotkey.onPress = { [weak self] in self?.orchestrator.shortcutDown() }
        hotkey.onRelease = { [weak self] in self?.orchestrator.shortcutUp() }
        hotkey.onCancel = { [weak self] in
            if self?.orchestrator.phase == .listening { self?.orchestrator.dismiss() }
        }
    }

    private func openAnswerCard() {
        guard !model.answer.isEmpty else { return }
        card.show(
            .init(
                question: model.question, answer: model.answer, citations: model.citations,
                providerName: provider?.displayName ?? ""))
    }

    // MARK: - Settings → engines

    private func observeSettings() {
        withObservationTracking {
            _ = (settings.providerID, settings.voiceEngine, settings.voiceIDs, settings.voiceSpeed)
            _ = (settings.corner, settings.useRightOption, settings.fallbackKeyCode, settings.fallbackModifiers)
            _ = settings.showTimings
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.refreshProvider()
                self.refreshVoice()
                self.restartHotkey()
                self.stage.update(presentation: self.presentation())
                self.model.setTimingsVisible(self.settings.showTimings)
                self.observeSettings()
            }
        }
    }

    func refreshProvider() {
        guard let id = settings.providerID else {
            provider = nil
            return
        }
        let store = credentials
        Task {
            let credential = try? await store.credential(for: id)
            provider = ProviderFactory.make(
                id: id, credential: credential,
                chatgptToken: {
                    guard
                        let c = try await store.validCredential(
                            for: ProviderFactory.chatgpt, refresh: { try await ChatGPTAuth().refresh($0) })
                    else { throw FlitchError.invalidCredentials(provider: "ChatGPT") }
                    return c.secret
                })
        }
    }

    func refreshVoice() {
        Task {
            voice.synthesizer = await VoiceFactory.make(
                engine: settings.voiceEngine, settings: settings, character: character, credentials: credentials)
        }
    }

    private func presentation() -> StagePresentation {
        StagePresentation(corner: settings.corner, shortcutName: shortcutName)
    }

    var shortcutName: String {
        if hotkey.activeMode == .rightOption || (hotkey.activeMode == nil && settings.useRightOption) {
            return String(localized: "right ⌥")
        }
        return KeyCombo(keyCode: UInt32(settings.fallbackKeyCode), modifiers: UInt32(settings.fallbackModifiers))
            .displayString
    }

    func restartHotkey() {
        let combo = KeyCombo(keyCode: UInt32(settings.fallbackKeyCode), modifiers: UInt32(settings.fallbackModifiers))
        hotkey.start(preferred: settings.useRightOption ? .rightOption : .combo(combo), fallback: combo)
        stage?.update(presentation: presentation())
    }

    // MARK: - Clock

    private func startTimer() {
        lastTick = Date()
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        let now = Date()
        let dt = min(0.1, now.timeIntervalSince(lastTick))
        lastTick = now
        orchestrator.tick(.milliseconds(Int(dt * 1000)))
        let hovered = stage.tick(dt) || model.hovered || card.isOpen
        orchestrator.setBubbleHovered(hovered)
    }
}

/// Builds the selected voice.
enum VoiceFactory {
    @MainActor
    static func make(
        engine: FlitchSettings.VoiceEngine, settings: FlitchSettings, character: LoadedCharacter,
        credentials: CredentialStore
    ) async -> any SentenceSynthesizer {
        let speed = settings.voiceSpeed
        let voiceID = settings.voiceID(for: engine)
        func key() async -> String? {
            guard let id = engine.credentialID else { return nil }
            return try? await credentials.credential(for: id)?.secret
        }
        switch engine {
        case .animal:
            return animal(character, speed: speed)
        case .apple:
            return AppleVoice(voiceIdentifier: voiceID, rate: Float(0.5 * speed).clamped(0.3, 0.65))
        case .elevenLabs:
            guard let k = await key() else { return animal(character, speed: speed) }
            return ElevenLabsVoice(apiKey: k, voiceID: voiceID ?? "21m00Tcm4TlvDq8ikWAM", speed: speed)
        case .openAI:
            guard let k = await key() else { return animal(character, speed: speed) }
            return OpenAIVoice(apiKey: k, voice: voiceID ?? "coral", speed: speed)
        case .cartesia:
            guard let k = await key() else { return animal(character, speed: speed) }
            var id = voiceID
            if id == nil {
                let all = (try? await CartesiaVoice.voices(apiKey: k)) ?? []
                id = (all.first { $0.language == settings.language.rawValue } ?? all.first)?.id
                if let id { settings.setVoiceID(id, for: .cartesia) }
            }
            guard let id else { return animal(character, speed: speed) }
            return CartesiaVoice(apiKey: k, voiceID: id)
        case .mistral:
            guard let k = await key() else { return animal(character, speed: speed) }
            return MistralVoice(apiKey: k, voiceID: voiceID ?? "gb_jane_neutral")
        case .gemini:
            guard let k = await key() else { return animal(character, speed: speed) }
            return GeminiVoice(apiKey: k, voice: voiceID ?? "Kore")
        }
    }

    static func animal(_ character: LoadedCharacter, speed: Double) -> AnimalVoice {
        var profile = AnimalVoiceProfile.otter
        if let a = character.pack.voice?.animal {
            profile = AnimalVoiceProfile(
                pitch: a.pitch, timbre: .init(rawValue: a.timbre) ?? .squeak, speed: a.speed, randomness: a.randomness)
        }
        profile.speed *= speed
        return AnimalVoice(profile: profile)
    }
}

extension Float {
    func clamped(_ lo: Float, _ hi: Float) -> Float { min(hi, max(lo, self)) }
}
