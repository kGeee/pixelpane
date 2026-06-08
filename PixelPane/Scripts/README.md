# Scripts

Build verification and agent runtime fixture tests. All scripts are standalone — no Xcode project open required.

## Build verification

```bash
./verify-debug-build.sh
```

Runs `xcodebuild` in debug configuration and confirms the app compiles cleanly. Run this before opening a PR.

## Fixture tests

Each `run-agent-*.sh` script compiles and runs the corresponding `.swift` fixture file against the live Swift toolchain. These are fast, dependency-free integration tests for the agent subsystems.

| Script | What it tests |
|---|---|
| `run-agent-runner-fixture-tests.sh` | Full agent runner: routing → model request → tool loop |
| `run-agent-tool-calling-fixture-tests.sh` | Tool orchestrator: permission checks, executor dispatch |
| `run-agent-permission-policy-fixture-tests.sh` | `AgentPermissionPolicy` allow/ask/deny decisions |
| `run-agent-run-store-fixture-tests.sh` | SQLite store: session/run/step CRUD and persistence |
| `run-agent-run-view-model-fixture-tests.sh` | `AgentRunViewModel` state projection |
| `run-agent-model-gateway-fixture-tests.sh` | Model conformance probing and caching |
| `run-agent-evidence-packets-fixture-tests.sh` | Evidence deduplication and requirement matching |
| `run-agent-side-effect-controller-fixture-tests.sh` | Side-effect lifecycle: propose → approve → execute → rollback |
| `run-agent-trace-export-fixture-tests.sh` | Markdown trace export correctness |
| `run-agent-rearchitecture-regression-fixture-tests.sh` | Regression suite covering the agent rearchitecture |

Run all fixture tests in one go:

```bash
for f in PixelPane/Scripts/run-agent-*.sh; do bash "$f"; done
```

## Release

`release.sh` builds, signs, notarises, and packages the DMG. **Do not run it** unless you are intentionally cutting a release — see the project `README.md` for the release policy.
