import Foundation

struct AgentKernelMLXNativeToolAdapter: AgentKernelModelAdapter {
    let descriptor: AgentKernelModelDescriptor
    let capabilities: AgentKernelModelAdapterCapabilities

    private let backend: MLXTextBackend
    private let fallback: AgentKernelAIBackendAdapter

    nonisolated init(
        descriptor: AgentKernelModelDescriptor,
        backend: MLXTextBackend,
        capabilities: AgentKernelModelAdapterCapabilities,
        preferredProvider: AIBackendProvider? = .mlxText,
        allowsSingleRepairAttempt: Bool = true
    ) {
        self.descriptor = descriptor
        self.backend = backend
        self.capabilities = capabilities
        self.fallback = AgentKernelAIBackendAdapter(
            descriptor: descriptor,
            backend: backend,
            capabilities: capabilities,
            preferredProvider: preferredProvider,
            allowsSingleRepairAttempt: allowsSingleRepairAttempt
        )
    }

    nonisolated func response(
        for request: AgentKernelModelAdapterRequest
    ) async -> AgentKernelModelAdapterResponse {
        guard request.responseFormat == .native, !request.tools.isEmpty else {
            return await fallback.response(for: request)
        }

        do {
            let events = try await backend.nativeToolResponse(for: request)
            return AgentKernelModelAdapterResponse(
                requestID: request.id,
                descriptor: descriptor,
                events: events
            )
        } catch is CancellationError {
            return AgentKernelModelAdapterResponse(
                requestID: request.id,
                descriptor: descriptor,
                events: [.timedOut],
                diagnostics: AgentKernelBoundedText("Request was canceled.")
            )
        } catch {
            return AgentKernelModelAdapterResponse(
                requestID: request.id,
                descriptor: descriptor,
                events: [.malformedOutput(error.localizedDescription)],
                diagnostics: AgentKernelBoundedText(error.localizedDescription)
            )
        }
    }
}
