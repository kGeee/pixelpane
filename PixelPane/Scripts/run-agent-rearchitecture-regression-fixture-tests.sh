#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TMP_BINARY="$(mktemp -t pixel-pane-agent-rearchitecture-regression.XXXXXX)"

cleanup() {
  rm -f "${TMP_BINARY}"
}
trap cleanup EXIT

swiftc \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentKernel/AgentKernelTypes.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentKernel/AgentKernelModelAdapter.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentKernel/AgentKernelModelOutputNormalizer.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentKernel/AgentKernelProtocolAdapters.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentKernel/FixtureAgentKernelAdapter.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentRunTypes.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentRunMetadataAccess.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentRunStorePersistence.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentRunStore.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentRunner.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentModelGateway.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentToolContracts.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentPermissionTypes.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentLocalPathResolver.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentToolCatalog.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentPermissionPolicy.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentSideEffectController.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentLocalEvidencePlanner.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentEvidencePackets.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentEvidenceRecorder.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentEvidenceController.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentFinalAnswerSupportRecorder.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentTaskFrame.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentRunTaskClassification.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentLocalToolExecutor.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentToolLoopController.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentToolOrchestrator.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentRunTraceExport.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentRuntime.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentRunViewModel.swift" \
  "${PROJECT_ROOT}/PixelPane/Scripts/agent-rearchitecture-regression-fixture-tests.swift" \
  -o "${TMP_BINARY}"

"${TMP_BINARY}"
