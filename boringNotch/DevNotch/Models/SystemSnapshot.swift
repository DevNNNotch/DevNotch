import Foundation

enum MetricAvailability<Value: Sendable & Equatable>: Sendable, Equatable {
    case available(Value)
    case unavailable(reason: String)
    case permissionRequired(reason: String)

    var value: Value? {
        guard case .available(let value) = self else { return nil }
        return value
    }

    var unavailableReason: String? {
        switch self {
        case .available: nil
        case .unavailable(let reason), .permissionRequired(let reason): reason
        }
    }
}

struct NetworkRates: Equatable, Sendable {
    let downloadBytesPerSecond: UInt64
    let uploadBytesPerSecond: UInt64
}

struct BatterySnapshot: Equatable, Sendable {
    let level: Double
    let isCharging: Bool
    let powerSource: String
}

struct SystemSnapshot: Equatable, Sendable {
    let cpu: MetricAvailability<Double>
    let memory: MetricAvailability<Double>
    let usedMemoryBytes: UInt64?
    let totalMemoryBytes: UInt64
    let network: MetricAvailability<NetworkRates>
    let battery: MetricAvailability<BatterySnapshot>
    let gpu: MetricAvailability<Double>
    let headphoneBattery: MetricAvailability<Double>
    let capturedAt: Date

    static let empty = SystemSnapshot(
        cpu: .unavailable(reason: "Waiting for the first CPU sample"),
        memory: .unavailable(reason: "Waiting for the first memory sample"),
        usedMemoryBytes: nil,
        totalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
        network: .unavailable(reason: "Waiting for the network counter baseline"),
        battery: .unavailable(reason: "Power source has not been sampled"),
        gpu: .unavailable(reason: "macOS has no public system-wide GPU utilization API"),
        headphoneBattery: .unavailable(reason: "No verified public headphone battery source is configured"),
        capturedAt: .distantPast
    )

    var memoryDetail: String {
        guard let usedMemoryBytes else { return memory.unavailableReason ?? "Unavailable" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return "\(formatter.string(fromByteCount: Int64(usedMemoryBytes))) of \(formatter.string(fromByteCount: Int64(totalMemoryBytes)))"
    }

    var batterySummary: String {
        guard let battery = battery.value else { return "Battery N/A" }
        let percentage = battery.level.formatted(.percent.precision(.fractionLength(0)))
        return battery.isCharging ? "\(percentage) charging" : percentage
    }
}
