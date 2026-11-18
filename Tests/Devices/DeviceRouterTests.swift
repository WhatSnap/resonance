import Testing
@testable import ResonanceCore

// MARK: - Fakes

@MainActor
final class FakeDeviceProvider: DeviceProvider {
    struct Device {
        var id: DeviceID
        var name: String
        var sampleRate: Double
        var isAlive: Bool = true
    }

    var deviceList: [Device] = []
    var defaultOutput: DeviceID?
    var onEvent: ((DeviceEvent) -> Void)?

    func outputDevices() -> [OutputDevice] {
        deviceList.map { OutputDevice(id: $0.id, name: $0.name) }
    }

    func defaultOutputDevice() -> DeviceID? { defaultOutput }

    func isAlive(_ id: DeviceID) -> Bool {
        deviceList.first { $0.id == id }?.isAlive ?? false
    }

    func nominalSampleRate(_ id: DeviceID) -> Double? {
        deviceList.first { $0.id == id }?.sampleRate
    }

    // Scenario helpers: mutate state, then emit the event Core Audio would send.
    func connect(_ device: Device) {
        deviceList.append(device)
        onEvent?(.devicesChanged)
    }

    func disconnect(_ id: DeviceID) {
        if let i = deviceList.firstIndex(where: { $0.id == id }) {
            deviceList[i].isAlive = false
            onEvent?(.aliveChanged(id))
            deviceList.remove(at: i)
        }
        onEvent?(.devicesChanged)
    }

    func setDefault(_ id: DeviceID?) {
        defaultOutput = id
        onEvent?(.defaultOutputChanged)
    }

    func setRate(_ id: DeviceID, _ rate: Double) {
        if let i = deviceList.firstIndex(where: { $0.id == id }) {
            deviceList[i].sampleRate = rate
        }
        onEvent?(.sampleRateChanged(id))
    }

    func wake() { onEvent?(.didWake) }
}

@MainActor
final class FakeScheduler: RouterScheduler {
    private struct Pending {
        let id: Int
        let fireAt: Double
        let action: @MainActor () -> Void
    }

    final class Token: ScheduledTask {
        let cancelAction: () -> Void
        init(_ cancelAction: @escaping () -> Void) { self.cancelAction = cancelAction }
        func cancel() { cancelAction() }
    }

    private(set) var now: Double = 0
    private var pending: [Pending] = []
    private var nextID = 0

    func schedule(after delay: Double, _ action: @escaping @MainActor () -> Void) -> ScheduledTask {
        nextID += 1
        let id = nextID
        pending.append(Pending(id: id, fireAt: now + delay, action: action))
        return Token { [weak self] in
            MainActor.assumeIsolated { self?.pending.removeAll { $0.id == id } }
        }
    }

    func advance(by seconds: Double) {
        let target = now + seconds
        while let next = pending.filter({ $0.fireAt <= target }).min(by: { $0.fireAt < $1.fireAt }) {
            pending.removeAll { $0.id == next.id }
            now = next.fireAt
            next.action()
        }
        now = target
    }
}

// MARK: - Fixture

let speakers = FakeDeviceProvider.Device(id: 10, name: "MacBook Pro Speakers", sampleRate: 48_000)
let airPods = FakeDeviceProvider.Device(id: 20, name: "AirPods Pro", sampleRate: 48_000)
let blackHole = FakeDeviceProvider.Device(id: 5, name: "BlackHole 2ch", sampleRate: 48_000)
let zoom = FakeDeviceProvider.Device(id: 30, name: "ZoomAudioDevice", sampleRate: 48_000)

@MainActor
struct Harness {
    let provider = FakeDeviceProvider()
    let clock = FakeScheduler()
    let router: DeviceRouter
    let log = RebindLog()

    final class RebindLog {
        var rebinds: [OutputTarget] = []
        var healthChecks: [OutputTarget?] = []
    }

