import Foundation
import Observation
import Sparkle

/// Sparkle 2 updates: EdDSA-signed appcast on GitHub Releases (no Apple account needed).
/// Dev builds have no public key, so updates stay off there.
@MainActor
@Observable
final class Updater {
    private let controller: SPUStandardUpdaterController?

    var isAvailable: Bool { controller != nil }

    init() {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        controller =
            key.isEmpty
            ? nil
            : SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates() { controller?.checkForUpdates(nil) }
}
