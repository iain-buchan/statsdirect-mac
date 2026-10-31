import Cocoa
import WebKit

extension ReportExportTests {
    @MainActor static func helpLinkRoundTrips(_ viewer: Viewer, output: URL) async throws {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let destination = "https://www.statsdirect.com/help/parametric_methods/paired_t.htm"
        let label = "Method and worked example →"
        let link = "<a href='\(destination)'>\(label)</a>"
        let record = #"{"version":1,"operation":"TPaired","title":"Paired test","run":"2026-10-31T11:57:00Z","inputs":[],"parameters":{"gamma":0.95},"values":{"mean":56.111111111111114},"data":{"before":[1,2,3],"after":[2,3,5]}}"#
        precondition(RunRecordR.validated(record) == record, "The regression fixture must contain a valid engine run record")
        let seed = viewer.makeReport()
        seed.reportEntries = [ReportEntry(id: "footer-check", title: "Paired test", operation: "TPaired", body: """
        <div><section>
          <p><a href='\(destination)'>Learner's own method link</a></p>
          <p><a href='https://example.org/course'>\(label)</a></p>
          <p>My explanation includes \(link) in a sentence.</p>
          <p>\(link)</p>
          <p>Results follow the learner's links.</p>
          <table style='border:1px solid #112233'><tr><th>Mean</th><td style='text-align:right'>56.111111111111114</td></tr></table>
          <svg xmlns='http://www.w3.org/2000/svg' width='120' height='80' viewBox='0 0 120 80'><circle cx='40' cy='40' r='5'/><text x='10' y='20'>Paired chart</text></svg>
          <p style='font-size:13px;color:#607583'>\(link)</p>
        </section></div><p class='report-links'>\(link)</p>
        """, record: record, recipe: true, helpPath: "Help/parametric_methods/paired_t.htm")]
        viewer.renderReport(seed); try await settled(seed)
        var source = output.appendingPathComponent("help-footer-seed.html")
        try await viewer.reportExportData(seed, format: .html).write(to: source)
        for cycle in 1...3 {
            let opened = try await viewer.importReport(source); try await settled(opened)
            let state = try await opened.web.callAsyncJavaScript("""
            const entry = document.querySelector('article.report-entry');
            const label = 'Method and worked example →';
            const links = [...entry.querySelectorAll('a')];
            const standalone = [...entry.querySelectorAll('p')].filter(p=>p.textContent.trim()===label && p.querySelector('a')?.getAttribute('href')===destination);
            return {links:links.length, standalone:standalone.length, generated:entry.querySelectorAll('.report-links').length,
              authored:links.some(a=>a.textContent==="Learner's own method link") && links.some(a=>a.getAttribute('href')==='https://example.org/course') && entry.textContent.includes('My explanation includes'),
              mean:entry.querySelector('td')?.textContent, tables:entry.querySelectorAll('table').length, charts:entry.querySelectorAll('svg').length,
              align:getComputedStyle(entry.querySelector('td')).textAlign, border:getComputedStyle(entry.querySelector('table')).borderTopWidth,
              help:entry.getAttribute('data-help')};
            """, arguments: ["destination":destination], in: nil, contentWorld: .page) as! [String: Any]
            precondition(state["links"] as? Int == 4 && state["standalone"] as? Int == 1 && state["generated"] as? Int == 0,
                         "Cycle \(cycle): generated footers are removed while the interior authored link is retained")
            precondition(state["authored"] as? Bool == true, "Cycle \(cycle): authored links retain their labels, targets and surrounding prose")
            precondition(state["tables"] as? Int == 1 && state["charts"] as? Int == 1 && state["mean"] as? String == "56.111111111111114"
                         && state["align"] as? String == "right" && state["border"] as? String == "1px",
                         "Cycle \(cycle): report tables, numeric text, borders, alignment and chart survive")
            precondition(opened.reportEntries?.first?.helpPath == "Help/parametric_methods/paired_t.htm" && opened.reportEntries?.first?.record == record,
                         "Cycle \(cycle): Method Help and the exact saved run record remain available")
            let exported = try await viewer.reportExportData(opened, format: .html)
            let html = String(decoding: exported, as: UTF8.self)
            let counts = try await opened.web.callAsyncJavaScript("""
            const page = new DOMParser().parseFromString(html,'text/html');
            return {footers:page.querySelectorAll('article.report-entry .report-links').length,links:page.querySelectorAll('article.report-entry a').length};
            """, arguments: ["html":html], in: nil, contentWorld: .defaultClient) as! [String: Int]
            precondition(counts["footers"] == 0 && counts["links"] == 4, "Cycle \(cycle): Mac HTML export does not manufacture a help footer")
            if cycle == 1 {
                let script = try String(contentsOf: viewer.root.appendingPathComponent("Report/export.js"), encoding: .utf8)
                let compatibility = try await opened.web.callAsyncJavaScript(script + "\nreturn await StatsDirectReportExport.capture(options);",
                    arguments: ["options":["title":"Compatibility", "format":"html", "helpRoot":viewer.root.appendingPathComponent("Help",isDirectory:true).absoluteString]],
                    in: nil, contentWorld: .defaultClient) as! String
                let defaultFooters = try await opened.web.callAsyncJavaScript("return new DOMParser().parseFromString(html,'text/html').querySelectorAll('article.report-entry .report-links').length;",
                    arguments: ["html":compatibility], in: nil, contentWorld: .defaultClient) as? Int
                precondition(defaultFooters == 1, "The shared export helper's unchanged default still adds one link when the Mac opt-out is absent")
            }
            source = output.appendingPathComponent("help-footer-cycle-\(cycle).html")
            try exported.write(to: source)
        }
        print("PASS: three save/reopen cycles remove duplicate help footers, preserve authored links, report formatting, chart, help metadata and exact run records"); fflush(stdout)
    }
}
