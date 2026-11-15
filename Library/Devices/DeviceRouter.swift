import Foundation

/// The output the engine should render to.
public struct OutputTarget: Equatable, Sendable {
    /// Rates at or below this mean the Bluetooth headset (HFP) profile is active.
    public static let headsetRateCeiling: Double = 24_000

    public let deviceID: DeviceID
    public let sampleRate: Double

    public init(deviceID: DeviceID, sampleRate: Double) {
        self.deviceID = deviceID
        self.sampleRate = sampleRate
    }

    public var isHeadsetProfile: Bool { sampleRate <= Self.headsetRateCeiling }
}

public protocol ScheduledTask: AnyObject {
    func cancel()
}

/// A clock the router uses for debouncing, so tests can control time.
@MainActor
public protocol RouterScheduler: AnyObject {
    func schedule(after delay: Double, _ action: @escaping @MainActor () -> Void) -> ScheduledTask
}

/// Real scheduler on the main queue.
@MainActor
public final class MainQueueScheduler: RouterScheduler {
    private final class Task: ScheduledTask {
        let item: DispatchWorkItem
        init(_ item: DispatchWorkItem) { self.item = item }
        func cancel() { item.cancel() }
    }

    public init() {}

    public func schedule(after delay: Double, _ action: @escaping @MainActor () -> Void) -> ScheduledTask {
        let item = DispatchWorkItem { MainActor.assumeIsolated { action() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        return Task(item)
    }
}

/// Decides when the engine must rebind its output.
///
/// It always follows the system default output (never "the first listed device"). Every hardware event restarts a
/// debounce window; when the window closes the router re-reads the default output and its rate, and calls `onRebind`
/// only if that target differs from the current one. Events about other devices therefore never cause a rebind.
/// Wake additionally calls `onHealthCheck` once, so the engine can verify its IO is still running.
@MainActor
public final class DeviceRouter {
    /// 300 ms: long enough to fold the devices / default / rate burst of an AirPods connect into one rebind,
    /// short enough that the switch feels immediate.
    public static let defaultDebounce: Double = 0.3

    public var onRebind: ((OutputTarget) -> Void)?
    /// Called after a wake, with the target the router resolved (nil if no usable output).
    public var onHealthCheck: ((OutputTarget?) -> Void)?

    public private(set) var current: OutputTarget?
    public var isHeadsetMode: Bool { current?.isHeadsetProfile ?? false }

    private let provider: DeviceProvider
    private let scheduler: RouterScheduler
    private let debounce: Double
    private var pending: ScheduledTask?
    private var wakePending = false
    private var running = false

    public init(provider: DeviceProvider, scheduler: RouterScheduler, debounce: Double = DeviceRouter.defaultDebounce) {
        self.provider = provider
        self.scheduler = scheduler
        self.debounce = debounce
    }

    /// Resolves the initial target (no `onRebind`) and starts listening.
    @discardableResult
    public func start() -> OutputTarget? {
        current = resolve()
        running = true
        provider.onEvent = { [weak self] event in self?.handle(event) }
        return current
    }

    public func stop() {
        running = false
        provider.onEvent = nil
        pending?.cancel()
        pending = nil
        wakePending = false
    }

    private func handle(_ event: DeviceEvent) {
        guard running else { return }
        if event == .didWake { wakePending = true }
        pending?.cancel()
        pending = scheduler.schedule(after: debounce) { [weak self] in self?.settle() }
    }

    private func settle() {
        guard running else { return }
        pending = nil
        let target = resolve()
        if wakePending {
            wakePending = false
            onHealthCheck?(target)
        }
        // No usable default yet (e.g. the HAL still names a device that just died): keep the current binding and
        // wait for the next event.
        guard let target, target != current else { return }
        current = target
        onRebind?(target)
    }

    private func resolve() -> OutputTarget? {
        guard let id = provider.defaultOutputDevice(), id != 0, provider.isAlive(id),
              let rate = provider.nominalSampleRate(id), rate > 0
        else { return nil }
        return OutputTarget(deviceID: id, sampleRate: rate)
    }
}
