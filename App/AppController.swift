import AVFoundation
import AppKit
import FlitchCharacter
import FlitchCore
import FlitchMemory
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
    let recognizer = RecognizerRouter(AppController.appleRecognizer())
    let character: LoadedCharacter
    /// History, profile and memories (nil only if the database can't be opened).
    let memory: MemoryStore?
    /// Cached "About me", saved by settings › Memory.
    var profile = UserProfile()
    private var conversationStartedAt = Date()
    private(set) var stage: (any Stage)!
    private var stageMode: FlitchSettings.Mode?
    private(set) var orchestrator: ConversationOrchestrator!
    private(set) var provider: (any LLMProvider)?
    private var timer: Timer?
    private var lastTick = Date()
    lazy var settingsWindow = SettingsWindow(app: self)
    lazy var connector = BrainConnector(app: self)
    lazy var preview = VoicePreview(app: self)
    lazy var onboarding = OnboardingWindow(app: self)
    let updater = Updater()

    /// First idle frame, for the settings header and onboarding.
    var iconImage: CGImage? { try? SpriteSheet(character: character).frame("idle", 0) }

    init() throws {
        let dir = Bundle.main.resourceURL!.appendingPathComponent("Characters/otter")
        character = try CharacterPackLoader.load(from: dir)
        do {
            memory = try MemoryStore.openDefault()
        } catch {
            FlitchLog.error(FlitchError.other("memory database: \(error.localizedDescription)"))
            memory = nil
        }
        profile = (try? memory?.profile()) ?? UserProfile()
    }

    func start() throws {
        try makeStage()
        let deps = ConversationOrchestrator.Dependencies(
            recognizer: recognizer,
            speech: voice,
            provider: { [weak self] in self?.provider },
            promptInput: { [weak self] in self?.promptInput() ?? PromptBuilder.Input(persona: "") },
            speed: { [weak self] in self?.settings.speed ?? .balanced },
            webSearch: { [weak self] in self?.settings.webSearch ?? false },
            tools: { [weak self] in
                guard let self, self.memory != nil, self.settings.memoriesEnabled else { return [] }
                return [RememberTool.spec]
            })
        orchestrator = ConversationOrchestrator(dependencies: deps)
        orchestrator.onEvent = { [weak self] event in self?.handle(event) }
        orchestrator.onConversationClosed = { [weak self] messages in self?.saveConversation(messages) }
        orchestrator.onToolCall = { [weak self] call in self?.handleToolCall(call) }
        applyRetention()
        wireActions()
        model.setTimingsVisible(settings.showTimings)
        observeSettings()
        refreshProvider()
        refreshVoice()
        refreshRecognizer()
        restartHotkey()
        startTimer()
    }

    // MARK: - Prompt

    func promptInput() -> PromptBuilder.Input {
        let question = orchestrator?.conversation.last(where: { $0.role == .user })?.text ?? ""
        let memories =
            settings.memoriesEnabled ? ((try? memory?.relevantMemories(for: question)) ?? []) : []
        return PromptBuilder.Input(
            persona: character.persona(settings.language), tone: settings.tone, language: settings.language,
            userName: profile.name, city: profile.city, profile: profile.about, memories: memories,
            canSearchWeb: settings.webSearch && (provider?.capabilities.contains(.webSearch) ?? false),
            canRemember: memory != nil && settings.memoriesEnabled
                && (provider?.capabilities.contains(.tools) ?? false))
    }

    // MARK: - Learned memories

    private func handleToolCall(_ call: ToolCall) {
        guard let fact = RememberTool.fact(from: call), let memory, settings.memoriesEnabled else { return }
        let confirm = settings.confirmMemories
        guard let saved = try? memory.addMemory(fact, status: confirm ? .pending : .active), let id = saved.id
        else { return }
        if saved.status == .active && confirm { return }  // already known
        model.showMemory(.init(id: id, fact: saved.text, pending: confirm))
    }

    private func answerMemory(_ chip: StageModel.MemoryChip, keep: Bool) {
        if keep {
            try? memory?.confirmMemory(chip.id)
        } else {
            try? memory?.deleteMemory(chip.id)
        }
        model.clearMemory()
    }

    // MARK: - History

    private func saveConversation(_ messages: [ChatMessage]) {
        guard settings.historyRetention != .off, let memory else { return }
        let started = conversationStartedAt
        let providerID = settings.providerID
        let model = settings.customModel.isEmpty ? nil : settings.customModel
        Task.detached {
            try? memory.saveConversation(messages, startedAt: started, providerID: providerID, model: model)
        }
        applyRetention()
    }

    func applyRetention() {
        guard let memory else { return }
        let retention = settings.historyRetention
        Task.detached { try? memory.applyRetention(retention) }
    }

    // MARK: - Events

    private func handle(_ event: ConversationEvent) {
        model.apply(event)
        switch event {
        case .listening:
            if orchestrator.conversation.isEmpty { conversationStartedAt = Date() }
            menu.setState(.listening)
        case .sentence: menu.setState(.speaking)
        case .lingering, .dismissed, .error: menu.setState(.idle)
        default: break
        }
    }

    /// Corner peek or Dock walker, from the settings.
    private func makeStage() throws {
        guard stageMode != settings.mode else { return }
        stage?.tearDown()
        let sprites = try SpriteSheet(character: character)
        stage =
            settings.mode == .dock
            ? DockStage(model: model, sprites: sprites, presentation: presentation())
            : PeekStage(model: model, sprites: sprites, presentation: presentation())
        stageMode = settings.mode
        if orchestrator != nil { wireActions() }
    }

    private func otterClicked() {
        guard settings.mode == .dock else { return openAnswerCard() }
        // on the Dock, clicking her is the way to talk (click, speak, click to send)
        switch orchestrator.phase {
        case .listening: orchestrator.shortcutUp()
        case .lingering where !model.answer.isEmpty: openAnswerCard()
        default: orchestrator.shortcutDown()
        }
    }

    private func wireActions() {
        var actions = StageActions()
        actions.openAnswer = { [weak self] in self?.openAnswerCard() }
        actions.otterClicked = { [weak self] in self?.otterClicked() }
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
        actions.answerMemory = { [weak self] chip, keep in self?.answerMemory(chip, keep: keep) }
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
            _ = (settings.showTimings, settings.speechEngine, settings.historyRetention, settings.mode)
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.refreshProvider()
                self.refreshVoice()
                self.refreshRecognizer()
                self.applyRetention()
                try? self.makeStage()
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

    static func appleRecognizer() -> AppleSpeechRecognizer {
        AppleSpeechRecognizer { state in FlitchLog.info("speech assets: \(state)") }
    }

    /// Cloud transcription when chosen and a key is saved; on-device otherwise.
    func refreshRecognizer() {
        let engine = settings.speechEngine
        let language = settings.language
        let router = recognizer
        let store = credentials
        Task {
            let service: CloudSpeechRecognizer.Service? =
                switch engine {
                case .apple: nil
                case .openAI: .openAI
                case .mistral: .mistral
                }
            if let service, let id = engine.credentialID, let key = try? await store.credential(for: id)?.secret {
                router.recognizer = CloudSpeechRecognizer(service: service, apiKey: key)
            } else {
                let apple = Self.appleRecognizer()
                router.recognizer = apple
                await apple.prepare(language: language)
            }
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
        let mode = hotkey.start(preferred: settings.useRightOption ? .rightOption : .combo(combo), fallback: combo)
        FlitchLog.info(
            "hotkey: \(mode.map { "\($0)" } ?? "none"), input monitoring: \(HotkeyMonitor.inputMonitoringGranted), "
                + "microphone: \(AVCaptureDevice.authorizationStatus(for: .audio).rawValue), "
                + "provider: \(settings.providerID ?? "none"), mode: \(settings.mode)")
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
