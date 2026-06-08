# Classification

Lightweight content analysis that picks the smart default action shown when a capture result first appears.

## Files

| File | Purpose |
|---|---|
| `TechnicalContentClassifier.swift` | Scores OCR text for technical signals: error keywords (`error`, `exception`, `traceback`), code syntax patterns (braces, indentation, operators), and URLs. Returns a `TechnicalScore` used by `SmartDefaultActionSelector` in `Actions/` to decide whether to show Debug or Explain as the default. |

## Extension points

- **New signals** — add keyword lists or regex patterns to `TechnicalContentClassifier` to detect new content types (e.g. spreadsheet data, log lines, SQL).
- **New default actions** — update `SmartDefaultActionSelector` (`Actions/SmartDefaultActionSelector.swift`) to map new classifier outputs to new `PanelActionState` cases.
- **ML-based classification** — the classifier is intentionally rule-based and synchronous; it can be replaced with a `CoreML` model without changing the call site.
