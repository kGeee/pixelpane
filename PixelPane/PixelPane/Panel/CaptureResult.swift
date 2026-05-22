import CoreGraphics
import Foundation

enum CaptureSourceType: String {
    case ocr = "OCR"
    case assistant = "Chat"

    var displayName: String { rawValue }
}

struct CaptureResult: Identifiable {
    let id = UUID()
    let image: CGImage?
    let text: String
    let isEmptyOCRResult: Bool
    let selectionFrame: CGRect
    let createdAt: Date
    let sourceType: CaptureSourceType
    let detectedLanguage: DetectedLanguage
    let technicalClassification: TechnicalContentClassification

    init(
        image: CGImage?,
        text: String,
        isEmptyOCRResult: Bool = false,
        selectionFrame: CGRect,
        createdAt: Date,
        sourceType: CaptureSourceType,
        detectedLanguage: DetectedLanguage,
        technicalClassification: TechnicalContentClassification = TechnicalContentClassification(score: 0, reasons: [])
    ) {
        self.image = image
        self.text = text
        self.isEmptyOCRResult = isEmptyOCRResult
        self.selectionFrame = selectionFrame
        self.createdAt = createdAt
        self.sourceType = sourceType
        self.detectedLanguage = detectedLanguage
        self.technicalClassification = technicalClassification
    }

    var withoutCapturedImage: CaptureResult {
        CaptureResult(
            image: nil,
            text: text,
            isEmptyOCRResult: isEmptyOCRResult,
            selectionFrame: selectionFrame,
            createdAt: createdAt,
            sourceType: sourceType,
            detectedLanguage: detectedLanguage,
            technicalClassification: technicalClassification
        )
    }
}
