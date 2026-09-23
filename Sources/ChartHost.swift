import Cocoa
import WebKit
import UniformTypeIdentifiers

extension Viewer {
    @objc func saveChartSVG() {
        guard let doc = active, doc.hasSVG else { return }
        doc.web.evaluateJavaScript("document.querySelector('svg')?.outerHTML") { value, error in
            guard error == nil, let svg = value as? String, svg.hasPrefix("<svg") else { self.showError("The report's SVG chart could not be read."); return }
            let panel = NSSavePanel(); panel.allowedContentTypes = [UTType(filenameExtension: "svg")!]
            panel.nameFieldStringValue = "Agreement plot.svg"
            panel.beginSheetModal(for: self.window) { response in
                guard response == .OK, let url = panel.url else { return }
                do { try svg.write(to: url, atomically: true, encoding: .utf8); self.status.stringValue = "Saved vector chart to " + url.lastPathComponent }
                catch { self.showError(error.localizedDescription) }
            }
        }
    }
}
