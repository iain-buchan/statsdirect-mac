import Cocoa
import WebKit

extension Viewer {
    func learningRecordData(_ html: String, format: ReportFormat) async throws -> Data {
        if format == .html { return Data(html.utf8) }
        if format == .pdf { return try await ReportPDFPrinter.render(html) }
        // A private, script-free view uses the same tested DOCX exporter as reports.
        let document=Document(kind:"report",title:"StatsDirect learning record",access:root)
        document.web.configuration.defaultWebpagePreferences.allowsContentJavaScript=false
        document.web.loadHTMLString(html,baseURL:nil)
        for _ in 0..<200 {
            try Task.checkCancellation()
            if !document.web.isLoading, document.web.url != nil { return try await reportExportData(document,format:.docx) }
            try await Task.sleep(nanoseconds:50_000_000)
        }
        throw LearningTutor.Failure(message:"The learning record could not be prepared for export.")
    }
}
