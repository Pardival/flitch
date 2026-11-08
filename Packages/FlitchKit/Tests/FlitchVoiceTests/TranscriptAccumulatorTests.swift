import Testing

@testable import FlitchVoice

struct TranscriptAccumulatorTests {
    @Test func volatileResultsAreReplacedThenFinalized() {
        var a = TranscriptAccumulator()
        a.add("Parle", isFinal: false)
        #expect(a.text == "Parle")
        a.add("Parle-moi de", isFinal: false)
        #expect(a.text == "Parle-moi de")
        a.add("Parle-moi de Napoléon.", isFinal: true)
        #expect(a.text == "Parle-moi de Napoléon.")
        a.add(" Il est", isFinal: false)
        #expect(a.text == "Parle-moi de Napoléon. Il est")
        a.add(" Il est né où ?", isFinal: true)
        #expect(a.text == "Parle-moi de Napoléon. Il est né où ?")
    }
}
