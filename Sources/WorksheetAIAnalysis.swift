import Cocoa
import WebKit

enum WorksheetAIReportDestination: Equatable {
    case existing(id: String, title: String)
    case new

    var title: String {
        switch self {
        case .existing(_, let title): return title
        case .new: return "New report"
        }
    }
}

/// The selection, its sheet, the workbook's revisions or "First row has column names" changed since the distribution card
/// an offer was chosen on was read, so the card's check is not the evidence for the offer any more.
struct WorksheetAICardChanged: LocalizedError {
    static let message = "The workbook, selection, or report destination changed. Choose the method again."
    var errorDescription: String? { Self.message }
}

/// Another document came in front of the workbook while the grid answered for Continue. Windows takes Continue without waiting,
/// and refuses it while another window is in front, keeping the offer (ScriptAIPane.WorksheetAnalysis.cs:331-335): the offer is
/// left unconsumed, for Continue once the workbook is in front again.
struct WorksheetAINotInFront: Error {}

/// The offer holds only local worksheet metadata. It is never sent to the provider.
@MainActor final class WorksheetAIAnalysisOffer {
    let id = UUID().uuidString
    let methodTitle: String
    let menuPath: String
    let worksheetName: String
    let selectionLabel: String
    var reportTitle: String { destination.title }
    /// The click fingerprint of the moment the selection was captured (Grid/ai-selection.mjs worksheetAISelection).
    let fingerprint: String?
    /// A t test's study design, as Windows gives one to the confirmation of a paired or unpaired t test, whose Change design goes
    /// back to the study-design question (ScriptAIPane.WorksheetAnalysis.cs:266-276): nil for every other method.
    var design: String? { methodID == "TPaired" ? "paired" : methodID == "TUnpaired" ? "independent" : nil }

    fileprivate let methodID: String
    fileprivate let workbookID: String
    fileprivate let gridVersion: Int
    fileprivate let webID: ObjectIdentifier
    fileprivate let selection: WorksheetAISelection
    fileprivate let destination: WorksheetAIReportDestination
    fileprivate var consumed = false

    fileprivate init(method: WorksheetCommand, workbook: Document, selection: WorksheetAISelection, fingerprint: String?,
                     destination: WorksheetAIReportDestination) {
        methodID = method.id
        methodTitle = method.title
        menuPath = (method.path + [method.label]).joined(separator: " › ")
        workbookID = workbook.id
        gridVersion = workbook.gridVersion
        webID = ObjectIdentifier(workbook.web)
        worksheetName = selection.sheetName
        selectionLabel = selection.label
        self.selection = selection
        self.fingerprint = fingerprint
        self.destination = destination
    }
}

private struct WorksheetAISelection: Decodable, Equatable {
    struct Rectangle: Decodable, Equatable {
        let x: Int
        let y: Int
        let width: Int
        let height: Int
    }

    let sheet: Int
    let sheetName: String
    let workbookRevision: Int
    let sheetRevision: Int
    let columns: [Int]
    let rowCount: Int
    let firstRow: Int?
    let lastRow: Int?
    let range: Rectangle?
    let ranges: [Rectangle]

    var canOpenAnalysis: Bool {
        let selectionTypes = [!columns.isEmpty, rowCount > 0, range != nil]
        guard ranges.isEmpty, selectionTypes.filter({ $0 }).count <= 1 else { return false }
        if let firstRow, let lastRow { return lastRow - firstRow + 1 == rowCount }
        return rowCount == 0
    }

    var label: String {
        if let range {
            let first = Self.columnName(range.x) + String(range.y + 1)
            let last = Self.columnName(range.x + range.width - 1) + String(range.y + range.height)
            return first == last ? first : first + ":" + last
        }
        if !columns.isEmpty {
            var groupStarts: [Int] = [], groupEnds: [Int] = []
            for column in columns {
                if groupEnds.last == column - 1 {
                    groupEnds[groupEnds.count - 1] = column
                } else {
                    groupStarts.append(column)
                    groupEnds.append(column)
                }
            }
            let names = zip(groupStarts, groupEnds).prefix(8).map { start, end in
                start == end ? Self.columnName(start) : Self.columnName(start) + ":" + Self.columnName(end)
            }.joined(separator: ", ")
            return "Columns " + names + (groupStarts.count > 8 ? " … (\(columns.count) selected)" : "")
        }
        if let first = firstRow, let last = lastRow {
            return first == last ? "Row \(first + 1)" : "Rows \(first + 1)–\(last + 1)"
        }
        return "Choose data in the analysis form"
    }

    private static func columnName(_ index: Int) -> String {
        var column = index + 1
        var letters: [UInt8] = []
        while column > 0 {
            column -= 1
            letters.append(65 + UInt8(column % 26))
            column /= 26
        }
        return String(decoding: letters.reversed(), as: UTF8.self)
    }
}

extension Viewer {
    var worksheetAIMethods: [WorksheetCommand] {
        worksheetCommands.filter {
            !$0.disabled && analysisCatalog[$0.id] != nil
                && !["AnalysisOptions", "MetaCalculationOptions", "MetaPlotOptions"].contains($0.id)
        }
    }

    var currentReportDestination: Document? {
        documents.first { $0.id == activeReportID && $0.reportEntries != nil }
            ?? documents.last { $0.reportEntries != nil }
    }

