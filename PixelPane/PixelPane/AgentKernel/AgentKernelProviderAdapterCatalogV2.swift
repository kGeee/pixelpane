import Foundation

enum AgentKernelProviderAdapterCatalogV2 {
    nonisolated static func appleLocalTextAdapter(
        backend: AppleFoundationModelsBackend = AppleFoundationModelsBackend()
    ) async -> AgentKernelAIBackendAdapterV2 {
        let descriptor = AgentKernelModelDescriptorV2(
            id: "apple-foundation-models.v2",
            providerKind: .appleLocal,
            route: .local,
            displayName: backend.displayName
        )
        let capabilities = AgentKernelModelAdapterCapabilitiesV2.aiBackendBridge(
            descriptor: descriptor,
            backendCapabilities: await backend.capabilities()
        )
        return AgentKernelAIBackendAdapterV2(
            descriptor: descriptor,
            backend: backend,
            capabilities: capabilities,
            preferredProvider: .appleFoundationModels
        )
    }

    nonisolated static func mlxTextAdapter(
        backend: MLXTextBackend = MLXTextBackend()
    ) async -> AgentKernelAIBackendAdapterV2 {
        let descriptor = AgentKernelModelDescriptorV2(
            id: "mlx-text.v2",
            providerKind: .mlxLocal,
            route: .local,
            displayName: backend.displayName
        )
        let capabilities = AgentKernelModelAdapterCapabilitiesV2.aiBackendBridge(
            descriptor: descriptor,
            backendCapabilities: await backend.capabilities()
        )
        return AgentKernelAIBackendAdapterV2(
            descriptor: descriptor,
            backend: backend,
            capabilities: capabilities,
            preferredProvider: .mlxText
        )
    }

    nonisolated static func pixelPaneCloudAdapter(
        backend: CloudAIBackend
    ) async -> AgentKernelAIBackendAdapterV2 {
        let descriptor = AgentKernelModelDescriptorV2(
            id: "pixel-pane-cloud.v2",
            providerKind: .pixelPaneCloud,
            route: .cloud,
            displayName: backend.displayName
        )
        let capabilities = AgentKernelModelAdapterCapabilitiesV2.aiBackendBridge(
            descriptor: descriptor,
            backendCapabilities: await backend.capabilities()
        )
        return AgentKernelAIBackendAdapterV2(
            descriptor: descriptor,
            backend: backend,
            capabilities: capabilities,
            preferredProvider: .pixelPaneCloud
        )
    }

    nonisolated static func localOpenAICompatibleAdapter(
        endpoint: URL = URL(string: "http://127.0.0.1:11434/v1/chat/completions")!,
        modelName: String? = nil,
        apiKey: String? = nil
    ) -> AgentKernelOpenAICompatibleAdapterV2 {
        AgentKernelOpenAICompatibleAdapterV2(
            descriptor: AgentKernelModelDescriptorV2(
                id: "openai-compatible.local.v2",
                providerKind: .openAICompatible,
                route: .local,
                displayName: "OpenAI-Compatible Local",
                modelName: modelName
            ),
            endpoint: endpoint,
            apiKey: apiKey,
            capabilities: AgentKernelModelAdapterCapabilitiesV2(
                descriptor: AgentKernelModelDescriptorV2(
                    id: "openai-compatible.local.v2",
                    providerKind: .openAICompatible,
                    route: .local,
                    displayName: "OpenAI-Compatible Local",
                    modelName: modelName
                ),
                toolCallingMode: .textProtocol,
                structuredOutputReliability: .bestEffort,
                streamingMode: .unsupported,
                limits: AgentKernelModelLimitsV2(contextWindowTokens: nil),
                isAvailable: true
            )
        )
    }
}
