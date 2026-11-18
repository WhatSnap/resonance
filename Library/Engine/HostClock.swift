import Darwin

/// Host time in seconds (`mach_absolute_time`), the clock both sides pass to `DriftCompensatedBuffer`.
/// Real-time code keeps `secondsPerTick` in its own context instead of calling `now()`.
public enum HostClock {
    public static let secondsPerTick: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom) / 1_000_000_000
    }()

    public static func now() -> Double { Double(mach_absolute_time()) * secondsPerTick }
}
