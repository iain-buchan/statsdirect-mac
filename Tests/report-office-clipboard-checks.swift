import Cocoa
import WebKit

extension ReportExportTests {
    @MainActor static func officeClipboard(_ v: Viewer, output: URL) async throws {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let board = NSPasteboard.withUniqueName(), firstBoard = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally(); firstBoard.releaseGlobally() }
        let report = v.makeReport()
        let entryID = "office-clipboard"
        func svg(_ id: String, _ title: String, _ width: Int, _ margins: String, _ color: String) -> String {
            """
            <svg id="\(id)" aria-label="\(title)" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 300 150" width="300" height="150" style="width:\(width)px;height:auto;\(margins)">
            <defs><clipPath id="\(id)-clip"><rect width="300" height="150"/></clipPath></defs>
            <g clip-path="url(#\(id)-clip)"><rect width="300" height="150" fill="white"/><path d="M10 130L150 20L290 110" stroke="\(color)" fill="none"/><text x="12" y="142" font-size="14">\(title)</text></g></svg>
            """
        }
        let body = """
        <p id="office-note">Keep <strong>selected interpretation</strong> unchanged.</p>
        \(svg("office-first", "First vector chart", 180, "margin-left:auto;margin-right:0px;", "blue"))
        \(svg("office-second", "Second vector chart", 220, "margin-left:auto;margin-right:auto;", "red"))
        <table id="office-table" style="border-collapse:collapse;font-family:'Times New Roman'"><tbody><tr><th>Measure</th><th>Value</th></tr><tr><td style="border:2px solid #123456">Estimate</td><td style="border:2px solid #123456;text-align:right">2.50</td></tr></tbody></table>
        """
        report.reportEntries = [ReportEntry(id: entryID, title: "Office clipboard", operation: "", body: body, record: nil)]
        v.renderReport(report); try await settled(report)
        func js(_ source: String) async throws -> Any? { try await report.web.evaluateJavaScript(source) }
        func choose(_ selector: String, picture: Bool = false) async throws {
            _ = try await js("""
            (()=>{const element=document.querySelector(\(v.jsString(selector))),range=document.createRange();
            const target=\(picture ? "element.closest('.report-media')" : "element");
            \(picture ? "target.focus({preventScroll:true});range.selectNode(target);" : "document.getElementById('report-results').focus({preventScroll:true});range.selectNodeContents(target);")
            getSelection().removeAllRanges();getSelection().addRange(range);})()
            """)
        }
        func selectionState() async throws -> String {
            try await js("""
            (()=>{const s=getSelection(),root=document.getElementById('report-results');
            const path=node=>{const parts=[];for(let n=node;n&&n!==root;n=n.parentNode)parts.unshift([...n.parentNode.childNodes].indexOf(n));return parts;};
            return JSON.stringify({text:s.toString(),anchor:path(s.anchorNode),anchorOffset:s.anchorOffset,focus:path(s.focusNode),focusOffset:s.focusOffset,active:document.activeElement?.id||document.activeElement?.className});})()
            """) as? String ?? ""
        }
        func context(_ selector: String) async throws -> (String, Int) {
            let before = report.reportContext["nativeContextToken"] as? String
            _ = try await report.web.callAsyncJavaScript("""
            document.querySelector(selector).dispatchEvent(new MouseEvent('contextmenu',{bubbles:true,cancelable:true,button:2}));
            await new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)));return true;
            """, arguments: ["selector": selector], in: nil, contentWorld: .page)
            for _ in 0..<100 {
                if let token = report.reportContext["nativeContextToken"] as? String, token != before { return (token, report.reportRevision) }
                try await Task.sleep(nanoseconds: 25_000_000)
            }
            throw LegacyReportError("The chart context did not reach the Mac report host.")
        }
        func vector(_ pasteboard: NSPasteboard, title: String) -> Bool {
            guard let office = pasteboard.data(forType: ReportImageClipboard.officeSVGType),
                  let apple = pasteboard.data(forType: ReportImageClipboard.svgTypes[0]), office == apple,
                  let markup = String(data: office, encoding: .utf8), markup.contains(title),
                  let png = pasteboard.data(forType: .png), let bitmap = NSBitmapImageRep(data: png) else { return false }
            return bitmap.bitsPerSample == 8 && bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0
        }
        func privateGeometry(_ pasteboard: NSPasteboard, width: String, right: String, title: String) async throws -> Bool {
            guard let fragment = pasteboard.string(forType: Viewer.reportFragmentType) else { return false }
            return try await report.web.callAsyncJavaScript("""
            const parsed=new DOMParser().parseFromString(fragment,'text/html'),svg=parsed.querySelector('svg');
            return !!svg&&svg.textContent.includes(title)&&svg.style.width===width&&svg.style.marginLeft==='auto'&&svg.style.marginRight===right;
            """, arguments: ["fragment": fragment, "width": width, "right": right, "title": title], in: nil, contentWorld: .page) as? Bool == true
        }
        try await choose("#office-note strong")
        let selectionBefore = try await selectionState(), revisionBefore = report.reportRevision
        let contentBefore = try await js("StatsDirectReportEditor.serialize(document.getElementById('report-results'))") as? String
        let first = try await context("#office-first")
        let firstCopied = try await v.copyReportChart(report, format: "svg", context: first.0, revision: first.1, pasteboard: firstBoard)
        let firstPrivate = try await privateGeometry(firstBoard, width: "180px", right: "0px", title: "First vector chart")
        precondition(firstCopied && vector(firstBoard, title: "First vector chart") && firstPrivate,
                     "Context Copy publishes identical Office/Apple SVG, an 8-bit PNG fallback and private chart sizing/alignment")
        let selectionAfter = try await selectionState()
        let contentAfter = try await js("StatsDirectReportEditor.serialize(document.getElementById('report-results'))") as? String
        precondition(selectionAfter == selectionBefore && report.reportRevision == revisionBefore && contentAfter == contentBefore,
                     "Context Copy preserves the user's text selection and original report contents")
        try firstBoard.data(forType: ReportImageClipboard.officeSVGType)!.write(to: output.appendingPathComponent("office-context-first.svg"))
        try firstBoard.data(forType: .png)!.write(to: output.appendingPathComponent("office-context-first.png"))

