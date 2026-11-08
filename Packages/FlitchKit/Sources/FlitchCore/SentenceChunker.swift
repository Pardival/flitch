/// Splits streamed LLM text into speakable sentences as early as possible (EN / FR / ES).
///
/// ```swift
/// var chunker = SentenceChunker()
/// for delta in stream { for s in chunker.feed(delta) { speak(s) } }
/// for s in chunker.flush() { speak(s) }
/// ```
///
/// A sentence ends at `.` `!` `?` `…` (or a run of them, plus closing quotes/brackets)
/// followed by whitespace, or at a newline. It does **not** end at abbreviations
/// (`M.`, `Dr.`, `etc.`, `p. ex.`), initials (`J. K.`), decimals (`3.5`), or a dot
/// followed by a lowercase word (`en 1769. puis`). French spacing (`Quoi ?`) and
/// Spanish openers (`¿` `¡`) are handled.
public struct SentenceChunker: Sendable {
    public static let defaultAbbreviations: Set<String> = [
        // English
        "mr", "mrs", "ms", "dr", "prof", "st", "jr", "sr", "vs", "etc", "e.g", "i.e", "approx", "fig", "vol",
        "inc", "ltd", "co", "jan", "feb", "mar", "apr", "jun", "jul", "aug", "sep", "sept", "oct", "nov", "dec",
        // French
        "m", "mm", "mme", "mmes", "mlle", "mlles", "me", "mgr", "ex", "cf", "av", "apr", "j.-c", "env", "chap", "art",
        "boul", "bd", "tél", "éd",
        // Spanish
        "sra", "sres", "srta", "dra", "ud", "uds", "vd", "vds", "pág", "núm", "aprox", "av", "ej", "etc",
    ]

    private static let terminators: Set<Character> = [".", "!", "?", "…"]
    private static let closers: Set<Character> = ["\"", "'", "”", "’", "»", ")", "]", "}"]

    private let abbreviations: Set<String>
    private var buffer: [Character] = []
    /// Speeds up the first sound: before anything was emitted, a long opening sentence may be cut at
    /// its first comma, semicolon or colon once it reaches this many characters (nil = never).
    private let firstChunkMinLength: Int?
    private var emittedAny = false

    public init(abbreviations: Set<String> = SentenceChunker.defaultAbbreviations, firstChunkMinLength: Int? = nil) {
        self.abbreviations = abbreviations
        self.firstChunkMinLength = firstChunkMinLength
    }

    /// Adds streamed text and returns the sentences that are now complete.
    public mutating func feed(_ text: String) -> [String] {
        buffer.append(contentsOf: text)
        var out = extract(final: false)
        if out.isEmpty, !emittedAny, let early = earlyClause() { out = [early] }
        if !out.isEmpty { emittedAny = true }
        return out
    }

    /// First clause of a long opening sentence ("Napoléon Bonaparte, né en 1769 à Ajaccio, …").
    private mutating func earlyClause() -> String? {
        guard let min = firstChunkMinLength, buffer.count >= min else { return nil }
        for i in (min / 2)..<(buffer.count - 1) where [",", ";", ":"].contains(buffer[i]) && buffer[i + 1] == " " {
            let s = Self.clean(buffer[...i])
            buffer = Array(buffer[(i + 1)...])
            return s
        }
        return nil
    }

    /// Ends the stream: returns the remaining complete sentences and the leftover text.
    public mutating func flush() -> [String] {
        var out = extract(final: true)
        let rest = Self.clean(buffer[...])
        if !rest.isEmpty { out.append(rest) }
        buffer.removeAll()
        return out
    }

    // MARK: - Scanning

    private mutating func extract(final: Bool) -> [String] {
        let c = buffer
        var out: [String] = []
        var start = 0
        var i = 0
        scan: while i < c.count {
            let ch = c[i]
            if ch == "\n" {
                let s = Self.clean(c[start..<i])
                if !s.isEmpty { out.append(s) }
                start = i + 1
                i += 1
                continue
            }
            guard Self.terminators.contains(ch) else {
                i += 1
                continue
            }
            // run of terminators and closing marks: "?!", "...", ".»"
            var j = i
            while j < c.count, Self.terminators.contains(c[j]) || Self.closers.contains(c[j]) { j += 1 }
            // French spaced closing guillemet: "Bonjour. »"
            var q = j
            while q < c.count, c[q] == " " || c[q] == "\u{00A0}" || c[q] == "\u{202F}" { q += 1 }
            if q < c.count, c[q] == "»" {
                j = q + 1
            } else if q == c.count && q > j && !final {
                break scan  // a "»" may still come
            }
            if j == c.count {
                if final {
                    let s = Self.clean(c[start..<j])
                    if !s.isEmpty { out.append(s) }
                    start = j
                }
                break scan
            }
            guard c[j].isWhitespace else {  // "3.5", "e.g.x"
                i = j
                continue
            }
            var k = j
            while k < c.count, c[k].isWhitespace, c[k] != "\n" { k += 1 }
            if k == c.count && !final { break scan }  // need the next word to decide
            let next: Character? = k < c.count && c[k] != "\n" ? c[k] : nil
            if isBoundary(c, sentenceStart: start, at: i, runEnd: j, next: next) {
                let s = Self.clean(c[start..<j])
                if !s.isEmpty { out.append(s) }
                start = j
            }
            i = j
        }
        buffer = Array(c[start...])
        return out
    }

    private func isBoundary(_ c: [Character], sentenceStart: Int, at i: Int, runEnd: Int, next: Character?) -> Bool {
        let run = c[i..<runEnd].filter { Self.terminators.contains($0) }
        let dotsOnly = run.allSatisfy { $0 == "." || $0 == "…" }
        guard dotsOnly else { return true }  // "?" or "!" always end a sentence
        if let next, next.isLowercase { return false }  // "en 1769. puis", "… et alors"
        if run.count == 1 && run.first == "." {
            let word = wordBefore(c, index: i, floor: sentenceStart)
            if abbreviations.contains(word.lowercased()) { return false }
            if word.count == 1, let w = word.first, w.isUppercase { return false }  // initials: "J. K. Rowling"
        }
        return true
    }

    /// The token right before `index`, without leading punctuation: "(Dr" -> "Dr", "J.-C" stays "J.-C".
    private func wordBefore(_ c: [Character], index: Int, floor: Int) -> String {
        var s = index
        while s > floor, !c[s - 1].isWhitespace { s -= 1 }
        var word = String(c[s..<index])
        while let f = word.first, !f.isLetter, !f.isNumber { word.removeFirst() }
        return word
    }

    private static func clean(_ chars: ArraySlice<Character>) -> String {
        var s = chars
        while let f = s.first, f.isWhitespace { s.removeFirst() }
        while let l = s.last, l.isWhitespace { s.removeLast() }
        return String(s)
    }
}
