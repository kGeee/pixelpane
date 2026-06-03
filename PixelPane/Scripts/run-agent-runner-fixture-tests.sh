#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TMP_BINARY="$(mktemp -t pixel-pane-agent-runner.XXXXXX)"

cleanup() {
  rm -f "${TMP_BINARY}"
}
trap cleanup EXIT

swiftc \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentKernel/AgentKernelTypes.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentKernel/AgentKernelModelAdapter.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentKernel/AgentKernelModelOutputNormalizer.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentRunTypes.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentModelGateway.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentToolContracts.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentPermissionPolicy.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentRunStorePersistence.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentRunStore.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentRunner.swift" \
  "${PROJECT_ROOT}/PixelPane/Scripts/agent-runner-fixture-tests.swift" \
  -o "${TMP_BINARY}"

"${TMP_BINARY}"