    init(devices: [FakeDeviceProvider.Device], default id: DeviceID) {
        provider.deviceList = devices
        provider.defaultOutput = id
        router = DeviceRouter(provider: provider, scheduler: clock)
        let log = self.log
        router.onRebind = { log.rebinds.append($0) }
        router.onHealthCheck = { log.healthChecks.append($0) }
        router.start()
    }

    func settle() { clock.advance(by: 1.0) }
}

// MARK: - Tests

@MainActor
@Suite("DeviceRouter")
struct DeviceRouterTests {

    @Test("start binds to the current default output without a rebind")
    func startBindsToDefault() {
        let h = Harness(devices: [blackHole, speakers], default: speakers.id)
        #expect(h.router.current == OutputTarget(deviceID: speakers.id, sampleRate: 48_000))
        h.settle()
        #expect(h.log.rebinds.isEmpty)
    }

    @Test("AirPods connecting and becoming the default triggers one rebind to the AirPods")
    func airPodsConnect() {
        let h = Harness(devices: [blackHole, speakers], default: speakers.id)
        h.provider.connect(airPods)
        h.clock.advance(by: 0.05)
        h.provider.setDefault(airPods.id)
        h.settle()
        #expect(h.log.rebinds == [OutputTarget(deviceID: airPods.id, sampleRate: 48_000)])
    }

    @Test("AirPods becoming the default well after they appear still gives one rebind")
    func airPodsConnectSlowDefault() {
        let h = Harness(devices: [blackHole, speakers], default: speakers.id)
        h.provider.connect(airPods)
        h.clock.advance(by: 2.0)
        h.provider.setDefault(airPods.id)
        h.settle()
        #expect(h.log.rebinds == [OutputTarget(deviceID: airPods.id, sampleRate: 48_000)])
    }

    @Test("the default disconnecting rebinds to the new default, never to the first listed device")
    func defaultDisconnects() {
        // BlackHole is listed first: the old code would have fallen back to it.
        let h = Harness(devices: [blackHole, speakers, airPods], default: airPods.id)
        h.provider.disconnect(airPods.id)
        h.provider.setDefault(speakers.id)
        h.settle()
        #expect(h.log.rebinds == [OutputTarget(deviceID: speakers.id, sampleRate: 48_000)])
    }

    @Test("a dead default with no replacement yet causes no rebind, then one when the new default arrives")
    func defaultDiesBeforeReplacement() {
        let h = Harness(devices: [blackHole, speakers, airPods], default: airPods.id)
        h.provider.disconnect(airPods.id)   // HAL still reports the gone device as default
        h.settle()
        #expect(h.log.rebinds.isEmpty)
        h.provider.setDefault(speakers.id)
        h.settle()
        #expect(h.log.rebinds == [OutputTarget(deviceID: speakers.id, sampleRate: 48_000)])
    }

    @Test("a sample rate change on the current output triggers a rebind with the new rate")
    func rateChange() {
        let h = Harness(devices: [speakers, airPods], default: airPods.id)
        h.provider.setRate(airPods.id, 44_100)
        h.settle()
        #expect(h.log.rebinds == [OutputTarget(deviceID: airPods.id, sampleRate: 44_100)])
    }

    @Test("a rate change on another device causes no rebind")
    func rateChangeElsewhere() {
        let h = Harness(devices: [speakers, airPods], default: airPods.id)
        h.provider.setRate(speakers.id, 96_000)
        h.settle()
        #expect(h.log.rebinds.isEmpty)
    }

    @Test("a rate of 24 kHz or lower reports headset mode", arguments: [
        (24_000.0, true), (16_000.0, true), (8_000.0, true), (44_100.0, false), (48_000.0, false),
    ])
    func headsetMode(rate: Double, headset: Bool) {
        let h = Harness(devices: [speakers, airPods], default: airPods.id)
        #expect(h.router.isHeadsetMode == false)
        h.provider.setRate(airPods.id, rate)
        h.settle()
        #expect(h.router.isHeadsetMode == headset)
        #expect(h.router.current?.isHeadsetProfile == headset)
        if headset {
            #expect(h.log.rebinds.last?.isHeadsetProfile == true)
        }
    }

