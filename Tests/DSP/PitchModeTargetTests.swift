import Testing
import ResonanceCore

/// Baseline for the engine rewrite (HQ-430): every `PitchMode` shifts a 440 Hz sine
/// to its documented target frequency, rendered offline through `NewTimePitch`.
/// Rendering uses AVAudioEngine manual (offline) mode only, so no audio device is opened.
@Suite("Pitch mode targets")
struct PitchModeTargetTests {
    static let tolerance = 0.5

    /// Documented targets. Written out by hand so a change to the cents table fails here.
    static let documentedTargets: [PitchMode: Double] = [
        .off: 440,
        .hz174: 174,
        .hz285: 285,
        .hz396: 396,
        .hz417: 417,
        .hz432: 432,
        .hz444: 444,
        .hz528: 528,
        .hz639: 639,
        .hz741: 741,
        .hz852: 852,
        .hz963: 963,
        .demo: 415.30, // 440 Hz minus one equal-tempered semitone
    ]

    @Test("Every mode has a documented target")
    func everyModeHasADocumentedTarget() throws {
        #expect(Set(PitchMode.allCases) == Set(Self.documentedTargets.keys))
        for mode in PitchMode.allCases {
            let documented = try #require(Self.documentedTargets[mode])
            // The cents table is rounded: 417 and 741 sit about 0.45 Hz off their nominal target.
            #expect(abs(mode.targetFrequency - documented) <= Self.tolerance,
                    "\(mode): cents give \(mode.targetFrequency) Hz, documented \(documented) Hz")
        }
    }

    @Test("The renderer uses offline manual rendering, not a device")
    func rendererIsOffline() throws {
        let renderer = try OfflinePitchRenderer()
        #expect(renderer.isManualOffline)
    }

    @Test("The analyzer finds a pure sine within 0.05 Hz")
    func analyzerFindsAPureSine() {
        let samples = OfflinePitchRenderer.sine(frequency: 432, sampleRate: 48_000, frameCount: 1 << 17)
        let peak = PeakFrequency.estimate(samples, sampleRate: 48_000)
        #expect(abs(peak - 432) < 0.05, "peak \(peak) Hz")
    }

    @Test("A 440 Hz sine in 432 Hz mode peaks at 432 Hz ± 0.5 Hz")
    func hz432From440() throws {
        try assertTarget(.hz432)
    }

    /// One case (and one assertion) per mode.
    @Test("440 Hz lands on the mode's documented target ± 0.5 Hz", arguments: PitchMode.allCases)
    func modeLandsOnTarget(_ mode: PitchMode) throws {
        try assertTarget(mode)
    }

    private func assertTarget(_ mode: PitchMode, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let renderer = try OfflinePitchRenderer()
        let output = try renderer.render(inputFrequency: 440, pitchCents: mode.pitchCents)
        let peak = PeakFrequency.estimate(output, sampleRate: renderer.sampleRate)
        let target = try #require(Self.documentedTargets[mode])
        #expect(abs(peak - target) <= Self.tolerance,
                "\(mode): peak \(peak) Hz, expected \(target) Hz", sourceLocation: sourceLocation)
    }
}
