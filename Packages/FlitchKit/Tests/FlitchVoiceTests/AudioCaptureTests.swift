import AVFoundation
import Testing

@testable import FlitchVoice

struct AudioLevelTests {
    @Test func silenceIsZero() {
        #expect(AudioLevel.normalizedRMS([Float](repeating: 0, count: 512)) == 0)
        #expect(AudioLevel.normalizedRMS([Float]()) == 0)
    }

    @Test func fullScaleIsOne() {
        #expect(AudioLevel.normalizedRMS([Float](repeating: 1, count: 512)) == 1)
    }

    @Test func louderIsHigher() {
        let quiet = AudioLevel.normalizedRMS((0..<512).map { _ in Float(0.01) })
        let loud = AudioLevel.normalizedRMS((0..<512).map { _ in Float(0.3) })
        #expect(quiet > 0 && quiet < loud && loud < 1)
    }
}

struct AudioFormatConverterTests {
    @Test func converts48kStereoTo16kMono() throws {
        let input = try #require(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let output = try #require(
            AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true))
        let converter = try #require(AudioFormatConverter(from: input, to: output))

        let frames: AVAudioFrameCount = 4800  // 100 ms
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: input, frameCapacity: frames))
        buffer.frameLength = frames
        for ch in 0..<2 {
            for i in 0..<Int(frames) { buffer.floatChannelData![ch][i] = sin(Float(i) * 0.05) * 0.5 }
        }
        // the converter may hold a few frames back on the first call: feed twice
        let first = try #require(converter.convert(buffer))
        let second = try #require(converter.convert(buffer))
        #expect(first.format.sampleRate == 16_000 && first.format.channelCount == 1)
        let total = Int(first.frameLength + second.frameLength)
        #expect(abs(total - 3200) < 320)  // 200 ms at 16 kHz, minus the resampler latency (< 20 ms)
    }
}
