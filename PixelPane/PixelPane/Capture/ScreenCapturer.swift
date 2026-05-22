import AppKit
import CoreGraphics
import ScreenCaptureKit

enum CaptureError: LocalizedError {
    case screenRecordingPermissionDenied
    case captureFailed
    case captureFailedWithReason(String)

    var errorDescription: String? {
        switch self {
        case .screenRecordingPermissionDenied:
            "Screen Recording permission is required before Pixel Pane can capture a selected region."
        case .captureFailed:
            "Pixel Pane could not capture that region. Check Screen Recording permission in System Settings."
        case .captureFailedWithReason(let reason):
            "Pixel Pane could not capture that region. \(reason)"
        }
    }
}

struct ScreenCapturer {
    func capture(selection: CaptureSelection) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            SCScreenshotManager.captureImage(in: selection.captureRect) { image, error in
                if let error {
                    if !CGPreflightScreenCaptureAccess() {
                        continuation.resume(throwing: CaptureError.screenRecordingPermissionDenied)
                    } else {
                        continuation.resume(throwing: CaptureError.captureFailedWithReason(error.localizedDescription))
                    }
                    return
                }

                guard let image else {
                    let captureError: CaptureError = CGPreflightScreenCaptureAccess()
                        ? .captureFailed
                        : .screenRecordingPermissionDenied
                    continuation.resume(throwing: captureError)
                    return
                }

                continuation.resume(returning: image)
            }
        }
    }
}
