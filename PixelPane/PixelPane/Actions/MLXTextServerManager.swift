import Foundation
import Darwin

actor MLXTextServerManager {
    static let shared = MLXTextServerManager()

    private let idleTimeout: TimeInterval = 420
    private let startupTimeout: TimeInterval = 45
    private let requestTimeout: TimeInterval = 120

    private var server: WarmServer?
    private var idleTask: Task<Void, Never>?

    func response(
        prompt: String,
        maxOutputTokens: Int,
        modelURL: URL,
        executableURL: URL
    ) async throws -> AIModelOutput {
        let warmServer = try await readyServer(modelURL: modelURL, executableURL: executableURL)
        scheduleIdleShutdown()

        do {
            let output = try await requestResponse(
                prompt: prompt,
                maxOutputTokens: maxOutputTokens,
                server: warmServer
            )
            scheduleIdleShutdown()
            return output
        } catch {
            stopServer()
            throw error
        }
    }

    func stop() {
        stopServer()
    }

    static func terminateCurrentProcess() async {
        await shared.stop()
    }

    private func readyServer(modelURL: URL, executableURL: URL) async throws -> WarmServer {
        if let server,
           server.modelPath == modelURL.path,
           server.executablePath == executableURL.path,
           server.process.isRunning,
           await isHealthy(server) {
            return server
        }

        stopServer()

        let port = try Self.availablePort()
        let process = Process()
        process.executableURL = executableURL
        process.arguments = [
            "--model", modelURL.path,
            "--host", "127.0.0.1",
            "--port", "\(port)",
            "--allowed-origins", "http://127.0.0.1:\(port)",
            "--chat-template-args", "{\"enable_thinking\":false}",
            "--log-level", "ERROR",
            "--max-tokens", "4096"
        ]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        try process.run()

        let newServer = WarmServer(
            process: process,
            modelPath: modelURL.path,
            executablePath: executableURL.path,
            port: port
        )
        server = newServer

        do {
            try await waitUntilHealthy(newServer)
            return newServer
        } catch {
            stopServer()
            throw error
        }
    }

    private func waitUntilHealthy(_ server: WarmServer) async throws {
        let deadline = Date().addingTimeInterval(startupTimeout)
        while Date() < deadline {
            if !server.process.isRunning {
                throw AIBackendError.unavailable(.generationFailed)
            }
            if await isHealthy(server) {
                return
            }
            try? await Task.sleep(for: .milliseconds(300))
        }
        throw AIBackendError.unavailable(.mlxGenerationTimeout)
    }

    private func isHealthy(_ server: WarmServer) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(server.port)/health") else {
            return false
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    private func requestResponse(
        prompt: String,
        maxOutputTokens: Int,
        server: WarmServer
    ) async throws -> AIModelOutput {
        guard let url = URL(string: "http://127.0.0.1:\(server.port)/v1/chat/completions") else {
            throw AIBackendError.unavailable(.generationFailed)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: [
                "messages": [["role": "user", "content": prompt]],
                "max_tokens": min(maxOutputTokens, 4_096),
                "temperature": 0
            ]
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw AIBackendError.unavailable(.generationFailed)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let choices = json?["choices"] as? [[String: Any]]
        let message = choices?.first?["message"] as? [String: Any]
        let text = message?["content"] as? String ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIBackendError.unavailable(.generationFailed)
        }

        return AIModelOutput(
            finalText: text.trimmingCharacters(in: .whitespacesAndNewlines),
            reasoningText: nil,
            statistics: []
        )
    }

    private func scheduleIdleShutdown() {
        idleTask?.cancel()
        idleTask = Task { [idleTimeout] in
            try? await Task.sleep(for: .seconds(idleTimeout))
            self.stop()
        }
    }

    private func stopServer() {
        idleTask?.cancel()
        idleTask = nil

        if let process = server?.process, process.isRunning {
            process.terminate()
        }
        server = nil
    }

    private static func availablePort() throws -> Int {
        let socketDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard socketDescriptor >= 0 else {
            throw AIBackendError.unavailable(.generationFailed)
        }
        defer { close(socketDescriptor) }

        var value: Int32 = 1
        setsockopt(socketDescriptor, SOL_SOCKET, SO_REUSEADDR, &value, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketDescriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            throw AIBackendError.unavailable(.generationFailed)
        }

        var boundAddress = sockaddr_in()
        var boundLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(socketDescriptor, $0, &boundLength)
            }
        }
        guard nameResult == 0 else {
            throw AIBackendError.unavailable(.generationFailed)
        }

        return Int(UInt16(bigEndian: boundAddress.sin_port))
    }
}

private struct WarmServer {
    let process: Process
    let modelPath: String
    let executablePath: String
    let port: Int
}
