import Cocoa
import WebKit

// Mac mirror of the two report sanitizer checks Windows added for v5.3.9 (f41aad46):
//   tests/WebReports/ImportedUrlAttributes.cs   CheckImportedUrlAttributes   (4 checks)
//   tests/WebReports/ReportSanitizerParity.cs   CheckReportSanitizerParity   (5 checks)
// The sanitizers are the shared report editor's (Report/import.mjs for an opened report, Report/fragment.mjs for a paste). What this
// shows is that in the Mac's WKWebView they give the result Windows asserts of WebView2: an opened or pasted report keeps a chart's
// own url(#id) references and the harmless content, and loses every external or file: address, video, audio, source, track,
// animateColor, poster, background, cite and download. Windows runs its two checks after CheckSvgImportIsolation and so does the Mac
// (after importedRCharts, in the full run and under --svg-isolation-only).
// The payloads, the page scripts, the expected values and the messages are Windows's, unchanged. The host steps are the Mac's own:
//   - Windows opens the text with view.OpenHtmlAsync(html, title); the Mac imports the same text as an HTML file named by the title
//     (Viewer.importReport), which converts it through the same StatsDirectReportImport.convert.
//   - Windows pastes through its typed API (preparePaste, then paste with {html, text: ""}); the Mac's host pastes the same HTML from
//     a private pasteboard (Viewer.transferReportClipboard: preparePaste, then pastePrepared with {html, text: ""}). The host returns
//     true for any paste it handled, so "pastes" here also requires the insertion it reports in the status line, which is the value
//     Windows's paste call returns.
// On the Mac the report is one editable region, so document.querySelector('.report-body') is the whole report, as Windows's scripts
// expect of theirs.
// STATSDIRECT_SANITIZER_COLLECT=1 reports every failing check before failing (for a before and after comparison of two builds);
// without it the first failing check stops the run, as its neighbours do.
extension ReportExportTests {
    @MainActor static func reportSanitizing(_ v: Viewer, output: URL) async throws {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let collect = ProcessInfo.processInfo.environment["STATSDIRECT_SANITIZER_COLLECT"] == "1"
        var failures: [String] = []
        func failure(_ message: String) -> NSError { NSError(domain: "ReportSanitizerTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        func check(_ ok: Bool, _ description: String) throws {
            if ok { print("PASS: " + description); fflush(stdout); return }
            guard collect else { throw failure(description) }
            failures.append(description); print("FAIL (collected): " + description); fflush(stdout)
        }
        func open(_ html: String, title: String) async throws -> Document {
            let url = output.appendingPathComponent(title + ".html")
            try html.write(to: url, atomically: true, encoding: .utf8)
            let report = try await v.importReport(url); try await settled(report)
            return report
        }
        // Windows's caret step, unchanged but for returning the paragraph it chose: the end of the report's last paragraph.
        func paste(_ html: String, into report: Document) async throws -> Bool {
            let paragraph = try await report.web.evaluateJavaScript(#"(()=>{const b=document.querySelector('.report-body');b.focus();const p=b.querySelector('p:last-child');const r=document.createRange();r.selectNodeContents(p);r.collapse(false);getSelection().removeAllRanges();getSelection().addRange(r);return p.textContent;})()"#) as? String
            guard paragraph == "Paste here" else { throw failure("the caret for the paste belongs at the end of the paragraph \"Paste here\", not \(paragraph ?? "nowhere")") }
            let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
            board.setString(html, forType: .html)
            v.status.stringValue = ""
            let handled = try await v.transferReportClipboard(report, command: "paste", pasteboard: board)
            let inserted = v.status.stringValue == "Pasted report content"
            try await settled(report)
            return handled && inserted
        }

        // tests/WebReports/ImportedUrlAttributes.cs: an opened report is sanitized as a paste is. An SVG presentation attribute (fill,
        // stroke, filter, clip-path, mask, marker-*) that names an external url(...) is removed, while a reference to the chart's own
        // definitions is kept, renamed with its IDs.
        func importedUrlAttributes() async throws {
            let svg = """
            <svg xmlns="http://www.w3.org/2000/svg" width="120" height="60" viewBox="0 0 120 60">
              <defs>
                <linearGradient id="own-paint"><stop offset="0" stop-color="#235f89"/><stop offset="1" stop-color="#235f89"/></linearGradient>
                <clipPath id="own-clip"><rect width="60" height="60"/></clipPath>
                <marker id="own-marker" markerWidth="4" markerHeight="4" refX="2" refY="2"><circle cx="2" cy="2" r="2"/></marker>
              </defs>
              <rect width="60" height="60" fill="url(#own-paint)" clip-path="url('#own-clip')"/>
              <path d="M10 50L50 10" stroke="#000" marker-end="url(#own-marker)"/>
              <rect x="60" width="60" height="60" fill="url(https://invalid.example/paint.svg#p)" stroke="url('http://invalid.example/stroke.svg#s')"
                filter="url(//invalid.example/filter.svg#f)" clip-path="url(https://invalid.example/clip.svg#c)" mask="URL( https://invalid.example/mask.svg#m )"/>
              <path d="M70 50L110 10" stroke="#000" marker-start="url(https://invalid.example/m.svg#a)" marker-mid="url(file:///C:/m.svg#b)" marker-end="url(https://invalid.example/m.svg#c)"/>
            </svg>
            """
            // every attribute of a chart, other than its style, that holds a url(...): its element, its name and whether it names one
            // of the same chart's own definitions
            func references(_ report: Document, chart: Int) async throws -> [String] {
                guard let found = try await report.web.evaluateJavaScript(#"""
                (()=>{
                  const svg=document.querySelectorAll('.report-body svg')[\#(chart)],own=new Set([...svg.querySelectorAll('[id]')].map(e=>e.id));
                  const result=[];
                  for(const el of [svg,...svg.querySelectorAll('*')])for(const attr of [...el.attributes]){
                    if(attr.name==='style'||!/url\s*\(/i.test(attr.value))continue;
                    const match=/^url\(\s*["']?#([^"')]+)["']?\s*\)$/i.exec(attr.value.trim());
                    result.push(el.localName+' '+attr.name+' '+(match&&own.has(match[1])?'own':'external '+attr.value));
                  }
                  return result;
                })()
                """#) as? [String] else { throw failure("the url(...) references of chart \(chart) could not be read from the report") }
                return found.sorted()   // attribute order is the sanitizer's
            }
            let expected = ["rect fill own", "rect clip-path own", "path marker-end own"].sorted()
            let report = try await open("<p>Opened chart</p>" + svg + "<p>Paste here</p>", title: "External SVG references")
            let opened = try await references(report, chart: 0)
            try check(opened == expected, "an opened report keeps a chart's own url(#...) references and removes external ones from fill, stroke, filter, clip-path, mask and markers: " + opened.joined(separator: "; "))
            try check(try await report.web.evaluateJavaScript("!document.querySelector('.report-body').innerHTML.includes('invalid.example') && !document.querySelector('.report-body').innerHTML.includes('file:')") as? Bool == true,
                "no external address of the opened chart reaches the report")

            try check(try await paste(svg, into: report), "the same chart pastes through the typed report API")
            let pasted = try await references(report, chart: 1)
            try check(pasted == opened, "opening and pasting the chart keep the same references: " + pasted.joined(separator: "; "))
        }

        // tests/WebReports/ReportSanitizerParity.cs: opening a report and pasting into one sanitize alike (StatsDirect Mac review F8,
        // 9 November 2026). A paste kept a video poster and table and cell backgrounds that opening removes, and both paths kept
        // animateColor. A style attribute keeps only its filtered declarations, so an external image in MathML or behind image-set()
        // reaches neither path.
        func sanitizerParity() async throws {
            let payload = """
            <video poster="https://invalid.example/poster.png"></video>
            <table background="https://invalid.example/t.png"><tr><td background="//invalid.example/c.png">c</td></tr></table>
            <svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="9" height="9"><rect fill="red" width="9" height="9"><animateColor attributeName="fill" values="red;blue" dur="1s" repeatCount="indefinite"/></rect><animateColor xlink:href="#t" attributeName="href" values="javascript:alert(1)"/></svg>
            <math><mi style="background-image:url(https://invalid.example/m.png);color:red">x</mi></math>
            <p style="mask:image-set(&quot;https://invalid.example/m.png&quot; 1x);color:red">p</p>
            """
            // what reached the report body that neither path may keep, and how many copies of the harmless content arrived
            func inspect(_ report: Document) async throws -> (leaks: [String], cells: Int, rects: Int) {
                guard let found = try await report.web.evaluateJavaScript(#"""
                (()=>{
                  const body=document.querySelector('.report-body'),leaks=[];
                  for(const el of body.querySelectorAll('*')){
                    const name=el.localName.toLowerCase();
                    if(['video','audio','source','track','animatecolor'].includes(name))leaks.push('element '+name);
                    for(const attr of [...el.attributes])
                      if(['poster','background','cite','download'].includes(attr.name.toLowerCase())||/invalid\.example|javascript:/i.test(attr.value))leaks.push(name+' '+attr.name+'="'+attr.value+'"');
                  }
                  return {leaks,cells:[...body.querySelectorAll('td')].filter(td=>td.textContent==='c').length,
                    rects:[...body.querySelectorAll('rect')].filter(r=>r.getAttribute('fill')==='red').length};
                })()
                """#) as? [String: Any], let leaks = found["leaks"] as? [String], let cells = found["cells"] as? Int, let rects = found["rects"] as? Int
                else { throw failure("the report body could not be inspected") }
                return (leaks, cells, rects)
            }
            let report = try await open("<p>Opened content</p>" + payload + "<p>Paste here</p>", title: "Sanitizer parity")
            let opened = try await inspect(report)
            try check(opened.leaks.isEmpty, "an opened report keeps no media element, poster, background or animateColor and no external address: " + opened.leaks.joined(separator: "; "))
            try check(opened.cells == 1 && opened.rects == 1, "an opened report keeps the table cell and the chart's rectangle (\(opened.cells) cells, \(opened.rects) rectangles)")

            try check(try await paste(payload, into: report), "the same content pastes through the typed report API")
            let pasted = try await inspect(report)
            try check(pasted.leaks.isEmpty, "a paste keeps no media element, poster, background or animateColor and no external address, as opening does: " + pasted.leaks.joined(separator: "; "))
            try check(pasted.cells == 2 && pasted.rects == 2, "a paste keeps the table cell and the chart's rectangle (\(pasted.cells) cells, \(pasted.rects) rectangles)")
        }

        // Collecting, a check that cannot be made (the page script failed, the caret could not be placed) is a failure of its group
        // and the other group still runs.
        do { try await importedUrlAttributes() } catch let error where collect { failures.append("imported url attributes stopped: " + error.localizedDescription); print("FAIL (collected): " + failures.last!); fflush(stdout) }
        do { try await sanitizerParity() } catch let error where collect { failures.append("sanitizer parity stopped: " + error.localizedDescription); print("FAIL (collected): " + failures.last!); fflush(stdout) }
        if !failures.isEmpty { throw failure("\(failures.count) report sanitizer checks failed: " + failures.joined(separator: " | ")) }
    }
}
