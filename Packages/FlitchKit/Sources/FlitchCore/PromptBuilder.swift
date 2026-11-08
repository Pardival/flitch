import Foundation

/// Assembles Flitch's system prompt.
///
/// Order: persona (from the character pack) → tone → spoken-style rules → what Flitch can do →
/// about the user (profile + memories, M4) → date, time zone and language.
public struct PromptBuilder: Sendable {
    public struct Input: Sendable {
        public var persona: String
        public var tone: TonePreset
        public var language: AppLanguage
        public var userName: String?
        public var city: String?
        public var profile: String?
        public var memories: [String]
        public var canSearchWeb: Bool
        /// The `remember` tool is offered.
        public var canRemember: Bool
        public var date: Date
        public var timeZone: TimeZone

        public init(
            persona: String, tone: TonePreset = .enthusiastic, language: AppLanguage = .english,
            userName: String? = nil, city: String? = nil, profile: String? = nil, memories: [String] = [],
            canSearchWeb: Bool = false, canRemember: Bool = false, date: Date = Date(), timeZone: TimeZone = .current
        ) {
            self.persona = persona
            self.tone = tone
            self.language = language
            self.userName = userName
            self.city = city
            self.profile = profile
            self.memories = memories
            self.canSearchWeb = canSearchWeb
            self.canRemember = canRemember
            self.date = date
            self.timeZone = timeZone
        }
    }

    public init() {}

    public func systemPrompt(_ input: Input) -> String {
        var sections: [String] = []
        sections.append(input.persona.trimmingCharacters(in: .whitespacesAndNewlines))

        sections.append("## Tone\n" + input.tone.instruction)

        sections.append(
            """
            ## How you answer
            Your answers are read aloud by a voice and shown in a small speech bubble.
            - Speak naturally, like in a conversation. Answer fully, but keep it as short as the question allows.
            - Plain text only: no markdown, no lists, no headings, no emoji, no links or URLs.
            - Write numbers, dates and symbols the way they are spoken when that sounds more natural.
            - Answer in the language the user speaks. If unsure, use \(input.language.englishName).
            - If you don't know or aren't sure, say so simply instead of guessing.
            """)

        sections.append(
            "## What you can do\n"
                + (input.canSearchWeb
                    ? "You can search the web: use it for news, weather, prices and anything recent."
                    : "You cannot browse the web. For recent events, say your knowledge may be out of date.")
                + " You cannot act on the computer yet (open apps, send messages…): say so kindly if asked."
                + (input.canRemember
                    ? " When the user shares a lasting personal fact, call the remember tool, then answer as usual."
                    : ""))

        var about: [String] = []
        if let name = input.userName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            about.append("Their name is \(name).")
        }
        if let city = input.city?.trimmingCharacters(in: .whitespacesAndNewlines), !city.isEmpty {
            about.append("They live in \(city).")
        }
        if let profile = input.profile?.trimmingCharacters(in: .whitespacesAndNewlines), !profile.isEmpty {
            about.append(profile)
        }
        if !input.memories.isEmpty {
            about.append("Things you remember about them:\n" + input.memories.map { "- \($0)" }.joined(separator: "\n"))
        }
        if !about.isEmpty {
            sections.append("## About the user\n" + about.joined(separator: "\n"))
        }

        sections.append(
            """
            ## Context
            Today is \(Self.dateString(input.date, timeZone: input.timeZone)) (time zone \(input.timeZone.identifier)).
            The user's interface language is \(input.language.englishName).
            """)

        return sections.joined(separator: "\n\n")
    }

    static func dateString(_ date: Date, timeZone: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "EEEE d MMMM yyyy, HH:mm"
        return f.string(from: date)
    }
}
