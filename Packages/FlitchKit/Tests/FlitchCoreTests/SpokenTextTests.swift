import Testing

@testable import FlitchCore

struct SpokenTextTests {
    @Test(arguments: [
        ("Voir https://fr.wikipedia.org/wiki/Napoléon pour plus.", "Voir pour plus."),
        (
            "D'après [Wikipédia](https://fr.wikipedia.org/wiki/X), il est né en 1769.",
            "D'après Wikipédia, il est né en 1769."
        ),
        ("Il est né en 1769 [1].", "Il est né en 1769."),
        ("C'est **très** important.", "C'est très important."),
        ("## Résumé", "Résumé"),
        ("Tu viens ?", "Tu viens ?"),
        ("Rien à nettoyer.", "Rien à nettoyer."),
        ("https://example.org", ""),
    ])
    func cleans(input: String, expected: String) {
        #expect(SpokenText.clean(input) == expected)
    }
}
