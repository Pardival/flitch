import FlitchCore
import FlitchProviders
import FlitchStage
import SwiftUI

struct BrainPane: View {
    let connector: BrainConnector
    @Bindable var settings: FlitchSettings
    @State private var keySheet: BrainConnector.KeyProvider?
    @State private var showLocal = false

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
                TextField("Custom model", text: $settings.customModel, prompt: Text("Automatic"))
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
