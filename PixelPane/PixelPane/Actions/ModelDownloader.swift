import Foundation

/// Cumulative download progress across all files in a model repo.
nonisolated struct ModelDownloadProgress: Sendable, Equatable {
    let completedBytes: Int64
    let totalBytes: Int64
    let currentFile: String

    nonisolated var fractionComplete: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(completedBytes) / Double(totalBytes))
    }
}

/// UI-facing lifecycle of an in-app model download.
nonisolated enum ModelDownloadState: Sendable, Equatable {
    case preparing(repositoryID: String)
    case downloading(repositoryID: String, progress: ModelDownloadProgress)
    case validating(repositoryID: String)
    case failed(repositoryID: String, message: String)

    nonisolated var repositoryID: String {
        switch self {
        case let .preparing(repo), let .downloading(repo, _),
             let .validating(repo), let .failed(repo, _):
            return repo
        }
    }

    nonisolated var isActive: Bool {
        switch self {
        case .preparing, .downloading, .validating: return true
        case .failed: return false
        }
    }
}

/// Lifecycle of the optional one-click Python runtime (mlx-lm / mlx-vlm) install.
nonisolated enum RuntimeInstallState: Sendable, Equatable {
    case installing
    case finished
    case failed(message: String)
}

nonisolated enum ModelDownloadError: LocalizedError {
    case repositoryUnavailable(String)
    case invalidResponse(String)
    case insufficientDisk(neededBytes: Int64, availableBytes: Int64)
    case writeFailed(String)

    nonisolated var errorDescription: String? {
        switch self {
        case let .repositoryUnavailable(repo):
            return "Could not reach \(repo) on Hugging Face. Check your connection and try again."
        case let .invalidResponse(detail):
            return "Unexpected response while downloading: \(detail)"
        case let .insufficientDisk(needed, available):
            let neededStr = ByteCountFormatter.string(fromByteCount: needed, countStyle: .file)
            let availableStr = ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
            return "Not enough free disk space. This model needs about \(neededStr) and only \(availableStr) is available."
        case let .writeFailed(detail):
            return "Could not save the model to disk: \(detail)"
        }
    }
}

