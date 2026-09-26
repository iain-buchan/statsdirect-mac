import Cocoa
import PDFKit

@main struct ReportExportTests {
    @MainActor static func main() {
        let app=NSApplication.shared;app.setActivationPolicy(.regular)
        let viewer=Viewer();app.delegate=viewer
        UserDefaults.standard.set(false,forKey:"automaticUpdateChecks")
        DispatchQueue.main.asyncAfter(deadline:.now()+0.5) {
            Task { @MainActor in
                do {try await run(viewer);print("PASS: native report exports");fflush(stdout)}
                catch {print("FAIL:",error.localizedDescription);fflush(stdout);exit(1)}
                if !CommandLine.arguments.contains("--stay-open") {viewer.closeApproved=true;app.terminate(nil)}
            }
        }
        app.run()
    }
    @MainActor static func run(_ v: Viewer) async throws {
        let output=URL(fileURLWithPath:CommandLine.arguments[1]);try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        func dataset(_ columns:[[Int]]) -> [String:Any] {
            ["complete":true,"rowCount":columns[0].count,"columns":columns.enumerated().map{["title":$0.offset==0 ? "Before":"After","values":$0.element,"index":$0.offset]}]
        }
        for (operation,values) in [("TPaired",[[312,242,340,388,296,254,391,402,290],[300,201,232,312,220,256,328,330,231]]),("Chi2by2",[[12,3],[8,17]])] {
            let result=try await TutorTools.run(operation:operation,dataset:dataset(values),agreement:operation=="TPaired",studyType:"neither",preferences:[:]) { request in
                try await withCheckedThrowingContinuation { c in v.analysisRequest(request,entry:"statsdirect_operation"){c.resume(with:$0)} }
            }
            let entryID=UUID().uuidString
            let plan=try RScriptGenerator.generate(operation:operation,title:operation,output:result,resources:v.root)
            let body="<section class='engine-report'>"+(result["html"] as! String)+"</section>"+v.reportLinks(plan,helpPath:v.analysisCatalog[operation]?["help"] as? String,resultID:entryID)
            v.appendReport(ReportEntry(id:entryID,title:operation,operation:operation,body:body,rPlan:plan))
        }
        let rows=(1...65).map{"<tr><td>Observation \($0)</td><td>\($0).25</td><td>-2.5</td><td>1.2e-7</td></tr>"}.joined()
        v.appendReport(ReportEntry(id:UUID().uuidString,title:"Export table checks",operation:"",body:"<h1>Export table checks</h1><table><thead><tr><th rowspan='2'>Measurement</th><th colspan='3'>Results</th></tr><tr><th>Estimate</th><th>Difference</th><th>P value</th></tr></thead><tbody>\(rows)</tbody></table><p><strong>All report entries included</strong> — α = 0.05, 95% CI, χ<sup>2</sup> and CO<sub>2</sub>.</p>",rPlan:nil))
        let report=v.active!
        for _ in 0..<100 where report.web.isLoading {try await Task.sleep(nanoseconds:100_000_000)}
        for format in ReportFormat.allCases {
            let data=try await v.reportExportData(report,format:format)
            try data.write(to:output.appendingPathComponent("combined-report."+format.rawValue))
            if format == .html {
                let html=String(decoding:data,as:UTF8.self)
                precondition(html.contains("56.111111")&&html.contains("8.64")&&html.contains("Observation 65"))
                precondition(html.contains("<svg")&&html.contains("https://www.statsdirect.com/help/"))
                precondition(!html.contains("onclick=") && !html.contains("statsDirectReport.postMessage") && !html.contains("file:///"))
                print("PASS: HTML contains every result, inline vector chart and portable help links; no app handlers or file paths")
            }
            if format == .pdf {
                let pdf=PDFDocument(data:data)!,text=pdf.string ?? ""
                precondition(pdf.pageCount>1&&text.contains("56.111111")&&text.contains("Observation 65")&&text.contains("All report entries included"))
                for i in 0..<pdf.pageCount {let rect=pdf.page(at:i)!.bounds(for:.mediaBox);precondition(rect.height<900&&rect.width<650)}
                print("PASS: paginated PDF contains all results across \(pdf.pageCount) A4 pages")
            }
            print("Wrote",format.rawValue,data.count,"bytes");fflush(stdout)
        }
        // Exercise the actual WebKit selection path without changing the system clipboard.
        try await report.web.evaluateJavaScript("window.getSelection().selectAllChildren(document.body)")
        let copied=try await v.reportScript(report,method:"clipboard")!
        let clipboard=try JSONSerialization.jsonObject(with:Data(copied.utf8)) as! [String:String]
        precondition(clipboard["html"]!.contains("data:image/png;base64,") && !clipboard["html"]!.contains("<svg"))
        precondition(clipboard["html"]!.contains("x:str=\"Observation 65\"") && clipboard["html"]!.contains("mso-number-format"))
        precondition(clipboard["text"]!.contains("Observation 65\t65.25\t-2.5\t1.2e-7"))
        precondition(!clipboard["text"]!.contains("220240") && !clipboard["html"]!.contains("Continue in R"))
        try Data(clipboard["html"]!.utf8).write(to:output.appendingPathComponent("clipboard.html"))
        try await report.web.evaluateJavaScript("let row=document.querySelector('table').rows[1];let range=document.createRange();range.selectNodeContents(row);let sel=window.getSelection();sel.removeAllRanges();sel.addRange(range);")
        let partial=try await v.reportScript(report,method:"clipboard")!
        let part=try JSONSerialization.jsonObject(with:Data(partial.utf8)) as! [String:String]
        precondition(part["text"]=="3\t17\t20" && part["html"]!.contains("<table"))
        try await report.web.evaluateJavaScript("window.getSelection().removeAllRanges()")
        let empty=try await v.reportScript(report,method:"clipboard")
        precondition(empty==nil)
        print("PASS: full report, partial table row and empty selection clipboard paths; numbers, labels, chart and TSV")
        // Reopened standalone HTML must support all export formats too.
        let reopened=v.newDocument(kind:"report",title:"Reopened HTML",url:output.appendingPathComponent("combined-report.html"),access:output)
        for _ in 0..<100 where reopened.web.isLoading {try await Task.sleep(nanoseconds:100_000_000)}
        let roundtrip=try await v.reportExportData(reopened,format:.docx)
        try roundtrip.write(to:output.appendingPathComponent("reopened-report.docx"))
        print("PASS: standalone HTML reopens and exports to DOCX")
        v.tabs.selectTabViewItem(report.item)
    }
}
