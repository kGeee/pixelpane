import Foundation

struct ExtractTextAction {
    func run(on result: CaptureResult) -> String {
        result.text
    }
}
