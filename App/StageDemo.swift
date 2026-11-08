import AppKit
import FlitchCore
import FlitchStage

/// `Flitch --demo-stage topLeft` plays a scripted conversation on the stage (no microphone, no AI),
/// to check the otter and the bubble visually.
@MainActor
final class StageDemo {
    private let stage: PeekStage
    private let model: StageModel
    private var timer: Timer?
    private var t: Double = 0
    private var step = 0

    init(controller: AppController, corner: String) throws {
        model = controller.model
        let sprites = try SpriteSheet(character: controller.character)
        stage = PeekStage(
            model: model, sprites: sprites,
            presentation: StagePresentation(corner: FlitchSettings.Corner(rawValue: corner) ?? .topLeft))
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private let script: [(Double, ConversationEvent)] = [
        (0.2, .listening), (0.8, .partialTranscript("Parle-moi")), (1.6, .partialTranscript("Parle-moi de Napoléon")),
        (2.4, .transcribed("Parle-moi de Napoléon")), (2.4, .thinking),
        (4.0, .sentence("Napoléon Bonaparte est né en 1769 à Ajaccio, en Corse.")),
        (6.5, .sentence("Il devient empereur des Français en 1804.")),
        (
            8.5,
            .answerComplete(
                "Napoléon Bonaparte est né en 1769 à Ajaccio, en Corse. Il devient empereur des Français en 1804.")
        ),
        (8.5, .lingering(remaining: .seconds(15))),
    ]

    private func tick() {
        t += 1.0 / 60
        while step < script.count, script[step].0 <= t {
            model.apply(script[step].1)
            step += 1
        }
        if step == script.count, t > 8.5 {
            let remaining = max(0, 15 - (t - 8.5))
            model.apply(remaining > 0 ? .lingering(remaining: .milliseconds(Int(remaining * 1000))) : .dismissed)
        }
        if t > 25 {
            t = 0
            step = 0
        }
        if case .speaking = model.bubble {
            model.apply(.speakingLevel(Float(abs(sin(t * 9)))))
        }
        stage.tick(1.0 / 60)
    }
}
