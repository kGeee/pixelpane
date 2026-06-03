#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TMP_BINARY="$(mktemp -t pixel-pane-agent-model-gateway.XXXXXX)"

cleanup() {
  rm -f "${TMP_BINARY}"
}
trap cleanup EXIT

swiftc \
  "${PROJECT_ROOT}/PixelPane/PixelPane/Actions/AIBackend.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/Actions/ModelDisplayTextNormalizer.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/Actions/ModelOutputFormatter.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentToolContracts.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentPermissionPolicy.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentRunTypes.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentKernel/AgentKernelTypes.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentKernel/AgentKernelModelAdapter.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentKernel/AgentKernelModelOutputNormalizer.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentKernel/AgentKernelProtocolAdapters.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentKernel/AgentKernelAIBackendAdapter.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentKernel/AgentKernelCloudChatAdapter.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentKernel/FixtureAgentKernelAdapter.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentModelGateway.swift" \
  "${PROJECT_ROOT}/PixelPane/Scripts/agent-model-gateway-fixture-tests.swift" \
  -o "${TMP_BINARY}"

"${TMP_BINARY}"
