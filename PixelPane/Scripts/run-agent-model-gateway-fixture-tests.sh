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
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentRunTypes.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentKernel/AgentKernelV2Types.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentKernel/AgentKernelModelAdapterV2.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentKernel/AgentKernelModelOutputNormalizerV2.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentKernel/AgentKernelProtocolAdaptersV2.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentKernel/AgentKernelAIBackendAdapterV2.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentKernel/AgentKernelCloudChatAdapterV2.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentKernel/FixtureAgentKernelAdapterV2.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentModelGateway.swift" \
  "${PROJECT_ROOT}/PixelPane/Scripts/agent-model-gateway-fixture-tests.swift" \
  -o "${TMP_BINARY}"

"${TMP_BINARY}"