        let second = try await context("#office-second")
        let secondCopied = try await v.copyReportChart(report, format: "svg", context: second.0, revision: second.1, pasteboard: board)
        let secondPrivate = try await privateGeometry(board, width: "220px", right: "auto", title: "Second vector chart")
        precondition(secondCopied && vector(board, title: "Second vector chart") && secondPrivate,
                     "Context Copy follows the second right-clicked chart, with its own width and centre alignment")
        let boardBeforeStale = board.changeCount
        precondition(try await !v.copyReportChart(report, format: "svg", context: first.0, revision: first.1, pasteboard: board)
                     && board.changeCount == boardBeforeStale,
                     "An obsolete right-click context cannot replace clipboard contents")
        v.updateReportText(report, id: entryID, html: body + "<p>Later report edit</p>", refresh: true); try await settled(report)
        precondition(try await !v.copyReportChart(report, format: "svg", context: second.0, revision: second.1, pasteboard: board)
                     && board.changeCount == boardBeforeStale,
                     "A report edit invalidates pending chart Copy commands without changing the clipboard")

        let target = v.makeReport()
        target.reportEntries = [ReportEntry(id: "office-target", title: "Paste destination", operation: "", body: "<p id='office-target'>Paste destination</p>", record: nil)]
        v.renderReport(target); try await settled(target)
        _ = try await target.web.evaluateJavaScript("document.getElementById('report-results').focus();const r=document.createRange();r.selectNodeContents(document.getElementById('office-target'));r.collapse(false);getSelection().removeAllRanges();getSelection().addRange(r)")
        precondition(try await v.transferReportClipboard(target, command: "paste", pasteboard: firstBoard))
        try await settled(target)
        precondition(try await target.web.evaluateJavaScript("(()=>{const s=document.querySelector('.report-body svg');return !!s&&s.textContent.includes('First vector chart')&&s.style.width==='180px'&&s.style.marginLeft==='auto'&&s.style.marginRight==='0px';})()") as? Bool == true,
                     "Pasting a context-copied chart back into a report keeps its vector content, width and right alignment")
        _ = try await target.web.evaluateJavaScript("StatsDirectReportEditor.command('undo')"); try await settled(target)
        precondition(try await target.web.evaluateJavaScript("!document.querySelector('.report-body svg')&&document.getElementById('office-target').textContent==='Paste destination'") as? Bool == true,
                     "Context chart paste participates in the report's unified undo")

