import AVFAudio

final class DictationPCMAccumulator {
    private let maximumSamples: Int
    private var samples: [Float] = []
    private var converter: AVAudioConverter?
    private var peak: Float = 0
    private var voicedFrames = 0
    private var windowEnergy: Double = 0
    private var windowFrames = 0

    init(maximumSamples: Int = 120 * 16_000) { self.maximumSamples = maximumSamples }

    var audio: DictationAudio {
        let partial = windowFrames > 0 && Float(sqrt(windowEnergy / Double(windowFrames))) >= 0.005 ? windowFrames : 0
        return DictationAudio(samples: samples, evidence: .init(voicedSeconds: Double(voicedFrames + partial) / 16_000, peak: peak))
    }

    @discardableResult
    func append(_ input: AVAudioPCMBuffer) throws -> Double {
        guard samples.count < maximumSamples, input.frameLength > 0 else { return 0 }
        guard input.format.sampleRate > 0, input.format.channelCount > 0,
              let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1) else {
            throw DictationCaptureFailure.conversion
        }
        if converter?.inputFormat != input.format {
            converter = AVAudioConverter(from: input.format, to: format)
            converter?.downmix = true
            converter?.primeMethod = .none
        }
        guard let converter else { throw DictationCaptureFailure.conversion }
        let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * 16_000 / input.format.sampleRate)) + 32
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw DictationCaptureFailure.conversion
        }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true
            status.pointee = .haveData
            return input
        }
        guard status != .error, error == nil, let data = output.floatChannelData?[0] else {
            throw DictationCaptureFailure.conversion
        }
        let count = min(Int(output.frameLength), maximumSamples - samples.count)
        var energy: Double = 0
        for index in 0..<count {
            let value = data[index]
            guard value.isFinite else { throw DictationCaptureFailure.conversion }
            samples.append(value)
            peak = max(peak, abs(value))
            windowEnergy += Double(value) * Double(value)
            energy += Double(value) * Double(value)
            windowFrames += 1
            if windowFrames == 320 {
                if Float(sqrt(windowEnergy / 320)) >= 0.005 { voicedFrames += 320 }
                windowEnergy = 0
                windowFrames = 0
            }
        }
        return count > 0 ? sqrt(energy / Double(count)) : 0
    }
}
