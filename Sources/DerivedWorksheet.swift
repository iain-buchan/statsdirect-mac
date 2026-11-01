import Foundation

func supportsDerivedWorksheet(_ operation: String) -> Bool {
    operation.hasPrefix("Transform") || ["ApplyFunction","PairDifferences","PairMeans","PairSlopes","Rank","Normal","Standardize","ConvertUnits"].contains(operation)
}

// A new worksheet contains a value snapshot of the source, with derived values
// aligned to the selected rows. The original workbook is never modified.
//
// A source that carries `cells` (lesson data) is copied here. A live worksheet source
// carries only metadata; `sourceColumns` then names the columns the grid must snapshot
// (Grid/analysis-source.mjs snapshotColumns) and the sheet holds the derived cells.
struct DerivedWorksheetPlan {
    let sheet: [String:Any]
    let sourceColumns: [String:Any]?
}
func derivedWorksheet(source: [String:Any]?, range: [String:Any]?, frame: [String:Any]) -> DerivedWorksheetPlan? {
    guard let source, let range, let first=range["firstRow"] as? Int, let last=range["lastRow"] as? Int,
          let columns=source["columns"] as? [String],
          let result=frame["cells"] as? [[String:Any]], let rows=frame["rows"] as? Int,
          let count=frame["columns"] as? Int, frame["headerRow"] as? Bool == true,
          first>0, last>=first, rows-1==last-first+1 else { return nil }
    let hasHeader=(source["firstRow"] as? Int ?? 1)>1
    let offset=hasHeader ? 0 : 1
    let original=source["cells"] as? [[String:Any]]
    let width: Int
    if let original { width=max(1,original.filter{!String(describing:$0["text"] ?? "").isEmpty}.compactMap{$0["col"] as? Int}.max().map{$0+1} ?? 1) }
    else if let known=source["width"] as? Int { width=max(1,known) }
    else { return nil }
    guard width<=columns.count, width+count<=16384, max((source["rows"] as? Int ?? last)+offset,last+offset)<=1048576 else { return nil }
    var cells: [[String:Any]] = []
    if let original {
        cells=original.compactMap { cell -> [String:Any]? in
            guard let col=cell["col"] as? Int, col<width, let row=cell["row"] as? Int else { return nil }
            return ["col":col,"row":row+offset,"text":cell["text"] ?? "","kind":cell["kind"] ?? "text"]
        }
        if !hasHeader { cells += (0..<width).map{["col":$0,"row":0,"text":columns[$0],"kind":"text"]} }
    }
    for cell in result {
        guard let col=cell["col"] as? Int, let row=cell["row"] as? Int else { return nil }
        cells.append(["col":width+col,"row":row==0 ? 0 : first-1+offset+row-1,"text":cell["text"] ?? "","kind":cell["kind"] ?? "text"])
    }
    let sheet: [String:Any] = ["name":frame["name"] ?? "Derived data","rows":max((source["rows"] as? Int ?? last)+offset,last+offset),"columns":width+count,"headerRow":true,"hidden":false,"cells":cells]
    var sourceColumns: [String:Any]? = nil
    if original == nil {
        sourceColumns = ["columns":Array(0..<width),"rowOffset":offset,"header":!hasHeader]
        if let sheetIndex=source["sheet"] as? Int { sourceColumns?["sheet"]=sheetIndex }
        if let sheetName=source["sheetName"] as? String { sourceColumns?["sheetName"]=sheetName }
    }
    return DerivedWorksheetPlan(sheet: sheet, sourceColumns: sourceColumns)
}

// Windows writes every output frame of an operation to the one place the user picked: a new sheet holds the first frame
// and each later frame after it (the pick comes before the selection a step keeps, 5.3.0). The Mac's "new worksheet
// document" does the same: the frames side by side in one sheet, in their order, empty frames left out.
func combinedOutputFrame(_ frames: [[String:Any]]) -> [String:Any]? {
    var cells: [[String:Any]] = [], lengths: [Int] = [], columns = 0, rows = 0, name: String? = nil, headerRow: Bool? = nil
    for frame in frames {
        guard let count = frame["columns"] as? Int, count > 0 else { continue }
        for cell in frame["cells"] as? [[String:Any]] ?? [] {
            guard let col = cell["col"] as? Int, col >= 0, col < count else { continue }
            var moved = cell; moved["col"] = columns + col; cells.append(moved)
        }
        let known = frame["lengths"] as? [Int]
        lengths += (0..<count).map { known?.indices.contains($0) == true ? known![$0] : max(0, (frame["rows"] as? Int ?? 1) - 1) }
        columns += count; rows = max(rows, frame["rows"] as? Int ?? 0)
        if name == nil { name = frame["name"] as? String }
        if headerRow == nil { headerRow = frame["headerRow"] as? Bool }
    }
    guard columns > 0 else { return nil }
    return ["name": name ?? "Analysis data", "rows": max(rows, 1), "columns": columns, "cells": cells, "headerRow": headerRow ?? true, "hidden": false, "lengths": lengths]
}
