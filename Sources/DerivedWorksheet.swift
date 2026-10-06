import Foundation

func supportsDerivedWorksheet(_ operation: String) -> Bool {
    operation.hasPrefix("Transform") || ["ApplyFunction","PairDifferences","PairMeans","PairSlopes","Rank","Normal","Standardize","ConvertUnits"].contains(operation)
}

// A new worksheet contains a value snapshot of the source, with derived values
// aligned to the selected rows. The original workbook is never modified.
func derivedWorksheet(source: [String:Any]?, range: [String:Any]?, frame: [String:Any]) -> [String:Any]? {
    guard let source, let range, let first=range["firstRow"] as? Int, let last=range["lastRow"] as? Int,
          let columns=source["columns"] as? [String], let original=source["cells"] as? [[String:Any]],
          let result=frame["cells"] as? [[String:Any]], let rows=frame["rows"] as? Int,
          let count=frame["columns"] as? Int, frame["headerRow"] as? Bool == true,
          first>0, last>=first, rows-1==last-first+1 else { return nil }
    let hasHeader=(source["firstRow"] as? Int ?? 1)>1
    let offset=hasHeader ? 0 : 1
    let width=max(1,original.filter{!String(describing:$0["text"] ?? "").isEmpty}.compactMap{$0["col"] as? Int}.max().map{$0+1} ?? 1)
    guard width+count<=16384, max((source["rows"] as? Int ?? last)+offset,last+offset)<=1048576 else { return nil }
    var cells=original.compactMap { cell -> [String:Any]? in
        guard let col=cell["col"] as? Int, col<width, let row=cell["row"] as? Int else { return nil }
        return ["col":col,"row":row+offset,"text":cell["text"] ?? "","kind":cell["kind"] ?? "text"]
    }
    if !hasHeader { cells += (0..<width).map{["col":$0,"row":0,"text":columns[$0],"kind":"text"]} }
    for cell in result {
        guard let col=cell["col"] as? Int, let row=cell["row"] as? Int else { return nil }
        cells.append(["col":width+col,"row":row==0 ? 0 : first-1+offset+row-1,"text":cell["text"] ?? "","kind":cell["kind"] ?? "text"])
    }
    return ["name":frame["name"] ?? "Derived data","rows":max((source["rows"] as? Int ?? last)+offset,last+offset),"columns":width+count,"headerRow":true,"hidden":false,"cells":cells]
}
