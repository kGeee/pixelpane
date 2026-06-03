import Foundation

enum AgentKernelProviderAdapterCatalog {
    nonisolated static func appleLocalTextAdapter(
        backend: AppleFoundationModelsBackend = AppleFoundationModelsBackend()
    ) async -> AgentKernelAIBackendAdapter {
        let descriptor = AgentKernelModelDescriptor(
            id: "apple-foundation-models.v2",
            providerKind: .appleLocal,
            route: .local,
            displayName: backend.displayName
        )
        let capabilities = AgentKernelModelAdapterCapabilities.aiBackendBridge(
            descriptor: descriptor,
            backendCapabilities: await backend.capabilities()
        )
        return AgentKernelAIBackendAdapter(
            descriptor: descriptor,
            backend: backend,
            capabilities: capabilities,
            preferredProvider: .appleFoundationModels
        )
    }

    nonisolated static func mlxTextAdapter(
        backend: MLXTextBackend = MLXTextBackend()
    ) async -> AgentKernelAIBackendAdapter {
        let descriptor = AgentKernelModelDescriptor(
            id: "mlx-text.v2",
            providerKind: .mlxLocal,
            route: .local,
            displayName: backend.displayName
        )
        let capabilities = AgentKernelModelAdapterCapabilities.aiBackendBridge(
            descriptor: descriptor,
            backendCapabilities: await backend.capabilities()
        )
        return AgentKernelAIBackendAdapter(
            descriptor: descriptor,
            backend: backend,
            capabilities: capabilities,
            preferredProvider: .mlxText
        )
    }

    nonisolated static func pixelPaneCloudAdapter(
        backend: CloudAIBackend
    ) async -> AgentKernelCloudChatAdapter {
        let descriptor = AgentKernelModelDescriptor(
            id: "pixel-pane-cloud.v2",
            providerKind: .pixelPaneCloud,
            route: .cloud,
            displayName: backend.displayName
        )
        let capabilities = await backend.capabilities()
        return AgentKernelCloudChatAdapter(
            descriptor: descriptor,
            backend: backend,
            backendCapabilities: capabilities,
            preferredProvider: .pixelPaneCloud,
            supportsLocalToolProtocol: true
        )
    }

    nonisolated static func localOpenAICompatibleAdapter(
        endpoint: URL = URL(string: "http://127.0.0.1:11434/v1/chat/completions")!,
        modelName: String? = nil,
        apiKey: String? = nil
    ) -> AgentKernelOpenAICompatibleAdapter {
        AgentKernelOpenAICompatibleAdapter(
            descriptor: AgentKernelModelDescriptor(
                id: "openai-compatible.local.v2",
                providerKind: .openAICompatible,
                route: .local,
                displayName: "OpenAI-Compatible Local",
                modelName: modelName
            ),
            endpoint: endpoint,
            apiKey: apiKey,
            capabilities: AgentKernelModelAdapterCapabilities(
                descriptor: AgentKernelModelDescriptor(
                    id: "openai-compatible.local.v2",
                    providerKind: .openAICompatible,
                    route: .local,
                    displayName: "OpenAI-Compatible Local",
                    modelName: modelName
                ),
                toolCallingMode: .textProtocol,
                structuredOutputReliability: .bestEffort,
                streamingMode: .unsupported,
                limits: AgentKernelModelLimits(contextWindowTokens: nil),
                isAvailable: true
            )
        )
    }
}
