import SwiftUI

/// Reusable building blocks for hardware-aware local-model setup, shared by the
/// onboarding flow and Settings. They read live state from `AppState`
/// (`hardwareProfile`, `mlxVisionSetupSnapshot`, `modelDownload`,
/// `runtimeInstall`) so progress and status update reactively.

/// Progress / status for an in-flight or failed model download.
struct ModelDownloadProgressView: View {
    let state: ModelDownloadState
    let onCancel: () -> Void
    let onDismissError: () -> Void

    var body: some View {
        switch state {
        case .preparing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Preparing download…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel", action: onCancel).controlSize(.small)
            }
        case let .downloading(_, progress):
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: progress.fractionComplete)
                HStack {
                    Text(byteLabel(progress))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Cancel", action: onCancel).controlSize(.small)
                }
            }
        case .validating:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Validating model…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case let .failed(_, message):
            VStack(alignment: .leading, spacing: 6) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Dismiss", action: onDismissError).controlSize(.small)
            }
        }
    }

    private func byteLabel(_ progress: ModelDownloadProgress) -> String {
        let done = ByteCountFormatter.string(fromByteCount: progress.completedBytes, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: progress.totalBytes, countStyle: .file)
        return "\(done) of \(total) · \(Int(progress.fractionComplete * 100))%"
    }
}

/// Shows whether the Python MLX runtime is present, and guides installing it
/// (one-click best effort + copyable command fallback).
struct RuntimeSetupRow: View {
    @ObservedObject var appState: AppState

    var body: some View {
        if appState.isMLXRuntimeInstalled {
            Label("MLX runtime detected", systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.green)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("MLX runtime needed", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.yellow)
                Text("Local models run through Python's mlx-lm / mlx-vlm. Install it once and the model you download can run on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if case .installing = appState.runtimeInstall {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Installing runtime… this can take a few minutes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    if case let .failed(message) = appState.runtimeInstall {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 8) {
                        Button {
                            appState.installMLXRuntime()
                        } label: {
                            Label("Install Runtime", systemImage: "arrow.down.circle")
                        }
                        Button {
                            appState.copyMLXRuntimeInstallCommand()
                        } label: {
                            Label("Copy Command", systemImage: "doc.on.doc")
                        }
                    }
                    .controlSize(.small)
                }
            }
        }
    }
}

/// The full hardware-aware recommendation + download block used in onboarding.
struct RecommendedModelDownloadView: View {
    @ObservedObject var appState: AppState
    let onChooseFolder: () -> Void

    private var snapshot: MLXVisionSetupSnapshot { appState.mlxVisionSetupSnapshot }
    private var recommended: MLXVisionModel { snapshot.recommendedModel }
    private var hasSelectedModel: Bool { snapshot.selectedModel != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "memorychip")
                    .foregroundStyle(.secondary)
                Text(appState.hardwareProfile.displaySummary)
                    .font(.callout.weight(.medium))
            }

            recommendationCard

            RuntimeSetupRow(appState: appState)

            if let state = appState.modelDownload {
                ModelDownloadProgressView(
                    state: state,
                    onCancel: { appState.cancelModelDownload() },
                    onDismissError: { appState.dismissModelDownloadError() }
                )
            } else if !hasSelectedModel {
                HStack(spacing: 8) {
                    Button {
                        appState.downloadRecommendedModel()
                    } label: {
                        Label("Download · \(recommended.approximateDiskSize)", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Choose Folder…", action: onChooseFolder)
                }
            }
        }
    }

    @ViewBuilder
    private var recommendationCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            if hasSelectedModel {
                Label("Local model ready", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.green)
                Text(snapshot.selectedModel?.repositoryID ?? recommended.repositoryID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("Recommended for your Mac")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(recommended.repositoryID)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("Download size: \(recommended.approximateDiskSize)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
