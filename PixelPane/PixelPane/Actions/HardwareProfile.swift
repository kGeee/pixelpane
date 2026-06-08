import Foundation

/// A read-only snapshot of the local machine's capacity, used to recommend a
/// local model that actually fits. Values are plain facts; the model-fitting
/// policy lives in `MLXModelCatalog.recommended(for:)`.
///
/// The memberwise initializer keeps this unit-testable: tests inject memory and
/// disk numbers instead of reading the host.
nonisolated struct HardwareProfile: Sendable, Equatable {
    /// Total unified memory, in bytes (`ProcessInfo.physicalMemory`).
    let physicalMemoryBytes: UInt64
    /// CPU brand string, e.g. "Apple M3 Pro". Empty if it could not be read.
    let chipBrand: String
    /// Free space on the home volume that the OS considers safe to use, in
    /// bytes. `nil` if it could not be determined.
    let availableDiskBytes: Int64?

    nonisolated init(
        physicalMemoryBytes: UInt64,
        chipBrand: String,
        availableDiskBytes: Int64?
    ) {
        self.physicalMemoryBytes = physicalMemoryBytes
        self.chipBrand = chipBrand
        self.availableDiskBytes = availableDiskBytes
    }

    /// Reads the current machine.
    nonisolated static func current(
        processInfo: ProcessInfo = .processInfo,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> HardwareProfile {
        HardwareProfile(
            physicalMemoryBytes: processInfo.physicalMemory,
            chipBrand: readChipBrand(),
            availableDiskBytes: readAvailableDiskBytes(at: homeDirectory)
        )
    }

    /// Approximate GiB for display and threshold math (1 GiB = 1024^3 bytes,
    /// matching how Apple markets "8 GB", "16 GB" memory).
    nonisolated var physicalMemoryGiB: Double {
        Double(physicalMemoryBytes) / 1_073_741_824.0
    }

    nonisolated var availableDiskGiB: Double? {
        availableDiskBytes.map { Double($0) / 1_073_741_824.0 }
    }

    /// Short human label, e.g. "Apple M3 Pro · 18 GB".
    nonisolated var displaySummary: String {
        let memory = ByteCountFormatter.string(fromByteCount: Int64(physicalMemoryBytes), countStyle: .memory)
        if chipBrand.isEmpty {
            return memory
        }
        return "\(chipBrand) · \(memory)"
    }

    // MARK: - Probes

    private nonisolated static func readChipBrand() -> String {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else {
            return ""
        }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0) == 0 else {
            return ""
        }
        return String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func readAvailableDiskBytes(at directory: URL) -> Int64? {
        guard let values = try? directory.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        ) else {
            return nil
        }
        return values.volumeAvailableCapacityForImportantUsage
    }
}
