import CoreGraphics
import FlitchCore
import Foundation
import Observation

/// What the otter and the bubble show, derived from the orchestrator's events. Pure state, tested.
@MainActor
@Observable
public final class StageModel {
    public enum Bubble: Equatable, Sendable {
        case none
        case listening(transcript: String)
        case thinking
        case speaking(spoken: String, current: String)
        case lingering(text: String, progress: Double)
        case error(FlitchError)
    }

    /// What to offer next to an error.
    public enum ErrorAction: Equatable, Sendable {
        case openSettings
        case openPrivacySettings
        case retry
    }

    public private(set) var visible = false
    public private(set) var bubble: Bubble = .none
    public private(set) var animation = "idle"
    public private(set) var microphoneLevel: Float = 0
    public private(set) var speakingLevel: Float = 0
    public private(set) var question = ""
    public private(set) var answer = ""
    public private(set) var citations: [Citation] = []
    public var hovered = false
    /// Driven by the stage at display rate.
    public var frameIndex = 0
    public var shownRows = 0
    /// Where the otter and bubble are inside the panel (SwiftUI coordinates), for click-through.
    public var otterFrame: CGRect = .zero
    public var bubbleFrame: CGRect = .zero
    /// Turn timings shown when "show timings" is on (latency work).
    public private(set) var timings: [String] = []

    private var spokenSentences: [String] = []
    private var lingerTotal: Duration = .seconds(15)

    public init() {}

    public func apply(_ event: ConversationEvent) {
        switch event {
        case .listening:
            visible = true
            question = ""
            citations = []
            bubble = .listening(transcript: "")
            animation = "listen"
        case .partialTranscript(let t):
            bubble = .listening(transcript: t)
        case .microphoneLevel(let l):
            microphoneLevel = l
        case .transcribing:
            animation = "think"
        case .transcribed(let q):
            question = q
        case .thinking:
            bubble = .thinking
            animation = "think"
            spokenSentences = []
            answer = ""
        case .citation(let c):
            if !citations.contains(c) { citations.append(c) }
        case .sentence(let s):
            spokenSentences.append(s)
            bubble = .speaking(spoken: spokenSentences.dropLast().joined(separator: " "), current: s)
            animation = "talk"
        case .speakingLevel(let l):
            speakingLevel = l
        case .answerComplete(let a):
            answer = a
            speakingLevel = 0
        case .lingering(let remaining):
            if case .lingering = bubble {
            } else if case .error = bubble {
            } else {
                lingerTotal = max(remaining, .milliseconds(1))
                animation = "happy"
            }
            if case .error = bubble { return }
            let progress = max(0, min(1, remaining / lingerTotal))
            bubble = .lingering(
                text: answer.isEmpty ? spokenSentences.joined(separator: " ") : answer, progress: progress)
        case .timings(let t):
            lastTimings = t.summary
        case .error(let e):
            bubble = .error(e)
            animation = "idle"
            speakingLevel = 0
        case .dismissed:
            visible = false
            bubble = .none
            animation = "idle"
            microphoneLevel = 0
            speakingLevel = 0
            hovered = false
        }
    }

    /// Shows or hides the latency line (Settings › show timings).
    public func setTimingsVisible(_ visible: Bool) { timingsVisible = visible }
    private var timingsVisible = false
    private var lastTimings: [String] = [] {
        didSet { timings = timingsVisible ? lastTimings : [] }
    }

    /// The next step to offer for an error.
    public static func action(for error: FlitchError) -> ErrorAction? {
        switch error {
        case .noProvider, .invalidCredentials: .openSettings
        case .microphoneDenied: .openPrivacySettings
        case .offline, .rateLimited, .other: .retry
        case .nothingHeard: nil
        }
    }
}
