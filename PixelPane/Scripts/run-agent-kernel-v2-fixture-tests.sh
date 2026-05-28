#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TMP_BINARY="$(mktemp -t pixel-pane-agent-kernel-v2.XXXXXX)"

cleanup() {
  rm -f "${TMP_BINARY}"
}
trap cleanup EXIT

swiftc \
  "${PROJECT_ROOT}/PixelPane/PixelPane/App/LocalFileAccess.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/Actions/AIBackend.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/Actions/AssistantHarness.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentKernel/AgentKernelV2Types.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentKernel/AgentKernelSessionLedgerV2.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentKernel/AgentKernelRuntimeGuardsV2.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentKernel/AgentKernelToolRegistryV2.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentKernel/AgentKernelModelAdapterV2.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentKernel/AgentKernelProtocolAdaptersV2.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentKernel/AgentKernelAIBackendAdapterV2.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentKernel/AgentKernelOpenAICompatibleAdapterV2.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentKernel/AgentKernelModelOutputNormalizerV2.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentKernel/AgentKernelLocalContextToolsV2.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentKernel/AgentKernelFiniteCommandToolV2.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentKernel/AgentKernelProcessLifecycleToolV2.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentKernel/AgentKernelEvidenceVerifierV2.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentKernel/AgentKernelEvidencePlanningV2.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentKernel/AgentKernelAnswerabilityGuardV2.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentKernel/AgentKernelChatRuntimeV2.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentKernel/FixtureAgentKernelModelV2.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentKernel/FixtureAgentKernelAdapterV2.swift" \
  "${PROJECT_ROOT}/PixelPane/Scripts/agent-kernel-v2-fixture-tests.swift" \
  -o "${TMP_BINARY}"

"${TMP_BINARY}"
