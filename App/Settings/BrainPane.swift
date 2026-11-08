import FlitchCore
import FlitchProviders
import FlitchStage
import SwiftUI

struct BrainPane: View {
    let connector: BrainConnector
    @Bindable var settings: FlitchSettings
    @State private var keySheet: BrainConnector.KeyProvider?
    @State private var showLocal = false
    @State private var models: [ModelInfo] = []
    @State private var loadingModels = false
    @State private var typingModel = false
    let loadModels: () async -> [ModelInfo]

    init(connector: BrainConnector, settings: FlitchSettings, loadModels: @escaping () async -> [ModelInfo]) {
        self.connector = connector
        self.settings = settings
        self.loadModels = loadModels
    }

    private var capabilities: ProviderCapabilities {
        guard let id = settings.providerID else { return [] }
        return switch id {
        case ProviderFactory.anthropic: [.webSearch, .tools]
        case ProviderFactory.openai: [.webSearch, .tools]
        case ProviderFactory.chatgpt: [.tools]
        default: ProviderCatalog.preset(id)?.providerCapabilities ?? []
        }
    }

    var body: some View {
        Form {
            Section {
                if let label = connector.connectedLabel {
                    LabeledContent {
                        Button("Sign out") { Task { await connector.signOut() } }
                    } label: {
                        Label {
                            Text(label).fontWeight(.semibold)
                            Text("Connected").font(.caption).foregroundStyle(FlitchColors.accent)
                        } icon: {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(FlitchColors.accent)
                        }
                    }
                } else {
                    Text("Flitch has no brain yet. Connect an AI below.").foregroundStyle(.secondary)
                }
                Picker("Answers", selection: $settings.speed) {
                    Text("Fast").tag(ResponseSpeed.fast)
                    Text("Balanced").tag(ResponseSpeed.balanced)
                    Text("Precise").tag(ResponseSpeed.precise)
                }
                .pickerStyle(.segmented)
                modelPicker
                Toggle(isOn: $settings.webSearch) {
                    Text("Search the web")
                    Text(
                        capabilities.contains(.webSearch)
                            ? "For news and recent facts." : "This brain can't search the web."
                    )
                    .font(.caption).foregroundStyle(.secondary)
                }
                .disabled(!capabilities.contains(.webSearch))
            }

            Section("Connect a brain") {
                ConnectButton(title: "Continue with ChatGPT", subtitle: "Uses your Plus or Pro plan", prominent: true) {
                    Task { await connector.continueWithChatGPT() }
                }
                ConnectButton(
                    title: "Sign in with OpenRouter", subtitle: "One account for Claude, Gemini, Grok, Mistral…"
                ) {
                    Task { await connector.signInWithOpenRouter() }
                }
                ForEach(BrainConnector.keyProviders) { p in
                    Button {
                        keySheet = p
                    } label: {
                        LabeledContent(p.name) { Text("API key").foregroundStyle(.secondary) }
                    }
                    .buttonStyle(.plain)
                }
                ForEach(BrainConnector.localProviders) { preset in
                    Button {
                        Task { await connector.useLocal(preset) }
                    } label: {
                        LabeledContent(preset.name) { Text("On this Mac").foregroundStyle(.secondary) }
                    }
                    .buttonStyle(.plain)
                }
                if connector.busy { ProgressView().controlSize(.small) }
                if let error = connector.errorMessage {
                    Text(error).foregroundStyle(.red).font(.callout)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(Text("Brain"))
        .sheet(item: $keySheet) { p in APIKeySheet(provider: p, connector: connector) }
        .task(id: "\(settings.providerID ?? "")|\(connector.connectedLabel ?? "")") { await reloadModels() }
    }

    private static let otherTag = "\u{0}other"

    @ViewBuilder private var modelPicker: some View {
        Picker(selection: modelSelection) {
            Text("Automatic").tag("")
            if !models.isEmpty { Divider() }
            ForEach(models, id: \.id) { m in Text(verbatim: "\(m.name)  ·  \(m.cost.label)").tag(m.id) }
            if !settings.customModel.isEmpty, !models.contains(where: { $0.id == settings.customModel }) {
                Text(verbatim: settings.customModel).tag(settings.customModel)
            }
            Divider()
            Text("Other…").tag(Self.otherTag)
        } label: {
            Text("Model")
            Text(modelCaption).font(.caption).foregroundStyle(.secondary)
        }
        .disabled(settings.providerID == nil)
        if typingModel {
            TextField("Model name", text: $settings.customModel, prompt: Text(verbatim: "gpt-5.1"))
                .onSubmit { typingModel = false }
        }
    }

    private var modelCaption: String {
        if loadingModels { return String(localized: "Loading the models…") }
        if settings.customModel.isEmpty { return String(localized: "Flitch picks a recent model for the speed above.") }
        let cheapest = models.min { $0.cost < $1.cost }
        let selected = models.first { $0.id == settings.customModel }
        var parts = [selected.map { String(localized: "Price: \($0.cost.label).") } ?? ""]
        if let cheapest, let selected, cheapest.cost < selected.cost {
            parts.append(String(localized: "Cheapest: \(cheapest.name)."))
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " ")
    }

    private var modelSelection: Binding<String> {
        Binding(
            get: { typingModel ? Self.otherTag : settings.customModel },
            set: { value in
                if value == Self.otherTag {
                    typingModel = true
                } else {
                    typingModel = false
                    settings.customModel = value
                }
            })
    }

    private func reloadModels() async {
        guard settings.providerID != nil else {
            models = []
            return
        }
        loadingModels = true
        models = await loadModels()  // in the provider's order (newest first for OpenAI)
        loadingModels = false
    }
}

struct ConnectButton: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                Text(subtitle).font(.caption).foregroundStyle(prominent ? .white.opacity(0.9) : .secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6).padding(.horizontal, 10)
            .foregroundStyle(prominent ? .white : .primary)
            .background(
                prominent ? AnyShapeStyle(FlitchColors.accent) : AnyShapeStyle(.quaternary), in: .rect(cornerRadius: 10)
            )
        }
        .buttonStyle(.plain)
    }
}

struct APIKeySheet: View {
    let provider: BrainConnector.KeyProvider
    let connector: BrainConnector
    @State private var key = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(provider.name) API key").font(.title3.weight(.semibold))
            Text("Your key is checked, then stored in your Mac's Keychain. It is only sent to \(provider.name).")
                .font(.callout).foregroundStyle(.secondary)
            SecureField("Paste your key", text: $key).textFieldStyle(.roundedBorder)
            Link(destination: provider.keyURL) { Text("Get a key") }.font(.callout)
            if let e = connector.errorMessage { Text(e).foregroundStyle(.red).font(.callout) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button {
                    Task { if await connector.saveKey(key, for: provider.id) { dismiss() } }
                } label: {
                    if connector.busy { ProgressView().controlSize(.small) } else { Text("Test and save") }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty || connector.busy)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

extension CostTier {
    /// Indicative only: prices change, the provider's pricing page is the reference.
    var label: String {
        switch self {
        case .veryCheap: String(localized: "very cheap")
        case .cheap: String(localized: "cheap")
        case .medium: String(localized: "mid-priced")
        case .expensive: String(localized: "expensive")
        }
    }
}
