import CoreGraphics
import Vision

enum OCRError: LocalizedError {
    case recognitionFailed

    var errorDescription: String? {
        switch self {
        case .recognitionFailed:
            "Pixel Pane could not read text from that capture."
        }
    }
}

struct OCREngine {
    func recognizeText(in image: CGImage) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            try Self.recognizeTextSynchronously(in: image)
        }.value
    }

    private nonisolated static func recognizeTextSynchronously(in image: CGImage) throws -> String {
        var output: Result<String, Error>?
        let request = VNRecognizeTextRequest { request, error in
            if let error {
                output = .failure(error)
                return
            }

            guard let observations = request.results as? [VNRecognizedTextObservation] else {
                output = .failure(OCRError.recognitionFailed)
                return
            }

            let lines = observations.compactMap { observation in
                observation.topCandidates(1).first?.string
            }

            output = .success(lines.joined(separator: "\n"))
        }

        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        if let output {
            return try output.get()
        }
        throw OCRError.recognitionFailed
    }
}
