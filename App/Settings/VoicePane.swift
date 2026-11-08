import FlitchCore
import FlitchStage
import FlitchVoice
import SwiftUI

struct VoicePane: View {
    let app: AppController
    @Bindable var settings: FlitchSettings
    @State private var keyEngine: FlitchSettings.VoiceEngine?
    @State private var designError: String?
    @State private var pendingSpeechEngine: FlitchSettings.SpeechEngine?

    init(app: AppController) {
        self.app = app
        self.settings = app.settings
    }

    var body: some View {
        Form {
            Section {
                ForEach(VoiceCatalog.engines, id: \.engine) { info in
                    VoiceRow(
                        info: info, selected: settings.voiceEngine == info.engine,
                        hasKey: app.preview.hasKey(info.engine),
                        playing: app.preview.playing == info.engine,
                        select: {
                            if info.engine.needsKey && !app.preview.hasKey(info.engine) {
                                keyEngine = info.engine
                            } else {
                                settings.voiceEngine = info.engine
                            }
                        },
                        test: { app.preview.play(info.engine) },
                        addKey: { keyEngine = info.engine })
                }
            } footer: {
                Text("Premium voices use your own account with the voice provider.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                if settings.voiceEngine == .apple {
                    Picker("Apple voice", selection: appleVoice) {
                        Text("Best available").tag("")
                        ForEach(AppleVoice.voices(for: settings.language), id: \.identifier) { v in
                            Text(verbatim: "\(v.name) (\(v.language))\(v.quality >= 2 ? " ★" : "")").tag(v.identifier)
                        }
                    }
                    if AppleVoice.shouldSuggestBetterVoices(for: settings.language) {
                        Link(destination: AppleVoice.downloadVoicesURL) { Text("Download better voices…") }
                    }
                }
                if !voices.isEmpty {
                    Picker("Voice", selection: cloudVoice) {
                        ForEach(voices, id: \.id) { v in Text(verbatim: v.name).tag(v.id) }
                    }
                }
                if settings.voiceEngine == .elevenLabs {
                    Button {
                        Task { designError = await app.preview.createSignatureVoice() }
                    } label: {
                        if app.preview.designing {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Create Flitch's signature voice", systemImage: "wand.and.stars")
                        }
                    }
                    .disabled(app.preview.designing)
                    if let designError { Text(designError).foregroundStyle(.red).font(.callout) }
                }
                LabeledContent("Speed") {
                    HStack {
                        Image(systemName: "tortoise").foregroundStyle(.secondary)
                        Slider(value: $settings.voiceSpeed, in: 0.6...1.6, step: 0.1).frame(width: 200)
                        Image(systemName: "hare").foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Picker("Transcription", selection: speechEngine) {
                    Text("On this Mac (private)").tag(FlitchSettings.SpeechEngine.apple)
                    Text(verbatim: "OpenAI").tag(FlitchSettings.SpeechEngine.openAI)
                    Text(verbatim: "Mistral").tag(FlitchSettings.SpeechEngine.mistral)
                }
            } header: {
                Text("Hearing you")
            } footer: {
                Text(
                    settings.speechEngine == .apple
                        ? "Your voice never leaves your Mac."
                        : "Your question is sent to \(settings.speechEngine == .openAI ? "OpenAI" : "Mistral") when you release the key. Nothing is kept on your Mac."
                )
                .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(Text("Voice"))
        .sheet(item: $keyEngine, onDismiss: applyPendingSpeechEngine) { engine in
            VoiceKeySheet(engine: engine, app: app, selectsVoice: pendingSpeechEngine == nil)
        }
        .task(id: settings.voiceEngine) { await app.preview.loadVoices(settings.voiceEngine) }
    }

    /// Picking a cloud engine without a key asks for the key first (shared with that provider's voice).
    private var speechEngine: Binding<FlitchSettings.SpeechEngine> {
        Binding(
            get: { settings.speechEngine },
            set: { engine in
                let voiceEngine: FlitchSettings.VoiceEngine? =
                    switch engine {
                    case .apple: nil
                    case .openAI: .openAI
                    case .mistral: .mistral
                    }
                if let voiceEngine, !app.preview.hasKey(voiceEngine) {
                    pendingSpeechEngine = engine
                    keyEngine = voiceEngine
                } else {
                    settings.speechEngine = engine
                }
            })
    }

    private var appleVoice: Binding<String> {
        Binding(
            get: { settings.voiceID(for: .apple) ?? "" },
            set: { settings.setVoiceID($0.isEmpty ? nil : $0, for: .apple) })
    }

    private func applyPendingSpeechEngine() {
        guard let engine = pendingSpeechEngine else { return }
        pendingSpeechEngine = nil
        if let id = engine.credentialID, app.preview.hasKey(id == "openai" ? .openAI : .mistral) {
            settings.speechEngine = engine
        }
    }

    private var voices: [VoiceCatalog.Voice] {
        if let fetched = app.preview.cloudVoices[settings.voiceEngine] {
            return fetched.map { VoiceCatalog.Voice(id: $0.id, name: $0.name) }
        }
        return VoiceCatalog.voices[settings.voiceEngine] ?? []
    }

    private var cloudVoice: Binding<String> {
        let engine = settings.voiceEngine
        let first = voices.first?.id ?? ""
        return Binding(
            get: { settings.voiceID(for: engine) ?? first },
            set: { settings.setVoiceID($0, for: engine) })
    }
}

extension FlitchSettings.VoiceEngine: @retroactive Identifiable {
    public var id: String { rawValue }
}

struct VoiceRow: View {
    let info: VoiceCatalog.EngineInfo
    let selected: Bool
    let hasKey: Bool
    let playing: Bool
    let select: () -> Void
    let test: () -> Void
    let addKey: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: select) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.title3).foregroundStyle(selected ? FlitchColors.accentBright : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(info.name))
            VStack(alignment: .leading, spacing: 2) {
                Text(info.name).fontWeight(.medium)
                Text(info.detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if info.engine.needsKey && !hasKey {
                Button("Add key", action: addKey).controlSize(.small)
            } else {
                Button(action: test) {
                    Label(playing ? "Playing…" : "Test", systemImage: playing ? "speaker.wave.2.fill" : "play.fill")
                }
                .controlSize(.small)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
    }
}

struct VoiceKeySheet: View {
    let engine: FlitchSettings.VoiceEngine
    let app: AppController
    /// Saving the key also switches to this voice (not when the key is for transcription).
    var selectsVoice = true
    @State private var key = ""
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let info = VoiceCatalog.info(engine)
        VStack(alignment: .leading, spacing: 14) {
            Text("\(info.name) API key").font(.title3.weight(.semibold))
            Text("Stored in your Mac's Keychain. It is only sent to \(info.name).").font(.callout).foregroundStyle(
                .secondary)
            SecureField("Paste your key", text: $key).textFieldStyle(.roundedBorder)
            if let url = info.keyURL { Link(destination: url) { Text("Get a key") }.font(.callout) }
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    Task {
                        if let e = await app.preview.saveKey(key, for: engine) {
                            error = e
                        } else {
                            if selectsVoice { app.settings.voiceEngine = engine }
                            dismiss()
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20).frame(width: 420)
    }
}
