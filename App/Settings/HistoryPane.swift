import FlitchCore
import FlitchMemory
import FlitchStage
import SwiftUI

/// Past conversations, searchable, with the retention setting.
struct HistoryPane: View {
    let app: AppController
    @Bindable var settings: FlitchSettings
    @State private var search = ""
    @State private var conversations: [ConversationRecord] = []
    @State private var selected: ConversationRecord?
    @State private var confirmDeleteAll = false

    init(app: AppController) {
        self.app = app
        self.settings = app.settings
    }

    var body: some View {
        Form {
            Section {
                Picker("Keep conversations", selection: $settings.historyRetention) {
                    Text("For 90 days").tag(HistoryRetention.days90)
                    Text("For 1 year").tag(HistoryRetention.year)
                    Text("Forever").tag(HistoryRetention.forever)
                    Text("Don't keep").tag(HistoryRetention.off)
                }
            } footer: {
                Text("Stored only on this Mac.").font(.caption).foregroundStyle(.secondary)
            }

            Section {
                if conversations.isEmpty {
                    Text(search.isEmpty ? "No conversations yet." : "No results.").foregroundStyle(.secondary)
                }
                ForEach(conversations) { c in
                    Button {
                        selected = c
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.title).lineLimit(1)
                                Text(c.startedAt, format: .dateTime.weekday().day().month().hour().minute())
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Delete", role: .destructive) { delete(c) }
                    }
                }
            } header: {
                Text("Conversations")
            } footer: {
                HStack {
                    Spacer()
                    Button("Delete history", role: .destructive) { confirmDeleteAll = true }
                        .disabled(conversations.isEmpty && search.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(Text("History"))
        .searchable(text: $search, placement: .toolbar, prompt: Text("Search conversations"))
        .task(id: search) { reload() }
        .onChange(of: settings.historyRetention) { reload() }
        .sheet(item: $selected) { c in
            ConversationSheet(app: app, conversation: c) {
                delete(c)
                selected = nil
            }
        }
        .confirmationDialog("Delete all conversations?", isPresented: $confirmDeleteAll) {
            Button("Delete history", role: .destructive) {
                try? app.memory?.deleteAllHistory()
                reload()
            }
        } message: {
            Text("This can't be undone.")
        }
    }

    private func delete(_ c: ConversationRecord) {
        if let id = c.id { try? app.memory?.deleteConversation(id) }
        reload()
    }

    private func reload() {
        let q = search.trimmingCharacters(in: .whitespaces)
        // retention runs in the background: give it a moment before reading
        conversations = (try? app.memory?.conversations(search: q.isEmpty ? nil : q)) ?? []
    }
}

struct ConversationSheet: View {
    let app: AppController
    let conversation: ConversationRecord
    let delete: () -> Void
    @State private var messages: [MessageRecord] = []
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(conversation.startedAt, format: .dateTime.weekday(.wide).day().month(.wide).hour().minute())
                    .font(.headline)
                Spacer()
                Button("Delete", role: .destructive, action: delete)
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(messages) { m in
                        let user = m.role == ChatMessage.Role.user.rawValue
                        HStack {
                            if user { Spacer(minLength: 60) }
                            Text(m.text)
                                .textSelection(.enabled)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(
                                    user
                                        ? AnyShapeStyle(FlitchColors.accent.opacity(0.18)) : AnyShapeStyle(.quaternary),
                                    in: .rect(cornerRadius: 12))
                            if !user { Spacer(minLength: 60) }
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 520, height: 480)
        .task { messages = (conversation.id.flatMap { try? app.memory?.messages(in: $0) }) ?? [] }
    }
}
