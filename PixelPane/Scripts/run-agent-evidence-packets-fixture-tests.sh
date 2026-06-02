#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TMP_BINARY="$(mktemp -t pixel-pane-agent-evidence-packets.XXXXXX)"

cleanup() {
  rm -f "${TMP_BINARY}"
}
trap cleanup EXIT

swiftc \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentKernel/AgentKernelV2Types.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentKernel/AgentKernelModelAdapterV2.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentKernel/AgentKernelModelOutputNormalizerV2.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentRunTypes.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentRunMetadataAccess.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentModelGateway.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentToolContracts.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentPermissionPolicy.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentRunStorePersistence.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentRunStore.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentRunner.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentSideEffectController.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentLocalEvidencePlanner.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentEvidencePackets.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentTaskFrame.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentRunTaskClassification.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentLocalToolExecutor.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentToolOrchestrator.swift" \
  "${PROJECT_ROOT}/PixelPane/Scripts/agent-evidence-packets-fixture-tests.swift" \
  -o "${TMP_BINARY}"

"${TMP_BINARY}"
