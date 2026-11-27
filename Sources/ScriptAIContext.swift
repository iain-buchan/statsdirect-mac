import Cocoa

/// One bounded read of a worksheet, as AI Assist's local "Data used" receipt lists it: the workbook as the
/// Document names it, the sheet, the ranges read (row-1 headings that travelled as column titles as a separate
/// "(headings)" range) and whether the read covered less than the sheet's used range. It stays in the app.
struct WorksheetAIRead: Codable, Equatable {
    let workbook: String
    let sheet: String
    let ranges: [String]
    let partial: Bool

    /// "Fictional.xlsx · Parametric · A1:B1 (headings), A2:B10 (part of the worksheet’s used range)"
    var line: String {
        [workbook, sheet, ranges.joined(separator: ", ")].joined(separator: " · ") + (partial ? " (part of the worksheet’s used range)" : "")
    }

    static func columnName(_ index: Int) -> String {
        var column = index + 1
        var letters: [UInt8] = []
        while column > 0 {
            column -= 1
            letters.append(65 + UInt8(column % 26))
            column /= 26
        }
        return String(decoding: letters.reversed(), as: UTF8.self)
    }

    /// Adjacent columns become one A1 range ("A2:B10"); others are listed separately. The row-1 headings that travelled
    /// as titles come first, as their own "(headings)" ranges, as on Windows.
    static func ranges(columns: [Int], headingColumns: [Int], firstRow: Int, lastRow: Int) -> [String] {
        func runs(_ columns: [Int]) -> [(Int, Int)] {
            var runs: [(Int, Int)] = []
            for column in Set(columns).sorted() {
                if let last = runs.last, column == last.1 + 1 { runs[runs.count - 1].1 = column } else { runs.append((column, column)) }
            }
            return runs
        }
        func area(_ run: (Int, Int), _ top: Int, _ bottom: Int) -> String {
            let first = columnName(run.0) + String(top), last = columnName(run.1) + String(bottom)
            return first == last ? first : first + ":" + last
        }
        return runs(headingColumns).map { area($0, 1, 1) + " (headings)" } + runs(columns).map { area($0, firstRow, lastRow) }
    }
}

