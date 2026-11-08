import Foundation

/// Makes text sound right when read aloud: no URLs, no markdown, no citation markers.
/// The bubble keeps the original text; only the voice gets the cleaned version.
public enum SpokenText {
    private static let rules: [(NSRegularExpression, String)] = [
        // markdown links [label](url) → label
        (#"\[([^\]]+)\]\((?:https?://|www\.)[^)]*\)"#, "$1"),
        // bare URLs
        (#"(?:https?://|www\.)[^\s)\]]+"#, ""),
        // citation markers [1], [2, 3], 【1】
        (#"\[\d+(?:\s*,\s*\d+)*\]|【[^】]*】"#, ""),
        // bold, code, headings
        (#"\*\*|__|`+"#, ""),
        (#"(?m)^#+\s*"#, ""),
        // single-character emphasis around words
        (#"(?<=\s|^)[*_](?=\S)|(?<=\S)[*_](?=\s|$|[.,!?])"#, ""),
        // leftovers: empty parentheses, double spaces, space before . or ,
        (#"\(\s*\)"#, ""),
        (#"[ \t]{2,}"#, " "),
        (#" +([.,])"#, "$1"),
    ].map { (try! NSRegularExpression(pattern: $0.0), $0.1) }

    public static func clean(_ text: String) -> String {
        var s = text
        for (regex, template) in rules {
            s = regex.stringByReplacingMatches(
                in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
