import Testing
@testable import ResonanceCore

/// Paths the HQ-431 review left for HQ-433: the "no output" signal, wake with no usable output, and `stop()`
/// cancelling a scheduled settle.
@MainActor
@Suite("DeviceRouter output lost")
struct DeviceRouterOutputLostTests {
    final class LostLog { var lost = 0 }

    @Test("the current output dying with no usable default calls onOutputLost once")
    func outputLostSignal() {
        let h = Harness(devices: [speakers], default: speakers.id)
        let log = LostLog()
        h.router.onOutputLost = { log.lost += 1 }
        h.provider.disconnect(speakers.id)
        h.provider.setDefault(nil)
        h.settle()
        #expect(log.lost == 1)
        #expect(h.router.current == nil)
        #expect(h.log.rebinds.isEmpty)

        // A second burst while still without output does not repeat the signal.
        h.provider.setDefault(nil)
        h.settle()
        #expect(log.lost == 1)
    }

    @Test("after a loss, the same device coming back is a rebind")
    func sameDeviceReturnsAfterLoss() {
        let h = Harness(devices: [airPods], default: airPods.id)
        let log = LostLog()
        h.router.onOutputLost = { log.lost += 1 }
        h.provider.disconnect(airPods.id)
        h.settle()
        #expect(log.lost == 1)
        h.provider.connect(airPods)
        h.provider.setDefault(airPods.id)
        h.settle()
        #expect(h.log.rebinds == [OutputTarget(deviceID: airPods.id, sampleRate: 48_000)])
    }

    @Test("wake with no usable output: health check gets nil, then output lost")
    func wakeWithNoUsableOutput() {
        let h = Harness(devices: [speakers], default: speakers.id)
        let log = LostLog()
        h.router.onOutputLost = { log.lost += 1 }
        h.provider.deviceList[0].isAlive = false
        h.provider.wake()
        h.settle()
        #expect(h.log.healthChecks.count == 1)
        #expect(h.log.healthChecks.first == .some(nil))
        #expect(log.lost == 1)
        #expect(h.log.rebinds.isEmpty)
    }

    @Test("stop cancels a scheduled settle")
    func stopCancelsSettle() {
        let h = Harness(devices: [speakers, airPods], default: speakers.id)
        h.provider.setDefault(airPods.id)
        h.router.stop()
        h.settle()
        #expect(h.log.rebinds.isEmpty)
        #expect(h.log.healthChecks.isEmpty)
    }
}
