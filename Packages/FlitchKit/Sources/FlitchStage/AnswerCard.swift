import AppKit
import FlitchCore
import SwiftUI

/// The full answer, opened by clicking the bubble: copy, replay, sources.
@MainActor
public final class AnswerCard {
    public struct Content: Equatable {
        public var question: String
        public var answer: String
        public var citations: [Citation]
        public var providerName: String
        public init(question: String, answer: String, citations: [Citation], providerName: String) {
            self.question = question
            self.answer = answer
            self.citations = citations
            self.providerName = providerName
        }
    }

    public var onReplay: (String) -> Void = { _ in }
    public var onClose: () -> Void = {}
    private var panel: NSPanel?

    public init() {}

    public var isOpen: Bool { panel?.isVisible == true }

    public func show(_ content: Content, near anchor: CGPoint? = nil) {
        close(notify: false)
        let view = AnswerCardView(
            content: content,
            onReplay: { [weak self] in self?.onReplay(content.answer) },
            onClose: { [weak self] in self?.close(notify: true) })
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 420),
            styleMask: [.titled, .closable, .fullSizeContentView, .utilityWindow],
            backing: .buffered, defer: false)
        p.titlebarAppearsTransparent = true
        p.titleVisibility = .hidden
        p.isMovableByWindowBackground = true
        p.level = .floating
        p.isReleasedWhenClosed = false
        p.contentView = NSHostingView(rootView: view)
        if let anchor { p.setFrameTopLeftPoint(anchor) } else { p.center() }
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: p, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.panelClosed() } }
        panel = p
        NSApp.activate()
        p.makeKeyAndOrderFront(nil)
    }

    public func close(notify: Bool = true) {
        guard let panel else { return }
        self.panel = nil
        panel.close()
        if notify { onClose() }
    }

    private func panelClosed() {
        if panel != nil {
            panel = nil
            onClose()
        }
    }
}

struct AnswerCardView: View {
    let content: AnswerCard.Content
    let onReplay: () -> Void
    let onClose: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("You asked", bundle: .module).font(.caption).foregroundStyle(.secondary)
                Text(content.question).font(.title3.weight(.semibold))
            }
            .padding(.horizontal, 20).padding(.top, 28).padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(content.answer).font(.body).lineSpacing(4).textSelection(.enabled)
                    if !content.citations.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Sources", bundle: .module).font(.caption.weight(.semibold)).foregroundStyle(
                                .secondary)
                            ForEach(content.citations, id: \.url) { c in
                                Link(destination: c.url) {
                                    Label(c.title, systemImage: "link").lineLimit(1)
                                }
                                .font(.callout)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20).padding(.bottom, 16)
            }

            Divider()
            HStack(spacing: 8) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(content.answer, forType: .string)
                    copied = true
                } label: {
                    copied ? Text("Copied", bundle: .module) : Text("Copy", bundle: .module)
                }
                .buttonStyle(.borderedProminent).tint(FlitchColors.accent)
                Button(action: onReplay) {
                    Label {
                        Text("Replay", bundle: .module)
                    } icon: {
                        Image(systemName: "speaker.wave.2")
                    }
                }
                Spacer()
                Text(content.providerName).font(.caption).foregroundStyle(.secondary)
                Button(action: onClose) { Text("Close", bundle: .module) }.keyboardShortcut(.cancelAction)
            }
            .controlSize(.regular)
            .padding(.horizontal, 20).padding(.vertical, 14)
        }
        .frame(minWidth: 420, idealWidth: 460, minHeight: 300, idealHeight: 420)
    }
}
