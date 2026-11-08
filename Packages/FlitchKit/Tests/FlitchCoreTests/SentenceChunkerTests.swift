import Testing

@testable import FlitchCore

struct SentenceChunkerTests {
    /// Feeds `text` one character at a time (worst case for streaming) and collects every sentence.
    static func chunk(_ text: String, step: Int = 1) -> [String] {
        var c = SentenceChunker()
        var out: [String] = []
        var i = text.startIndex
        while i < text.endIndex {
            let j = text.index(i, offsetBy: step, limitedBy: text.endIndex) ?? text.endIndex
            out += c.feed(String(text[i..<j]))
            i = j
        }
        return out + c.flush()
    }

    @Test(arguments: [
        // English
        ("Hello there. How are you?", ["Hello there.", "How are you?"]),
        ("Mr. Smith arrived. He sat down.", ["Mr. Smith arrived.", "He sat down."]),
        ("It costs 3.5 dollars. Cheap!", ["It costs 3.5 dollars.", "Cheap!"]),
        ("J. K. Rowling wrote it. Wow.", ["J. K. Rowling wrote it.", "Wow."]),
        ("Wait... really? Yes!", ["Wait... really?", "Yes!"]),
        ("He said \"no.\" Then he left.", ["He said \"no.\"", "Then he left."]),
        ("Apples, pears, etc. are fruits.", ["Apples, pears, etc. are fruits."]),
        // French
        ("Napoléon est né en 1769. Il est mort en 1821.", ["Napoléon est né en 1769.", "Il est mort en 1821."]),
        ("Il arrive en 1799. puis il règne.", ["Il arrive en 1799. puis il règne."]),
        ("M. Dupont est là. Mme Durand aussi.", ["M. Dupont est là.", "Mme Durand aussi."]),
        ("Quoi ? Tu viens ! Super.", ["Quoi ?", "Tu viens !", "Super."]),
        ("Des fruits, p. ex. des pommes. Miam.", ["Des fruits, p. ex. des pommes.", "Miam."]),
        ("En 52 av. J.-C. César gagne. Fin.", ["En 52 av. J.-C. César gagne.", "Fin."]),
        ("« Bonjour. » Elle sourit.", ["« Bonjour. »", "Elle sourit."]),
        // Spanish
        ("¿Qué tal? ¡Muy bien! Gracias.", ["¿Qué tal?", "¡Muy bien!", "Gracias."]),
        ("La Sra. García llegó. Se sentó.", ["La Sra. García llegó.", "Se sentó."]),
        // Newlines and leftovers
        ("First line\nSecond line", ["First line", "Second line"]),
        ("No final punctuation", ["No final punctuation"]),
        ("  ", [String]()),
    ])
    func splits(input: String, expected: [String]) {
        #expect(Self.chunk(input) == expected)
        #expect(Self.chunk(input, step: 7) == expected)
    }

    @Test func emitsAsSoonAsTheNextWordStarts() {
        var c = SentenceChunker()
        #expect(c.feed("Bonjour.").isEmpty)  // could still be "Bonjour.com" or an abbreviation
        #expect(c.feed(" ").isEmpty)  // need the next word to know its case
        #expect(c.feed("Comment") == ["Bonjour."])
        #expect(c.flush() == ["Comment"])
    }

    @Test func questionMarkIsImmediateOnceFollowedBySpaceAndWord() {
        var c = SentenceChunker()
        #expect(c.feed("Ça va ? O") == ["Ça va ?"])
    }
}

struct FirstChunkTests {
    @Test func longOpeningSentenceIsCutAtItsFirstClause() {
        var c = SentenceChunker(firstChunkMinLength: 40)
        let text = "Napoléon Bonaparte, né en 1769 à Ajaccio, devient empereur en 1804. Il meurt en 1821."
        var out: [String] = []
        for ch in text { out += c.feed(String(ch)) }
        out += c.flush()
        #expect(out.first == "Napoléon Bonaparte, né en 1769 à Ajaccio,")
        #expect(out.dropFirst().first == "devient empereur en 1804.")
        #expect(out.last == "Il meurt en 1821.")
    }

    @Test func onlyTheFirstChunkIsCutEarly() {
        var c = SentenceChunker(firstChunkMinLength: 10)
        let out = c.feed("Oui. Ensuite, une phrase assez longue, avec des virgules, continue. Fin") + c.flush()
        #expect(out == ["Oui.", "Ensuite, une phrase assez longue, avec des virgules, continue.", "Fin"])
    }
}
