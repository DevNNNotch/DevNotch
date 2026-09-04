import Combine
import Darwin
import Foundation
import IOKit.ps

@MainActor
final class SystemMonitor: ObservableObject {
    @Published private(set) var snapshot = SystemSnapshot.empty

    private var timer: Timer?
    private var sampler = SystemSampler()

    func start(interval: TimeInterval) {
        stop()
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: max(1, interval), repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sample()
            }
        }
        timer?.tolerance = min(0.5, max(0.1, interval * 0.2))
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func sample() {
        snapshot = sampler.sample()
    }
}

private struct CPUTicks {
    let user: UInt64
    let system: UInt64
    let idle: UInt64
    let nice: UInt64

    var active: UInt64 { user + system + nice }
    var total: UInt64 { active + idle }
}

private struct NetworkCounters {
    let received: UInt64
    let sent: UInt64
}

private struct SystemSampler {
    private var previousCPU: CPUTicks?
    private var previousNetwork: (counters: NetworkCounters, date: Date)?

    mutating func sample() -> SystemSnapshot {
        let now = Date()
        let cpu = sampleCPU()
        let memory = sampleMemory()
        let network = sampleNetwork(at: now)
        let power = samplePower()

        return SystemSnapshot(
            cpu: cpu,
            memory: memory.availability,
            usedMemoryBytes: memory.used,
            totalMemoryBytes: ProcessInfo.processInfo.physicalMemory,
            network: network,
            battery: power,
            gpu: .unavailable(reason: "macOS has no public system-wide GPU utilization API"),
            headphoneBattery: .unavailable(reason: "No verified public headphone battery source is configured"),
            capturedAt: now
        )
    }

    private mutating func sampleCPU() -> MetricAvailability<Double> {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return .unavailable(reason: "host_statistics failed with Mach status \(result)")
        }

        let ticks = CPUTicks(
            user: UInt64(info.cpu_ticks.0),
            system: UInt64(info.cpu_ticks.1),
            idle: UInt64(info.cpu_ticks.2),
            nice: UInt64(info.cpu_ticks.3)
        )
        defer { previousCPU = ticks }
        guard let previousCPU else {
            return .unavailable(reason: "Collecting the CPU counter baseline")
        }
        guard ticks.total >= previousCPU.total, ticks.active >= previousCPU.active else {
            return .unavailable(reason: "CPU counters reset before this sample")
        }
        let totalDelta = ticks.total - previousCPU.total
        let activeDelta = ticks.active - previousCPU.active
        guard totalDelta > 0 else {
            return .unavailable(reason: "CPU counters did not advance")
        }
        return .available(min(1, max(0, Double(activeDelta) / Double(totalDelta))))
    }

    private func sampleMemory() -> (availability: MetricAvailability<Double>, used: UInt64?) {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        let total = ProcessInfo.processInfo.physicalMemory
        guard result == KERN_SUCCESS else {
            return (.unavailable(reason: "host_statistics64 failed with Mach status \(result)"), nil)
        }

        var pageSize: vm_size_t = 0
        let pageResult = host_page_size(mach_host_self(), &pageSize)
        guard pageResult == KERN_SUCCESS else {
            return (.unavailable(reason: "host_page_size failed with Mach status \(pageResult)"), nil)
        }
        let availablePages = UInt64(stats.free_count) + UInt64(stats.inactive_count)
        let available = min(total, availablePages * UInt64(pageSize))
        let used = total - available
        guard total > 0 else { return (.unavailable(reason: "Physical memory size is zero"), nil) }
        return (.available(Double(used) / Double(total)), used)
    }

    private mutating func sampleNetwork(at now: Date) -> MetricAvailability<NetworkRates> {
        let current: NetworkCounters
        do {
            current = try readNetworkCounters()
        } catch {
            return .unavailable(reason: error.localizedDescription)
        }
        defer { previousNetwork = (current, now) }
        guard let previousNetwork else {
            return .unavailable(reason: "Collecting the network counter baseline")
        }
        guard current.received >= previousNetwork.counters.received,
              current.sent >= previousNetwork.counters.sent
        else {
            return .unavailable(reason: "Network counters reset before this sample")
        }
        let duration = max(0.001, now.timeIntervalSince(previousNetwork.date))
        return .available(NetworkRates(
            downloadBytesPerSecond: UInt64(Double(current.received - previousNetwork.counters.received) / duration),
            uploadBytesPerSecond: UInt64(Double(current.sent - previousNetwork.counters.sent) / duration)
        ))
    }

    private func readNetworkCounters() throws -> NetworkCounters {
        var addressPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addressPointer) == 0, let firstAddress = addressPointer else {
            let code = errno
            let reason = String(cString: strerror(code))
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSLocalizedDescriptionKey: "getifaddrs failed: \(reason)"])
        }
        defer { freeifaddrs(addressPointer) }

        var received: UInt64 = 0
        var sent: UInt64 = 0
        var pointer: UnsafeMutablePointer<ifaddrs>? = firstAddress
        while let address = pointer?.pointee {
            let flags = Int32(address.ifa_flags)
            if flags & IFF_LOOPBACK == 0,
               flags & IFF_UP != 0,
               let data = address.ifa_data?.assumingMemoryBound(to: if_data.self).pointee {
                received += UInt64(data.ifi_ibytes)
                sent += UInt64(data.ifi_obytes)
            }
            pointer = address.ifa_next
        }
        return NetworkCounters(received: received, sent: sent)
    }

    private func samplePower() -> MetricAvailability<BatterySnapshot> {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any]
        else {
            return .unavailable(reason: "No internal battery power source is available")
        }

        guard let current = (description[kIOPSCurrentCapacityKey] as? NSNumber)?.doubleValue,
              let maximum = (description[kIOPSMaxCapacityKey] as? NSNumber)?.doubleValue,
              maximum > 0,
              let charging = description[kIOPSIsChargingKey] as? Bool
        else {
            return .unavailable(reason: "The power source omitted capacity or charging fields")
        }
        let state = description[kIOPSPowerSourceStateKey] as? String ?? "Unknown"
        return .available(BatterySnapshot(
            level: min(1, max(0, current / maximum)),
            isCharging: charging,
            powerSource: state
        ))
    }
}
