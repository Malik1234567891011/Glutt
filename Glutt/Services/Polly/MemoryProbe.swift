import Foundation
import os

/// How much memory this process is using, and how much it has left.
///
/// Exists because a wearable camera stream kept ending the app with no crash report
/// and no jetsam event, on a device that had stopped writing either. Guessing at
/// the cause from the outside burned an afternoon. This makes the app say so
/// itself: if `available` walks down to nothing before it dies, it is a memory
/// kill and the footprint says who is eating it. If both sit flat, memory is
/// innocent and the cause is somewhere else entirely.
enum MemoryProbe {
    /// Physical footprint in bytes, the number iOS actually judges for jetsam.
    /// Not `resident_size`, which counts pages the app does not get charged for.
    static var footprintBytes: UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return info.phys_footprint
    }

    /// Bytes still available before this process is killed. Apple's own number,
    /// so it accounts for the device and the current system pressure rather than
    /// a guess at the limit.
    static var availableBytes: UInt64 {
        UInt64(os_proc_available_memory())
    }

    /// "182 MB used · 1.4 GB left"
    static var summary: String {
        let used = Double(footprintBytes) / 1_048_576
        let left = Double(availableBytes) / 1_048_576
        if left >= 1024 {
            return String(format: "%.0f MB used · %.1f GB left", used, left / 1024)
        }
        return String(format: "%.0f MB used · %.0f MB left", used, left)
    }
}