        v.tabs.selectTabViewItem(report.item)
        try await choose("#office-first", picture: true)
        precondition(try await v.transferReportClipboard(report, command: "copy", pasteboard: board)
                     && vector(board, title: "First vector chart"),
                     "Regular selected-chart Copy publishes SVG for Office and Apple with the PNG fallback")
        let undoBeforeCut = report.reportUndo.count
        precondition(try await v.transferReportClipboard(report, command: "cut", pasteboard: board))
        try await settled(report)
        let firstRemoved = try await js("!document.getElementById('office-first')") as? Bool == true
        precondition(vector(board, title: "First vector chart") && report.reportUndo.count == undoBeforeCut + 1
                     && firstRemoved,
                     "Regular chart Cut publishes all image formats before removing the selected chart")
        _ = try await js("StatsDirectReportEditor.command('undo')"); try await settled(report)
        precondition(try await js("(()=>{const s=document.getElementById('office-first');return !!s&&s.style.width==='180px'&&s.style.marginLeft==='auto'&&s.style.marginRight==='0px'&&document.querySelectorAll('.report-body svg').length===2;})()") as? Bool == true,
                     "Undo Cut restores the chart, width and alignment without disturbing the second chart")
        try await choose("#office-table")
        precondition(try await v.transferReportClipboard(report, command: "copy", pasteboard: board))
        let tableHTML = board.string(forType: .html) ?? "", tablePrivate = board.string(forType: Viewer.reportFragmentType) ?? ""
        precondition(tableHTML.contains("mso-number-format") && tableHTML.contains("0.00") && tableHTML.contains("x:num=\"2.5\"")
                     && tableHTML.contains("Times New Roman") && tableHTML.contains("border") && tablePrivate.contains("<table")
                     && board.string(forType: .string)?.contains("2.50") == true
                     && board.data(forType: ReportImageClipboard.officeSVGType) == nil && board.data(forType: ReportImageClipboard.svgTypes[0]) == nil,
                     "Table Copy retains HTML, borders, fonts and Excel numeric precision without advertising an unrelated SVG")
        try await engineChartOfficeClipboard(v, output: output)
        print("PASS: Mac report context/selection SVG Office formats, PNG fallback, selection preservation, stale guards, paste/cut undo and Excel table formatting"); fflush(stdout)
    }

    @MainActor static func engineChartOfficeClipboard(_ v: Viewer, output: URL) async throws {
        let fixture = try Data(contentsOf: v.root.appendingPathComponent("Examples/paired-agreement.svg"))
        let original = try XMLDocument(data: fixture, options: .nodeLoadExternalEntitiesNever)
        func count(_ document: XMLDocument, _ element: String) throws -> Int {
            try document.nodes(forXPath: "//*[local-name()='\(element)']").count
        }
        precondition(try count(original, "ellipse") == 9 && count(original, "line") == 19
                     && count(original, "text") == 17 && count(original, "tspan") == 17,
                     "The canonical engine PEFR agreement chart includes all nine observations and seventeen labels")
        let unsupported = Data("<svg xmlns='http://www.w3.org/2000/svg'><text x='1' y='20' font-size='14'>Keep unspecified font</text></svg>".utf8)
        precondition(OfficeSVG.forClipboard(unsupported) == unsupported && OfficeSVG.forClipboard(fixture) == fixture,
                     "Clipboard outlining leaves unspecified fonts and unflattened tspan source byte-identical")
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        let report = v.makeReport()
        report.reportEntries = [ReportEntry(id: "engine-pefr-office", title: "PEFR agreement", operation: "TPaired",
                                           body: "<p>Canonical engine PEFR agreement chart.</p>" + String(decoding: fixture, as: UTF8.self), record: nil)]
        v.renderReport(report); try await settled(report)
        let before = try await report.web.evaluateJavaScript("StatsDirectReportEditor.serialize(document.getElementById('report-results'))") as? String
        let revision = report.reportRevision
        func verify(_ label: String) async throws {
            guard let apple = board.data(forType: ReportImageClipboard.svgTypes[0]),
                  let office = board.data(forType: ReportImageClipboard.officeSVGType), apple == office,
                  let fragment = board.string(forType: Viewer.reportFragmentType),
                  let png = board.data(forType: .png), let bitmap = NSBitmapImageRep(data: png) else {
                throw LegacyReportError("The engine chart clipboard is missing its SVG, PNG or private report representation.")
            }
            let publicSVG = try XMLDocument(data: office, options: .nodeLoadExternalEntitiesNever)
            precondition(try count(publicSVG, "text") == 0 && count(publicSVG, "tspan") == 0
                         && count(publicSVG, "path") >= 17 && count(publicSVG, "ellipse") == 9 && count(publicSVG, "line") == 19
                         && bitmap.bitsPerSample == 8 && bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0,
                         "\(label) outlines the eligible PEFR labels only in matching public SVG representations, retaining every chart point and line")
            let privateUnchanged = try await report.web.callAsyncJavaScript("""
            const parsed=new DOMParser().parseFromString(fragment,'text/html'),svg=parsed.querySelector('svg');
            return !!svg&&svg.querySelectorAll('text').length===17&&svg.querySelectorAll('tspan').length===17&&
              svg.querySelectorAll('ellipse').length===9&&svg.querySelectorAll('line').length===19&&
              svg.textContent.includes('Mean ((PEFR Before + PEFR After) / 2)')&&
              svg.textContent.includes('Difference (PEFR Before - PEFR After)')&&
              svg.textContent.includes('mean difference ± 95% limits of agreement');
            """, arguments: ["fragment": fragment], in: nil, contentWorld: .page) as? Bool == true
            let after = try await report.web.evaluateJavaScript("StatsDirectReportEditor.serialize(document.getElementById('report-results'))") as? String
            precondition(privateUnchanged && before != nil && after == before && report.reportRevision == revision,
                         "\(label) preserves original editable text, tspans, chart geometry, report contents and revision")
            try office.write(to: output.appendingPathComponent("engine-pefr-\(label).svg"))
            try png.write(to: output.appendingPathComponent("engine-pefr-\(label).png"))
        }
        let previousContext = report.reportContext["nativeContextToken"] as? String
        _ = try await report.web.callAsyncJavaScript("""
        document.querySelector('.report-body svg').dispatchEvent(new MouseEvent('contextmenu',{bubbles:true,cancelable:true,button:2}));
        await new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)));return true;
        """, arguments: [:], in: nil, contentWorld: .page)
        var contextToken: String?
        for _ in 0..<100 {
            if let token = report.reportContext["nativeContextToken"] as? String, token != previousContext { contextToken = token; break }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        guard let contextToken else { throw LegacyReportError("The canonical engine chart context did not reach the native report host.") }
        precondition(try await v.copyReportChart(report, format: "svg", context: contextToken, revision: revision, pasteboard: board))
        try await verify("context")
        _ = try await report.web.evaluateJavaScript("""
        (()=>{const svg=document.querySelector('.report-body svg'),target=svg.closest('.report-media'),range=document.createRange();
        target.focus({preventScroll:true});range.selectNode(target);getSelection().removeAllRanges();getSelection().addRange(range);})()
        """)
        precondition(try await v.transferReportClipboard(report, command: "copy", pasteboard: board))
        try await verify("selected")
        print("PASS: Canonical engine PEFR chart public clipboard outlines preserve all geometry, private editable labels and original report contents"); fflush(stdout)
    }
}