    @Test("headset mode clears when the rate goes back up")
    func headsetModeClears() {
        let h = Harness(devices: [speakers, airPods], default: airPods.id)
        h.provider.setRate(airPods.id, 16_000)
        h.settle()
        h.provider.setRate(airPods.id, 48_000)
        h.settle()
        #expect(h.router.isHeadsetMode == false)
        #expect(h.log.rebinds.map(\.sampleRate) == [16_000, 48_000])
    }

    @Test("wake with nothing changed runs a health check and no rebind")
    func wakeNoChange() {
        let h = Harness(devices: [speakers, airPods], default: airPods.id)
        h.provider.wake()
        h.settle()
        #expect(h.log.healthChecks == [OutputTarget(deviceID: airPods.id, sampleRate: 48_000)])
        #expect(h.log.rebinds.isEmpty)
    }

    @Test("wake after the default changed during sleep runs a health check and one rebind")
    func wakeDeviceChanged() {
        let h = Harness(devices: [speakers, airPods], default: airPods.id)
        // During sleep the AirPods went away without any notification reaching the app.
        h.provider.deviceList.removeAll { $0.id == airPods.id }
        h.provider.defaultOutput = speakers.id
        h.provider.wake()
        h.settle()
        #expect(h.log.healthChecks.count == 1)
        #expect(h.log.rebinds == [OutputTarget(deviceID: speakers.id, sampleRate: 48_000)])
    }

    @Test("an unrelated device appearing or disappearing causes no rebind")
    func unrelatedDevice() {
        let h = Harness(devices: [blackHole, speakers], default: speakers.id)
        h.provider.connect(zoom)
        h.settle()
        h.provider.disconnect(zoom.id)
        h.settle()
        h.provider.disconnect(blackHole.id)
        h.settle()
        #expect(h.log.rebinds.isEmpty)
        #expect(h.log.healthChecks.isEmpty)
    }

    @Test("a burst of changes within the debounce window gives one rebind")
    func burstDebounced() {
        let h = Harness(devices: [speakers], default: speakers.id)
        h.provider.connect(airPods)
        h.clock.advance(by: 0.1)
        h.provider.setDefault(airPods.id)
        h.clock.advance(by: 0.1)
        h.provider.setRate(airPods.id, 16_000)
        h.clock.advance(by: 0.1)
        h.provider.setRate(airPods.id, 24_000)
        h.clock.advance(by: 0.1)
        h.provider.setDefault(speakers.id)
        h.clock.advance(by: 0.1)
        h.provider.setDefault(airPods.id)
        // Nothing fires while events keep arriving inside the window.
        h.clock.advance(by: DeviceRouter.defaultDebounce - 0.01)
        #expect(h.log.rebinds.isEmpty)
        h.settle()
        #expect(h.log.rebinds == [OutputTarget(deviceID: airPods.id, sampleRate: 24_000)])
    }

    @Test("the rebind fires one debounce window after the last event")
    func debounceTiming() {
        let h = Harness(devices: [speakers, airPods], default: speakers.id)
        h.provider.setDefault(airPods.id)
        h.clock.advance(by: DeviceRouter.defaultDebounce - 0.01)
        #expect(h.log.rebinds.isEmpty)
        h.clock.advance(by: 0.02)
        #expect(h.log.rebinds.count == 1)
    }

    @Test("a burst that ends where it started gives no rebind")
    func burstBackToStart() {
        let h = Harness(devices: [speakers, airPods], default: speakers.id)
        h.provider.setDefault(airPods.id)
        h.clock.advance(by: 0.1)
        h.provider.setDefault(speakers.id)
        h.settle()
        #expect(h.log.rebinds.isEmpty)
    }

    @Test("stop ignores later events")
    func stopIgnoresEvents() {
        let h = Harness(devices: [speakers, airPods], default: speakers.id)
        h.router.stop()
        h.provider.setDefault(airPods.id)
        h.settle()
        #expect(h.log.rebinds.isEmpty)
    }
}
