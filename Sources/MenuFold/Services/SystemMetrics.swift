import Foundation
import IOKit.ps

struct SystemMetrics {
    let batteryPercent: Int?
    let memoryPressure: Int

    static func current() -> SystemMetrics {
        SystemMetrics(
            batteryPercent: readBatteryPercent(),
            memoryPressure: readMemoryUsagePercent()
        )
    }

    private static func readBatteryPercent() -> Int? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef],
              let source = list.first,
              let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
                as? [String: Any],
              let current = description[kIOPSCurrentCapacityKey] as? Int,
              let maximum = description[kIOPSMaxCapacityKey] as? Int,
              maximum > 0
        else { return nil }
        return Int((Double(current) / Double(maximum) * 100).rounded())
    }

    private static func readMemoryUsagePercent() -> Int {
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        guard total > 0 else { return 0 }

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }

        let pageSize = Double(vm_kernel_page_size)
        let usedPages = Double(stats.active_count + stats.inactive_count + stats.wire_count)
        return min(100, max(0, Int((usedPages * pageSize / total * 100).rounded())))
    }
}
