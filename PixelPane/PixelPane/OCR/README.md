# OCR

On-device text extraction and language detection. No network calls — both use Apple frameworks.

## Files

| File | Purpose |
|---|---|
| `OCREngine.swift` | Runs `VNRecognizeTextRequest` (Vision framework) on a `CGImage` and returns the concatenated string. Uses the accurate recognition level by default. |
| `LanguageDetector.swift` | Wraps `NLLanguageRecognizer` (NaturalLanguage framework) to return the dominant language and a confidence score for a string. Used to decide whether to surface a Translate action. |

## Extension points

- **Recognition level** — `VNRecognizeTextRequest` supports `.fast` and `.accurate`; expose this as a setting if speed vs. quality matters for a use case.
- **Word-level bounding boxes** — Vision provides per-word geometry; extend `OCREngine` to return `[(String, CGRect)]` if features like highlight-on-hover are added.
- **Additional language hints** — pass `recognitionLanguages` to `VNRecognizeTextRequest` to bias recognition toward a specific script.