    private var worksheetAIReportDestination: WorksheetAIReportDestination {
        guard let report = currentReportDestination else { return .new }
        return .existing(id: report.id, title: report.title)
    }

    func prepareWorksheetAIAnalysis(_ methodID: String, for workbook: Document) async throws -> WorksheetAIAnalysisOffer {
        guard let method = worksheetAIMethods.first(where: { $0.id == methodID }) else {
            throw ConversationRScript.Failure(message: "Choose an available method from Analyse.")
        }
        let destination = worksheetAIReportDestination
        let (selection, fingerprint, _) = try await worksheetAIAnalysisSource(workbook, includeSource: false)
        guard selection.canOpenAnalysis else {
            throw ConversationRScript.Failure(message: "Select one rectangle, worksheet columns, or consecutive rows before choosing a method.")
        }
        guard destination == worksheetAIReportDestination else { throw worksheetAIAnalysisChanged }
        return WorksheetAIAnalysisOffer(method: method, workbook: workbook, selection: selection, fingerprint: fingerprint,
                                        destination: destination)
    }

    /// Opens the offered method for the selection it was made for. `fingerprint`, for an offer chosen on a distribution card,
    /// is the card's reading: a live fingerprint that differs, taken with the source the method is opened with, throws
    /// WorksheetAICardChanged. The workbook must still be the document in front once the page has answered, as the pane requires
    /// it to be when Continue is pressed: a report or any other document brought forward meanwhile throws WorksheetAINotInFront,
    /// the offer unconsumed, and nothing opens behind it.
    func continueWorksheetAIAnalysis(_ offer: WorksheetAIAnalysisOffer, for workbook: Document, fingerprint: String? = nil,
                                     isCurrent: () -> Bool) async throws {
        guard !offer.consumed, isCurrent() else { throw worksheetAIAnalysisChanged }
        offer.consumed = true
        // An edit since a card's reading is that card's to show (its fingerprint holds both revisions), so it is checked below.
        guard offer.workbookID == workbook.id, offer.webID == ObjectIdentifier(workbook.web),
              offer.gridVersion == workbook.gridVersion || fingerprint != nil, offer.destination == worksheetAIReportDestination,
              let method = worksheetAIMethods.first(where: { $0.id == offer.methodID }) else {
            throw worksheetAIAnalysisChanged
        }
        let (selection, live, captured) = try await worksheetAIAnalysisSource(workbook, includeSource: true)
        guard isCurrent() else { throw worksheetAIAnalysisChanged }
        // Checked before the selection, as Windows refuses Continue for another window in front before it opens the proposal,
        // whose target it checks then (ScriptAIPane.WorksheetAnalysis.cs:331-335, :393-397).
        guard active === workbook else {
            offer.consumed = false
            throw WorksheetAINotInFront()
        }
        if let fingerprint, live != fingerprint { throw WorksheetAICardChanged() }
        guard offer.gridVersion == workbook.gridVersion, window.attachedSheet == nil, NSApp.modalWindow == nil,
              let captured, selection == offer.selection, offer.destination == worksheetAIReportDestination else {
            throw worksheetAIAnalysisChanged
        }
        var source = captured
        if let first = selection.firstRow, let last = selection.lastRow {
            source["range"] = ["first": first + 1, "last": last + 1]
        }
        openAnalysisOperation(method.id, label: method.label, sourceID: workbook.id,
                              initialSource: source, reportDestination: offer.destination)
    }

    private var worksheetAIAnalysisChanged: ConversationRScript.Failure {
        ConversationRScript.Failure(message: WorksheetAICardChanged.message)
    }

    /// The selection, with the click fingerprint the page took with it, and, for Continue, the source the analysis opens with.
    private func worksheetAIAnalysisSource(_ workbook: Document, includeSource: Bool) async throws -> (WorksheetAISelection, String?, [String: Any]?) {
        guard workbook.kind == "grid", documents.contains(where: { $0 === workbook }), !workbook.fileBusy else {
            throw worksheetAIAnalysisChanged
        }
        let version = workbook.gridVersion
        let web = workbook.web
        let value = try await web.callAsyncJavaScript(
            """
            const grid = window.statsDirectGrid;
            return {selection: grid.worksheetAISelection(), source: includeSource ? grid.analysisSource() : null};
            """, arguments: ["includeSource": includeSource], in: nil, contentWorld: .page)
        guard documents.contains(where: { $0 === workbook }), workbook.web === web,
              workbook.gridVersion == version, !workbook.fileBusy, let value = value as? [String: Any],
              let selection = value["selection"] as? [String: Any] else { throw worksheetAIAnalysisChanged }
        let json = try JSONSerialization.data(withJSONObject: selection)
        return (try JSONDecoder().decode(WorksheetAISelection.self, from: json), selection["fingerprint"] as? String, value["source"] as? [String: Any])
    }

    @discardableResult
    func appendOperationReport(_ entry: ReportEntry, from analysis: Document) -> Document? {
        switch analysis.operationReportDestination {
        case nil: return appendReport(entry)
        case .new:
            let report = makeReport()
            analysis.operationReportDestination = .existing(id: report.id, title: report.title)
            return appendReport(entry, to: report)
        case .existing(let id, _):
            guard let report = documents.first(where: { $0.id == id && $0.reportEntries != nil }) else {
                operationError(analysis, "The confirmed report was closed. Choose the analysis again to select a report.")
                return nil
            }
            return appendReport(entry, to: report)
        }
    }
}
