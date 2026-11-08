import FlitchCore
import FlitchMemory
import FlitchStage
import SwiftUI

/// About me + what Flitch has learned. Everything stays on this Mac.
struct MemoryPane: View {
    let app: AppController
    @Bindable var settings: FlitchSettings
    @State private var profile = UserProfile()
    @State private var memories: [Memory] = []
    @State private var newMemory = ""
    @State private var editing: Memory.ID?
    @State private var editText = ""
    @State private var confirmDeleteAll = false

    init(app: AppController) {
        self.app = app
        self.settings = app.settings
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $profile.name, prompt: Text("What should Flitch call you?"))
                TextField("City", text: $profile.city, prompt: Text("For the weather and local news"))
                TextField(
                    "About me", text: $profile.about, prompt: Text("Job, interests, how you like answers…"),
                    axis: .vertical
                )
                .lineLimit(3...6)
            } header: {
                Text("About me")
            } footer: {
                Text("Flitch reads this before every answer.").font(.caption).foregroundStyle(.secondary)
            }
            .onChange(of: profile) { _, p in saveProfile(p) }

            Section {
                Toggle("Learn from conversations", isOn: $settings.memoriesEnabled)
                Toggle("Ask before remembering", isOn: $settings.confirmMemories)
                    .disabled(!settings.memoriesEnabled)
            }

            Section {
                if memories.isEmpty {
                    Text("Nothing yet. Tell Flitch something about you, like “I support FC Barcelona”.")
                        .foregroundStyle(.secondary)
                }
                ForEach(memories) { m in row(m) }
                HStack {
                    TextField("Add a memory", text: $newMemory, prompt: Text("Add something to remember"))
                        .onSubmit(add)
                    Button("Add", action: add)
                        .disabled(newMemory.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("What Flitch remembers")
            } footer: {
                HStack {
                    Text("Pinned memories are always used.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Forget everything", role: .destructive) { confirmDeleteAll = true }
                        .disabled(memories.isEmpty)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(Text("Memory"))
        .task {
            profile = app.profile
            reload()
        }
        .confirmationDialog("Forget all memories?", isPresented: $confirmDeleteAll) {
            Button("Forget everything", role: .destructive) {
                try? app.memory?.deleteAllMemories()
                reload()
            }
        } message: {
            Text("This can't be undone.")
        }
        .overlay {
            if app.memory == nil {
                ContentUnavailableView("Memory is unavailable", systemImage: "exclamationmark.triangle")
            }
        }
    }

    @ViewBuilder private func row(_ m: Memory) -> some View {
        HStack(spacing: 10) {
            Button {
                try? app.memory?.updateMemory(m.id!, pinned: !m.pinned)
                reload()
            } label: {
                Image(systemName: m.pinned ? "pin.fill" : "pin").foregroundStyle(
                    m.pinned ? FlitchColors.accent : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(m.pinned ? "Unpin" : "Pin"))
            if editing == m.id {
                TextField("Memory", text: $editText).onSubmit { commitEdit(m) }
                Button("Save") { commitEdit(m) }
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(m.text)
                    Text(m.createdAt, format: .dateTime.day().month().year()).font(.caption).foregroundStyle(
                        .secondary)
                }
                Spacer()
                Button {
                    editing = m.id
                    editText = m.text
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Edit"))
                Button(role: .destructive) {
                    try? app.memory?.deleteMemory(m.id!)
                    reload()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Forget"))
            }
        }
    }

    private func add() {
        let text = newMemory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        try? app.memory?.addMemory(text, source: .user, status: .active)
        newMemory = ""
        reload()
    }

    private func commitEdit(_ m: Memory) {
        let text = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            try? app.memory?.deleteMemory(m.id!)
        } else {
            try? app.memory?.updateMemory(m.id!, text: text)
        }
        editing = nil
        reload()
    }

    private func saveProfile(_ p: UserProfile) {
        app.profile = p
        try? app.memory?.saveProfile(p)
    }

    private func reload() {
        memories = (try? app.memory?.memories()) ?? []
    }
}