/// Read-only, per-question access. No document names or contents enter the
/// provider request until the pane has checked the user's sharing confirmation.
@MainActor final class ScriptAIContext {
    unowned let viewer: Viewer
    let script: Document?
    let report: Document?
    let workbook: Document?
    private let version: Int?
    private let consentRevision: Int?
    private let scriptSnapshot: [String:Any]?
    private var reportSnapshot: [String:Any]?
    private let reportRevision: Int?
    private let reportResultID: String?
    let rSource: String
    private(set) var rData = ""
    /// AI Assist's rules (the Windows LearningInfo boundary): the overview gives the workbook's structure only, so row-1
    /// headings and cell values travel only through the bounded read, and every read is recorded for the receipt.
    let worksheetAssist: Bool
    /// The bounded reads whose results ChatGPTTutor sent for this question, in order and without repeats (worksheetAssist only).
    private(set) var reads: [WorksheetAIRead] = []
    /// Reads made but not yet reported sent, by datasetId: their R data and receipt join the reply only in delivered(_:_:).
    private var pendingReads: [String:(code: String, receipt: WorksheetAIRead?)] = [:]
    private let active: () -> Bool
    init(viewer: Viewer, script: Document?, workbook: Document?, report: Document? = nil, reportResultID: String? = nil,
         usesSessionConsent: Bool = true, worksheetAssist: Bool = false, active: @escaping () -> Bool) {
        self.rSource=script?.rConsolePane?.sourceText ?? (script?.rPane?.language == "R" ? script?.rPane?.editor.string ?? "" : "")
        self.consentRevision=usesSessionConsent ? viewer.aiSharing.revision : nil
        self.worksheetAssist=worksheetAssist
        self.viewer=viewer; self.script=script; self.workbook=workbook; self.version=workbook?.gridVersion; self.active=active
        self.report=report; self.reportRevision=report?.reportRevision; self.reportResultID=reportResultID
        if let script, let pane=script.rConsolePane {
            let source=pane.sourceText, output=pane.outputText
            scriptSnapshot=["documentId":script.id,"title":script.title,"kind":"script","language":"R","script":String(source.prefix(12000)),"output":String(output.suffix(8000)),"truncated":source.count>12000 || output.count>8000,"running":pane.isBusy,"snapshot":true]
        } else if let script, let pane=script.rPane {
            scriptSnapshot=["documentId":script.id,"title":script.title,"kind":"script","language":pane.language,"script":String(pane.editor.string.prefix(12000)),"output":String(pane.console.string.suffix(8000)),"truncated":pane.editor.string.count>12000 || pane.console.string.count>8000,"running":pane.isRunning,"snapshot":true]
        } else { scriptSnapshot=nil }
    }
    var tools: [[String:Any]] {
        TutorTools.definitions.filter { row in
            switch row["name"] as? String {
            case "statsdirect_workspace", "statsdirect_method_help": return true
            case "statsdirect_read_data": return workbook != nil
            case "statsdirect_read_document": return script != nil || report != nil
            default: return false
            }
        }.map { row in
            var tool=row
            switch tool["name"] as? String {
            case "statsdirect_workspace" where worksheetAssist:
                tool["description"]="List the approved workbook's sheets, their row and column extents, column letters and the current selection. It gives no column headings or cell values: read those with statsdirect_read_data. No unapproved documents are exposed."
            case "statsdirect_workspace": tool["description"]="List only documents approved for this question, with worksheet headings and selections. No unapproved documents are exposed."
            case "statsdirect_read_document": tool["description"]="Read the approved, fixed report or script/output snapshot. Returns explicit bounds and truncation. Does not read other documents, run R or alter content."
            case "statsdirect_read_data" where worksheetAssist:
                tool["description"]="Read cells from the approved workbook. Defaults to its selected or used range. Rows are 1-based worksheet numbers; columns and sheetIndex are 0-based. When the first row holds column names, each column's heading is returned as its title. Values preserve missing cells and their original text. At most 32 columns and 4,000 cells per read; never silently sampled. StatsDirect shows the user the ranges each reply read. No engine execution is available."
            case "statsdirect_read_data": tool["description"]="Read cells from the approved workbook. Defaults to its selected or used range. Rows are 1-based worksheet numbers; columns and sheetIndex are 0-based. Values preserve missing cells and their original text. At most 32 columns and 4,000 cells per read; never silently sampled. No engine execution is available."
            default: break
            }
            return tool
        }
    }
    func check() throws {
        try TutorPolicy.check(); try Task.checkCancellation()
        guard active() else { throw CancellationError() }
        if let consentRevision, (script != nil || report != nil || workbook != nil), viewer.aiSharing.revision != consentRevision {
            throw ChatGPTTutor.Failure(message:"The selected data document changed. Confirm sharing for the new document before sending again.")
        }
        for doc in [script,report,workbook].compactMap({$0}) {
            guard viewer.documents.contains(where:{$0 === doc}) else { throw ChatGPTTutor.Failure(message:"A shared document was closed. Send again to choose the current context.") }
        }
        if let workbook, workbook.gridVersion != version { throw ChatGPTTutor.Failure(message:"The workbook changed after confirmation. Send a new question to use its current contents.") }
    }
    func overview() async throws -> [String:Any] {
        try check(); var documents: [[String:Any]]=[]
        if let script { documents.append(["documentId":script.id,"title":script.title,"kind":"script","language":scriptSnapshot?["language"] as? String ?? "R","operation":script.operationName ?? ""]) }
        if let report { documents.append(["documentId":report.id,"title":reportSnapshot?["title"] as? String ?? String(report.title.prefix(200)),"kind":"report"]) }
        if let workbook {
            let info=try await viewer.learningJavaScript(workbook,"window.statsDirectGrid.tutorInfo()")
            try check()
            documents.append(["documentId":workbook.id,"title":workbook.title,"kind":"grid","worksheet":worksheetAssist ? Self.structure(info) : info])
        }
        return ["documents":documents,"sharing":documents.isEmpty ? "Question and conversation only; no application documents are shared." : "Only the listed documents are shared for this question. Reports and script/output are fixed snapshots; workbook reads are bounded and reject content changes."]
    }
    /// The overview AI Assist sends: the fields named here and nothing else, so a field added to tutorInfo later
    /// cannot leak headings. Column titles are left out; `withheld` (a heading that looks like a person identifier,
    /// which the bounded read refuses) is kept, as it carries no heading text and stops a read that would fail.
    static func structure(_ info: [String:Any]) -> [String:Any] {
        let sheetKeys: Set<String> = ["index","name","hidden","firstDataRow","lastDataRow","columnCount","columnsTruncated","selection","range","noncontiguousRows"]
        let sheets = (info["sheets"] as? [[String:Any]] ?? []).map { sheet -> [String:Any] in
            var kept = sheet.filter { sheetKeys.contains($0.key) }
            kept["columns"] = (sheet["columns"] as? [[String:Any]] ?? []).map { column -> [String:Any] in
                var shown: [String:Any] = [:]
                if let index = column["index"] { shown["index"] = index }
                if let letter = column["letter"] { shown["letter"] = letter }
                if column["withheld"] as? Bool == true { shown["withheld"] = true }
                return shown
            }
            return kept
        }
        var structure: [String:Any] = ["sheets":sheets]
        if let active = info["activeSheet"] { structure["activeSheet"] = active }
        return structure
    }
    func context() async throws -> String {
        if report != nil { _ = try await readReport() }
        var payload=try await overview()
        if let scriptSnapshot { payload["currentScript"]=scriptSnapshot }
        if let reportSnapshot { payload["currentReport"]=reportSnapshot }
        var json=String(decoding:try JSONSerialization.data(withJSONObject:payload,options:[.sortedKeys]),as:UTF8.self)
        if json.count>28000 {
            // Keep the initial reference valid and bounded. Detailed worksheet
            // headings and document snapshots remain available through scoped tools.
            payload["documents"]=[script,report,workbook].compactMap{$0}.map{["documentId":$0.id,"kind":$0.kind,"title":String($0.title.prefix(200))]}
            payload["currentScript"]=nil;payload["currentReport"]=nil;payload["readDetailsWithTools"]=true
            json=String(decoding:try JSONSerialization.data(withJSONObject:payload,options:[.sortedKeys]),as:UTF8.self)
        }
        return json
    }
    private func readReport() async throws -> [String:Any] {
        try check()
        if let reportSnapshot { return reportSnapshot }
        guard let report else { throw ChatGPTTutor.Failure(message:"That report was not approved for this question.") }
        guard report.reportRevision == reportRevision else { throw ChatGPTTutor.Failure(message:"The report changed after confirmation. Send a new question to use its current contents.") }
        let snapshot=try await ReportAIContext.snapshot(viewer:viewer,document:report,resultID:reportResultID)
        try check()
        guard report.reportRevision == reportRevision else { throw ChatGPTTutor.Failure(message:"The report changed while preparing the snapshot. Send a new question to use its current contents.") }
        reportSnapshot=snapshot
        return snapshot
    }
    func call(_ name: String, _ arguments: [String:Any]) async throws -> [String:Any] {
        try check()
        guard let spec=tools.first(where:{$0["name"] as? String==name}),
              let schema=spec["inputSchema"] as? [String:Any], let properties=schema["properties"] as? [String:Any],
              Set(arguments.keys).isSubset(of:Set(properties.keys)),
              (schema["required"] as? [String] ?? []).allSatisfy({arguments[$0] != nil}) else { throw ChatGPTTutor.Failure(message:"This question does not allow that AI action.") }
        switch name {
        case "statsdirect_workspace": return try await overview()
        case "statsdirect_read_document":
            if let report, arguments["documentId"] as? String==report.id { return try await readReport() }
            guard let script, arguments["documentId"] as? String==script.id, let scriptSnapshot else { throw ChatGPTTutor.Failure(message:"That document was not approved for this question.") }
            return scriptSnapshot
        case "statsdirect_read_data":
            guard let workbook, arguments["documentId"] as? String==workbook.id else { throw ChatGPTTutor.Failure(message:"That workbook was not approved for this question.") }
            var options=arguments; options.removeValue(forKey:"documentId")
            let json=String(decoding:try JSONSerialization.data(withJSONObject:options),as:UTF8.self)
            guard worksheetAssist else {
                var result=try await viewer.learningJavaScript(workbook,"window.statsDirectGrid.tutorData(\(json))")
                try check()
                result["datasetId"]=UUID().uuidString
                let code=try ConversationRScript.dataset(result)
                result["rCode"]=code; rData += code + "\n"
                return result
            }
            // The sheet's used range comes from the same evaluation as the read, so the receipt's "part of the used range"
            // agrees with the cells read. Only `data` is returned to the provider; `used` stays here.
            let evaluated=try await viewer.learningJavaScript(workbook,"""
                (() => { const grid = window.statsDirectGrid, data = grid.tutorData(\(json)), sheet = grid.tutorInfo().sheets[data.sheetIndex];
                  return {data, used: {firstDataRow: sheet.firstDataRow, lastDataRow: sheet.lastDataRow, columnCount: sheet.columnCount, columns: sheet.columns.map(c => c.index)},
                          headings: data.headerRow ? grid.aiHeadingCells(data.sheetIndex, data.columns.map(c => c.index)) : []}; })()
                """)
            try check()
            guard var result=evaluated["data"] as? [String:Any] else { throw ChatGPTTutor.Failure(message:"The worksheet could not be read. Try again.") }
            let id=UUID().uuidString
            result["datasetId"]=id
            let code=try ConversationRScript.dataset(result)
            result["rCode"]=code
            // Held until ChatGPTTutor reports the result sent (as Windows does, pull request 44): a result it refuses as
            // larger than 200,000 bytes, or holds back because Stop came first, adds neither R data nor a receipt line.
            pendingReads[id]=(code, Self.receipt(result, used: evaluated["used"] as? [String:Any], headings: evaluated["headings"] as? [Int] ?? [],
                                                 workbook: workbook.openedFileURL?.lastPathComponent ?? workbook.title))
            return result
        case "statsdirect_method_help":
            guard let operation=arguments["operation"] as? String, let path=viewer.analysisCatalog[operation]?["help"] as? String else { throw ChatGPTTutor.Failure(message:"Choose a documented StatsDirect method.") }
            guard let file = viewer.bundledMethodHelpFile(path) else { throw ChatGPTTutor.Failure(message:"The method help is unavailable.") }
            return ["operation":operation,"text":LearningWorkspace.plain(try String(contentsOf:file,encoding:.utf8)),"boundedExcerpt":true]
        default: throw ChatGPTTutor.Failure(message:"Unknown AI action.")
        }
    }
    /// ChatGPTTutor sent a tool result (its ToolDelivery). A worksheet read's R data and receipt now belong to the reply;
    /// anything else, an unknown dataset or a repeat report, changes nothing.
    func delivered(_ name: String, _ result: [String:Any]) {
        guard name=="statsdirect_read_data", let id=result["datasetId"] as? String, let read=pendingReads.removeValue(forKey:id) else { return }
        rData += read.code + "\n"
        if let receipt=read.receipt, !reads.contains(receipt) { reads.append(receipt) }
    }
    /// What a read sent, from the read's own result. With the header row on, each column's row-1 heading travelled as
    /// its title; a blank heading sends only the stand-in "Column X", not a cell. `headings` are the read columns whose
    /// row-1 cell holds text, taken by the same evaluation as the read (a heading may itself read "Column X"), so only
    /// they are listed as "(headings)", as on Windows.
    static func receipt(_ result: [String:Any], used: [String:Any]?, headings: [Int], workbook: String) -> WorksheetAIRead? {
        guard let sheet = result["sheet"] as? String, let first = result["firstRow"] as? Int, let last = result["lastRow"] as? Int,
              let read = result["columns"] as? [[String:Any]] else { return nil }
        let columns = read.compactMap { $0["index"] as? Int }
        guard !columns.isEmpty else { return nil }
        let headingColumns = result["headerRow"] as? Bool == true ? headings.filter(columns.contains) : []
        var whole = false
        if let used, let count = used["columnCount"] as? Int, let usedColumns = used["columns"] as? [Int],
           let firstData = used["firstDataRow"] as? Int, let lastData = used["lastDataRow"] as? Int {
            whole = count <= 32 && count == usedColumns.count && Set(usedColumns).isSubset(of: Set(columns))
                && first <= firstData && last >= lastData
        }
        return WorksheetAIRead(workbook: workbook, sheet: sheet,
                               ranges: WorksheetAIRead.ranges(columns: columns, headingColumns: headingColumns, firstRow: first, lastRow: last),
                               partial: !whole)
    }
}
