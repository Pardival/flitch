@preconcurrency import AVFoundation
import FlitchCore

/// Microphone level helpers (pure, testable).
public enum AudioLevel {
    /// Maps RMS of float samples to 0…1 on a perceptual scale (-50 dBFS → 0, 0 dBFS → 1).
    public static func normalizedRMS(_ samples: UnsafeBufferPointer<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for s in samples { sum += s * s }
        let rms = (sum / Float(samples.count)).squareRoot()
        guard rms > 0 else { return 0 }
        let db = 20 * log10(rms)
        return min(1, max(0, (db + 50) / 50))
    }

    public static func normalizedRMS(_ samples: [Float]) -> Float {
        samples.withUnsafeBufferPointer { normalizedRMS($0) }
    }

    public static func normalizedRMS(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        return normalizedRMS(UnsafeBufferPointer(start: data, count: Int(buffer.frameLength)))
    }
}

/// Converts captured buffers to the format the recognizer wants (e.g. 16 kHz mono).
public final class AudioFormatConverter: @unchecked Sendable {
    public let output: AVAudioFormat
    private let converter: AVAudioConverter

    public init?(from input: AVAudioFormat, to output: AVAudioFormat) {
        guard let c = AVAudioConverter(from: input, to: output) else { return nil }
        self.output = output
        self.converter = c
    }

    public func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let ratio = output.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: output, frameCapacity: capacity) else { return nil }
        final class Flag: @unchecked Sendable { var consumed = false }
        let flag = Flag()
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, inputStatus in
            if flag.consumed {
                inputStatus.pointee = .noDataNow
                return nil
            }
            flag.consumed = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, error == nil else { return nil }
        return out
    }
}

/// Captures the microphone **in memory only** (nothing is written to disk) and streams buffers
/// in the requested format, plus a 0…1 level for the listening animation.
public final class AudioCapture: @unchecked Sendable {
    public let buffers: AsyncStream<AVAudioPCMBuffer>
    public let levels: AsyncStream<Float>

    private let engine = AVAudioEngine()
    private let buffersContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation
    private let levelsContinuation: AsyncStream<Float>.Continuation
    private var running = false

    public init() {
        (buffers, buffersContinuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
        (levels, levelsContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    /// Asks for microphone access if needed. Throws `FlitchError.microphoneDenied` when refused.
    public static func ensurePermission() async throws {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return
        case .denied: throw FlitchError.microphoneDenied
        default:
            let ok = await AVAudioApplication.requestRecordPermission()
            if !ok { throw FlitchError.microphoneDenied }
        }
    }

    /// Starts capturing. `format` is the recognizer's preferred format (nil = the microphone's own).
    public func start(format: AVAudioFormat?) throws {
        let input = engine.inputNode
        let natural = input.outputFormat(forBus: 0)
        let converter = format.flatMap { $0 == natural ? nil : AudioFormatConverter(from: natural, to: $0) }
        let buffers = buffersContinuation
        let levels = levelsContinuation
        input.installTap(onBus: 0, bufferSize: 2048, format: natural) { buffer, _ in
            levels.yield(AudioLevel.normalizedRMS(buffer))
            if let converter {
                if let converted = converter.convert(buffer) { buffers.yield(converted) }
            } else if let copy = buffer.copy() as? AVAudioPCMBuffer {
                buffers.yield(copy)
            }
        }
        engine.prepare()
        try engine.start()
        running = true
    }

    /// Stops the microphone and ends both streams. Buffers are released with the streams.
    public func stop() {
        guard running else { return }
        running = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        buffersContinuation.finish()
        levelsContinuation.finish()
    }

    deinit { stop() }
}
