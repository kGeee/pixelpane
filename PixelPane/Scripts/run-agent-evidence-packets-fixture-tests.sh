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
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentRunTypes.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentRunStore.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentSideEffectController.swift" \
  "${PROJECT_ROOT}/PixelPane/PixelPane/AgentRuntime/AgentEvidencePackets.swift" \
  "${PROJECT_ROOT}/PixelPane/Scripts/agent-evidence-packets-fixture-tests.swift" \
  -o "${TMP_BINARY}"

"${TMP_BINARY}"
