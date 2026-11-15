import AVFoundation
import Foundation

/// Renders a sine through Apple's NewTimePitch unit (`AVAudioUnitTimePitch`, the same
/// component `CoreAudioPitchGraph` uses) with AVAudioEngine in offline manual rendering mode.
/// Manual rendering detaches the engine from every audio device: nothing is opened or played.
final class OfflinePitchRenderer {
    enum RenderError: Error {
        case formatUnavailable
        case bufferUnavailable
        case renderFailed(AVAudioEngineManualRenderingStatus)
    }

    let sampleRate: Double
    private let engine = AVAudioEngine()
    private let timePitch = AVAudioUnitTimePitch()
    private let format: AVAudioFormat

    var isManualOffline: Bool {
        engine.isInManualRenderingMode && engine.manualRenderingMode == .offline
    }

    init(sampleRate: Double = 48_000) throws {
        self.sampleRate = sampleRate
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            throw RenderError.formatUnavailable
        }
        self.format = format
        // Must be set before the engine touches its output node, so no device is ever bound.
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
    }

    /// Renders `duration` seconds and drops the first `warmup` seconds (the unit's latency and settling).
    func render(inputFrequency: Double, pitchCents: Float,
                duration: Double = 4, warmup: Double = 0.5) throws -> [Float] {
        let phaseStep = 2 * Double.pi * inputFrequency / sampleRate
        let state = PhaseState()
        let source = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for buffer in buffers {
                let out = buffer.mData!.assumingMemoryBound(to: Float.self)
                var phase = state.phase
                for i in 0..<Int(frameCount) {
                    out[i] = Float(0.5 * sin(phase))
                    phase += phaseStep
                }
                if buffer.mData == buffers.last?.mData { state.phase = phase.truncatingRemainder(dividingBy: 2 * .pi) }
            }
            return noErr
        }

        timePitch.pitch = pitchCents
        engine.attach(source)
        engine.attach(timePitch)
        engine.connect(source, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)
        engine.prepare()
        try engine.start()
        defer {
            engine.stop()
            engine.detach(source)
        }

        guard let chunk = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat,
                                           frameCapacity: engine.manualRenderingMaximumFrameCount) else {
            throw RenderError.bufferUnavailable
        }
        let total = Int(duration * sampleRate)
        let skip = Int(warmup * sampleRate)
        var output: [Float] = []
        output.reserveCapacity(total)
        while output.count < total {
            let frames = min(chunk.frameCapacity, AVAudioFrameCount(total - output.count))
            let status = try engine.renderOffline(frames, to: chunk)
            guard status == .success else { throw RenderError.renderFailed(status) }
            let channel = chunk.floatChannelData![0]
            output.append(contentsOf: UnsafeBufferPointer(start: channel, count: Int(chunk.frameLength)))
        }
        return Array(output[skip...])
    }

    static func sine(frequency: Double, sampleRate: Double, frameCount: Int) -> [Float] {
        let step = 2 * Double.pi * frequency / sampleRate
        return (0..<frameCount).map { Float(sin(Double($0) * step)) }
    }
}

/// Oscillator phase carried between render callbacks (the callback runs on the rendering thread).
private final class PhaseState: @unchecked Sendable {
    var phase: Double = 0
}
