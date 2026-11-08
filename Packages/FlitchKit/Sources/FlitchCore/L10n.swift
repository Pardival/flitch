import Foundation

/// User-facing strings of FlitchCore, localized in EN / FR / ES (`Resources/Localizable.xcstrings`).
public enum L10n {
    public static func string(_ key: String.LocalizationValue, locale: Locale = .current) -> String {
        String(localized: key, bundle: .module, locale: locale)
    }

    public static func listeningHint(shortcut: String) -> String {
        String(format: string("listening.hint"), shortcut)
    }

    public static func speakingHint(shortcut: String) -> String {
        String(format: string("speaking.hint"), shortcut)
    }
}
