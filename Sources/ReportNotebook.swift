import Foundation

/// Notebook formatting and data validation live in the same managed writer as
/// Windows. Swift owns its native save panel, stable report capture and errors.
enum ReportNotebook {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
}
