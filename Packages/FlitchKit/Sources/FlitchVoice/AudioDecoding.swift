@preconcurrency import AVFoundation
import FlitchCore
import Foundation

/// Turns provider audio into clips.
public enum AudioDecoding {
    /// Raw signed 16-bit little-endian mono PCM.
    public static func pcm16(_ data: Data, sampleRate: Double) throws -> AudioClip {
        let count = data.count / 2
        var samples = [Float](repeating: 0, count: count)
        data.withUnsafeBytes { raw in
            let p = raw.bindMemory(to: Int16.self)
            for i in 0..<count { samples[i] = Float(Int16(littleEndian: p[i])) / 32_768 }
        }
        return try clip(samples, sampleRate)
    }

    /// Raw 32-bit float little-endian mono PCM.
    public static func pcmFloat32(_ data: Data, sampleRate: Double) throws -> AudioClip {
        let count = data.count / 4
        var samples = [Float](repeating: 0, count: count)
        data.withUnsafeBytes { raw in
            let p = raw.bindMemory(to: UInt32.self)
            for i in 0..<count { samples[i] = Float(bitPattern: UInt32(littleEndian: p[i])) }
        }
        return try clip(samples, sampleRate)
    }

    /// Any container AVFoundation reads (WAV, MP3, AAC…), mixed down to mono.
    public static func container(_ data: Data, fileExtension: String) throws -> AudioClip {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("flitch-\(UUID().uuidString).\(fileExtension)")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw FlitchError.other("unreadable audio")
        }
        try file.read(into: buffer)
        guard let channels = buffer.floatChannelData else { throw FlitchError.other("unreadable audio") }
        let n = Int(buffer.frameLength)
        let c = Int(format.channelCount)
        var samples = [Float](repeating: 0, count: n)
        for ch in 0..<c {
            for i in 0..<n { samples[i] += channels[ch][i] / Float(c) }
        }
        return try clip(samples, format.sampleRate)
    }

    private static func clip(_ samples: [Float], _ rate: Double) throws -> AudioClip {
        guard !samples.isEmpty, let b = AVAudioPCMBuffer.mono(samples, sampleRate: rate) else {
            throw FlitchError.other("the voice returned no audio")
        }
        return AudioClip(b)
    }
}