/// Downloads a Hugging Face model repo natively (no Python / huggingface-cli)
/// into the standard cache so the existing detector finds it and `mlx_lm`
/// loads it by path. Writes real files under
/// `~/.cache/huggingface/hub/models--{org}--{name}/snapshots/{sha}/`.
///
/// Note: this is a simplified layout (no `blobs/` + symlinks). It is fully
/// usable by Pixel Pane and `mlx_lm --model <path>`; the only tradeoff is that
/// a later `huggingface-cli download` of the same repo would re-fetch rather
/// than dedup against blobs.
actor ModelDownloader {
    private struct RepoInfo: Decodable {
        let sha: String?
    }

    private struct TreeEntry: Decodable {
        let type: String
        let path: String
        let size: Int64
    }

    private let session: URLSession
    private let fileManager: FileManager
    private let homeDirectory: URL

    init(
        session: URLSession = .shared,
        fileManager: FileManager = .default,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.session = session
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
    }

    /// Downloads every file in `repositoryID`, reporting cumulative byte
    /// progress. Returns the snapshot directory containing the model files.
    /// Honors task cancellation between and during files.
    @discardableResult
    func download(
        repositoryID: String,
        onProgress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws -> URL {
        let sha = try await resolveCommitSHA(repositoryID: repositoryID)
        let files = try await listFiles(repositoryID: repositoryID)
        let totalBytes = files.reduce(0) { $0 + $1.size }

        try preflightDiskSpace(neededBytes: totalBytes)

        let modelRoot = MLXVisionModelStore.defaultCacheURL(
            for: repositoryID,
            homeDirectory: homeDirectory
        )
        let snapshotURL = modelRoot
            .appendingPathComponent("snapshots")
            .appendingPathComponent(sha)
        try makeDirectory(snapshotURL)

        var completedBytes: Int64 = 0
        for file in files {
            try Task.checkCancellation()

            let destination = snapshotURL.appendingPathComponent(file.path)

            // Resume-skip: a previously completed file of the right size.
            if let existing = fileSize(at: destination), existing == file.size {
                completedBytes += file.size
                onProgress(ModelDownloadProgress(
                    completedBytes: completedBytes,
                    totalBytes: totalBytes,
                    currentFile: file.path
                ))
                continue
            }

            try await downloadFile(
                repositoryID: repositoryID,
                path: file.path,
                expectedSize: file.size,
                destination: destination,
                baseBytes: completedBytes,
                totalBytes: totalBytes,
                onProgress: onProgress
            )
            completedBytes += file.size
            onProgress(ModelDownloadProgress(
                completedBytes: completedBytes,
                totalBytes: totalBytes,
                currentFile: file.path
            ))
        }

        try writeRef(modelRoot: modelRoot, sha: sha)
        return snapshotURL
    }

    // MARK: - Hugging Face API

    private func resolveCommitSHA(repositoryID: String) async throws -> String {
        let url = URL(string: "https://huggingface.co/api/models/\(repositoryID)")!
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ModelDownloadError.repositoryUnavailable(repositoryID)
        }
        let info = try JSONDecoder().decode(RepoInfo.self, from: data)
        // Fall back to the branch name; the snapshot dir name is cosmetic since
        // models are loaded by absolute path.
        return info.sha ?? "main"
    }

    private func listFiles(repositoryID: String) async throws -> [TreeEntry] {
        let url = URL(string: "https://huggingface.co/api/models/\(repositoryID)/tree/main?recursive=1")!
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ModelDownloadError.repositoryUnavailable(repositoryID)
        }
        let entries = try JSONDecoder().decode([TreeEntry].self, from: data)
        let files = entries.filter { $0.type == "file" }
        guard !files.isEmpty else {
            throw ModelDownloadError.invalidResponse("\(repositoryID) has no downloadable files.")
        }
        return files
    }

    private func downloadFile(
        repositoryID: String,
        path: String,
        expectedSize: Int64,
        destination: URL,
        baseBytes: Int64,
        totalBytes: Int64,
        onProgress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws {
        let encodedPath = path
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        guard let url = URL(string: "https://huggingface.co/\(repositoryID)/resolve/main/\(encodedPath)") else {
            throw ModelDownloadError.invalidResponse("Bad file URL for \(path).")
        }

        let delegate = FileProgressDelegate(
            baseBytes: baseBytes,
            totalBytes: totalBytes,
            fileName: path,
            onProgress: onProgress
        )

        let (tempURL, response): (URL, URLResponse)
        do {
            (tempURL, response) = try await session.download(for: URLRequest(url: url), delegate: delegate)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ModelDownloadError.repositoryUnavailable(repositoryID)
        }

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ModelDownloadError.invalidResponse("Failed to download \(path).")
        }

        try makeDirectory(destination.deletingLastPathComponent())
        if fileManager.fileExists(atPath: destination.path) {
            try? fileManager.removeItem(at: destination)
        }
        do {
            try fileManager.moveItem(at: tempURL, to: destination)
        } catch {
            throw ModelDownloadError.writeFailed("\(path): \(error.localizedDescription)")
        }
    }

    private func writeRef(modelRoot: URL, sha: String) throws {
        let refsDir = modelRoot.appendingPathComponent("refs")
        try makeDirectory(refsDir)
        let mainRef = refsDir.appendingPathComponent("main")
        try? sha.write(to: mainRef, atomically: true, encoding: .utf8)
    }

    // MARK: - Filesystem helpers

    private func preflightDiskSpace(neededBytes: Int64) throws {
        guard let values = try? homeDirectory.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        ), let available = values.volumeAvailableCapacityForImportantUsage else {
            return
        }
        // 10% headroom over the raw download size.
        let needed = Int64(Double(neededBytes) * 1.1)
        if available < needed {
            throw ModelDownloadError.insufficientDisk(neededBytes: needed, availableBytes: available)
        }
    }

    private func makeDirectory(_ url: URL) throws {
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw ModelDownloadError.writeFailed("\(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    private func fileSize(at url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let size = values.fileSize else {
            return nil
        }
        return Int64(size)
    }
}

/// Reports per-file byte progress, offset by the bytes already completed across
/// earlier files, so the consumer sees a single monotonic total.
private final class FileProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let baseBytes: Int64
    private let totalBytes: Int64
    private let fileName: String
    private let onProgress: @Sendable (ModelDownloadProgress) -> Void

    init(
        baseBytes: Int64,
        totalBytes: Int64,
        fileName: String,
        onProgress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) {
        self.baseBytes = baseBytes
        self.totalBytes = totalBytes
        self.fileName = fileName
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        onProgress(ModelDownloadProgress(
            completedBytes: baseBytes + totalBytesWritten,
            totalBytes: totalBytes,
            currentFile: fileName
        ))
    }

    // Required by the protocol; the async `download(for:delegate:)` return value
    // provides the temp file location, so nothing to do here.
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {}
}
