import Foundation

struct AgentKernelMLXNativeToolAdapterV2: AgentKernelModelAdapterV2 {
    let descriptor: AgentKernelModelDescriptorV2
    let capabilities: AgentKernelModelAdapterCapabilitiesV2

    private let backend: MLXTextBackend
    private let fallback: AgentKernelAIBackendAdapterV2

    nonisolated init(
        descriptor: AgentKernelModelDescriptorV2,
        backend: MLXTextBackend,
        capabilities: AgentKernelModelAdapterCapabilitiesV2,
        preferredProvider: AIBackendProvider? = .mlxText,
        allowsSingleRepairAttempt: Bool = true
    ) {
        self.descriptor = descriptor
        self.backend = backend
        self.capabilities = capabilities
        self.fallback = AgentKernelAIBackendAdapterV2(
            descriptor: descriptor,
            backend: backend,
            capabilities: capabilities,
            preferredProvider: preferredProvider,
            allowsSingleRepairAttempt: allowsSingleRepairAttempt
        )
    }

    nonisolated func response(
        for request: AgentKernelModelAdapterRequestV2
    ) async -> AgentKernelModelAdapterResponseV2 {
        guard request.responseFormat == .native, !request.tools.isEmpty else {
            return await fallback.response(for: request)
        }

        do {
            let events = try await backend.nativeToolResponse(for: request)
            return AgentKernelModelAdapterResponseV2(
                requestID: request.id,
                descriptor: descriptor,
                events: events
            )
        } catch is CancellationError {
            return AgentKernelModelAdapterResponseV2(
                requestID: request.id,
                descriptor: descriptor,
                events: [.timedOut],
                diagnostics: AgentKernelBoundedTextV2("Request was canceled.")
            )
        } catch {
            return AgentKernelModelAdapterResponseV2(
                requestID: request.id,
                descriptor: descriptor,
                events: [.malformedOutput(error.localizedDescription)],
                diagnostics: AgentKernelBoundedTextV2(error.localizedDescription)
            )
        }
    }
}
