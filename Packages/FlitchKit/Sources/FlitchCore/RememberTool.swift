import Foundation

/// The `remember(fact)` tool: the model calls it when the user shares a lasting personal fact.
/// The app turns each call into a memory, pending until the user confirms it in the bubble.
public enum RememberTool {
    public static let name = "remember"

    public static let spec = ToolSpec(
        name: name,
        description: """
            Save a lasting fact about the user so you remember it in future conversations \
            (their preferences, family, pets, job, hobbies, favourite team…). Only for facts that will still \
            be true in a month, never for passing requests. Write it short, in the user's language, \
            without "the user" (e.g. "Supports FC Barcelona", "A une chatte nommée Moka"). \
            Always answer the user out loud as well.
            """,
        parametersJSON: """
            {"type":"object","properties":{"fact":{"type":"string","description":"The fact, under 120 characters."}},"required":["fact"],"additionalProperties":false}
            """)

    /// The fact of a `remember` call, or nil for another tool or bad arguments.
    public static func fact(from call: ToolCall) -> String? {
        guard call.name == name,
            let json = try? JSONSerialization.jsonObject(with: Data(call.argumentsJSON.utf8)) as? [String: Any],
            let fact = (json["fact"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !fact.isEmpty
        else { return nil }
        return String(fact.prefix(200))
    }
}
