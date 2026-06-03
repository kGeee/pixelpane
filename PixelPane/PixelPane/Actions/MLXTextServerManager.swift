import Foundation
import Darwin

actor MLXTextServerManager {
    static let shared = MLXTextServerManager()

    private let idleTimeout: TimeInterval = 420
    private let startupTimeout: TimeInterval = 45
    private let requestTimeout: TimeInterval = 120

    private var server: WarmServer?
    private var idleTask: Task<Void, Never>?
    private let formatter = ModelOutputFormatter()

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

    func responseIfReady(
        prompt: String,
        maxOutputTokens: Int,
        modelURL: URL,
        executableURL: URL
    ) async throws -> AIModelOutput? {
        guard let server,
              server.modelPath == modelURL.path,
              server.executablePath == executableURL.path,
              server.process.isRunning
        else {
            return nil
        }

        guard await isHealthy(server) else {
            return nil
        }

        do {
            let output = try await requestResponse(
                prompt: prompt,
                maxOutputTokens: maxOutputTokens,
                server: server
            )
            scheduleIdleShutdown()
            return output
        } catch {
            stopServer()
            throw error
        }
    }

    func nativeToolResponse(
        request: AgentKernelModelAdapterRequest,
        modelURL: URL,
        executableURL: URL
    ) async throws -> [AgentKernelModelAdapterEvent] {
        let warmServer = try await readyServer(modelURL: modelURL, executableURL: executableURL)
        scheduleIdleShutdown()

        do {
            let events = try await requestNativeToolResponse(
                request: request,
                server: warmServer
            )
            scheduleIdleShutdown()
            return events
        } catch {
            stopServer()
            throw error
        }
    }

    func warmIfNeeded(modelURL: URL, executableURL: URL) async {
        do {
            _ = try await readyServer(modelURL: modelURL, executableURL: executableURL)
            scheduleIdleShutdown()
        } catch {
            stopServer()
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
           server.process.isRunning {
            if await isHealthy(server) {
                return server
            }
            try await waitUntilHealthy(server)
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
        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }
        try process.run()

        let newServer = WarmServer(
            process: process,
            outputPipe: outputPipe,
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

        return formatter.format(text)
    }

    private func requestNativeToolResponse(
        request adapterRequest: AgentKernelModelAdapterRequest,
        server: WarmServer
    ) async throws -> [AgentKernelModelAdapterEvent] {
        guard let url = URL(string: "http://127.0.0.1:\(server.port)/v1/chat/completions") else {
            throw AIBackendError.unavailable(.generationFailed)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var payload: [String: Any] = [
            "messages": nativeMessages(from: adapterRequest.messages),
            "max_tokens": min(adapterRequest.requestedMaxOutputTokens, 4_096),
            "temperature": 0,
            "stop": ["<|im_end|>"]
        ]
        if !adapterRequest.tools.isEmpty {
            payload["tools"] = adapterRequest.tools.map(nativeToolSchema)
            payload["tool_choice"] = "auto"
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw AIBackendError.unavailable(.generationFailed)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else {
            throw AIBackendError.unavailable(.generationFailed)
        }

        if let toolCalls = message["tool_calls"] as? [[String: Any]],
           let event = nativeToolCallEvent(from: toolCalls) {
            return [event]
        }

        let text = (message["content"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return [.emptyOutput]
        }
        return [.finalAnswer(text)]
    }

    private func nativeMessages(
        from messages: [AgentKernelMessage]
    ) -> [[String: Any]] {
        messages.flatMap { message -> [[String: Any]] in
            switch message.role {
            case .system:
                return [["role": "system", "content": message.content]]
            case .user:
                return [["role": "user", "content": message.content]]
            case .assistant:
                return [["role": "assistant", "content": message.content]]
            case .observation:
                if let toolObservation = nativeToolObservation(from: message.content, messageID: message.id) {
                    return toolObservation
                }
                return [
                    [
                        "role": "user",
                        "content": "Tool/runtime observation:\n\(message.content)"
                    ]
                ]
            }
        }
    }

    private func nativeToolObservation(
        from content: String,
        messageID: UUID
    ) -> [[String: Any]]? {
        let lines = content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        guard lines.first == "Tool result",
              let nameLine = lines.first(where: { $0.hasPrefix("name: ") }) else {
            return nil
        }
        let name = String(nameLine.dropFirst("name: ".count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        let callID = "pixelpane-\(messageID.uuidString)"
        return [
            [
                "role": "assistant",
                "content": "",
                "tool_calls": [
                    [
                        "id": callID,
                        "type": "function",
                        "function": [
                            "name": name,
                            "arguments": "{}"
                        ]
                    ]
                ]
            ],
            [
                "role": "tool",
                "tool_call_id": callID,
                "name": name,
                "content": content
            ],
            [
                "role": "user",
                "content": "Use the tool result above to continue the task. Return a final answer if you have enough information; otherwise call another available tool."
            ]
        ]
    }

    private func nativeToolSchema(
        from tool: AgentKernelToolSchema
    ) -> [String: Any] {
        var properties: [String: Any] = [:]
        for argument in tool.arguments {
            properties[argument.name] = [
                "type": nativeJSONSchemaType(argument.type),
                "description": argument.summary
            ]
        }
        return [
            "type": "function",
            "function": [
                "name": tool.name,
                "description": tool.summary,
                "parameters": [
                    "type": "object",
                    "properties": properties,
                    "required": tool.requiredArguments,
                    "additionalProperties": false
                ]
            ]
        ]
    }

    private func nativeJSONSchemaType(_ type: AgentKernelToolArgumentType) -> String {
        switch type {
        case .string, .jsonString:
            return "string"
        case .integer:
            return "integer"
        case .number:
            return "number"
        case .boolean:
            return "boolean"
        }
    }

    private func nativeToolCallEvent(
        from toolCalls: [[String: Any]]
    ) -> AgentKernelModelAdapterEvent? {
        for rawCall in toolCalls {
            guard let function = rawCall["function"] as? [String: Any],
                  let name = function["name"] as? String,
                  !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            let arguments = nativeToolArguments(from: function["arguments"])
            return .toolCall(
                AgentKernelToolCall(
                    name: name,
                    arguments: arguments
                )
            )
        }
        return nil
    }

    private func nativeToolArguments(from raw: Any?) -> [String: String] {
        let object: Any?
        if let text = raw as? String,
           let data = text.data(using: .utf8) {
            object = try? JSONSerialization.jsonObject(with: data)
        } else {
            object = raw
        }

        guard let dictionary = object as? [String: Any] else {
            return [:]
        }

        return dictionary.reduce(into: [String: String]()) { result, item in
            switch item.value {
            case let value as String:
                result[item.key] = value
            case let value as NSNumber:
                result[item.key] = value.stringValue
            default:
                if JSONSerialization.isValidJSONObject(item.value),
                   let data = try? JSONSerialization.data(withJSONObject: item.value),
                   let text = String(data: data, encoding: .utf8) {
                    result[item.key] = text
                } else {
                    result[item.key] = String(describing: item.value)
                }
            }
        }
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
        server?.outputPipe.fileHandleForReading.readabilityHandler = nil
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
    let outputPipe: Pipe
    let modelPath: String
    let executablePath: String
    let port: Int
}
