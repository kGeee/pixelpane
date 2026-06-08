import Foundation

/// Best-effort one-click installer for the Python MLX runtime
/// (`mlx-lm` + `mlx-vlm` + `huggingface_hub`). This is a guided convenience: if
/// it cannot find `python3` or pip fails, the UI falls back to a copyable
/// command. Output is drained continuously so large pip logs never deadlock the
/// child process.
nonisolated struct MLXRuntimeInstaller: Sendable {
    /// The packages the local runtime needs. Kept in one place so the one-click
    /// path and the copyable command stay in sync.
    static let packages = ["mlx-lm", "mlx-vlm", "huggingface_hub"]

    static var copyableCommand: String {
        "python3 -m pip install -U " + packages.joined(separator: " ")
    }

    private let python3URL: URL

    nonisolated init(python3URL: URL) {
        self.python3URL = python3URL
    }

    /// Runs `python3 -m pip install --user -U <packages>`. Returns `nil` on
    /// success, or a short error message (tail of the pip log) on failure.
    func install() async -> String? {
        await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            let process = Process()
            process.executableURL = python3URL
            process.arguments = ["-m", "pip", "install", "--user", "-U"] + Self.packages

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            let buffer = OutputBuffer()
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty { buffer.append(data) }
            }

            process.terminationHandler = { proc in
                pipe.fileHandleForReading.readabilityHandler = nil
                if proc.terminationStatus == 0 {
                    continuation.resume(returning: nil)
                } else {
                    let log = buffer.string()
                    let tail = log
                        .split(separator: "\n", omittingEmptySubsequences: true)
                        .suffix(8)
                        .joined(separator: "\n")
                    continuation.resume(
                        returning: tail.isEmpty
                            ? "pip exited with status \(proc.terminationStatus)."
                            : tail
                    )
                }
            }

            do {
                try process.run()
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: error.localizedDescription)
            }
        }
    }
}

/// Thread-safe accumulator for a child process's combined output, drained from
/// the pipe's readability handler to avoid the 64 KB pipe-buffer deadlock.
private final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    func string() -> String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
