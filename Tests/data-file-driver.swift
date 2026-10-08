import Foundation
@main struct DataFileDriver {
    static func main() {
        do { try execute() } catch { FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8)); exit(1) }
    }
    static func execute() throws {
        let a = CommandLine.arguments
        switch a[1] {
        case "read-csv": try CSVFileIO.read(URL(fileURLWithPath:a[2])).write(toFile:a[3],atomically:true,encoding:.utf8)
        case "write-csv": try CSVFileIO.write(String(contentsOfFile:a[2],encoding:.utf8),to:URL(fileURLWithPath:a[3]))
        case "read-r":  // read-r <file> <script> <book.json> <snapshot folder>
            let book = try RDataFileIO.read(URL(fileURLWithPath:a[2]),script:URL(fileURLWithPath:a[3]),snapshots:URL(fileURLWithPath:a[5]))
            try JSONSerialization.data(withJSONObject:book).write(to:URL(fileURLWithPath:a[4]))
        case "write-r":  // write-r <snapshot.sdcol> <tables.json> <destination> <format> <script>
            let tables = try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:a[3]))) as! [[String:Any]]
            try RDataFileIO.write(snapshot:URL(fileURLWithPath:a[2]),tables:tables,to:URL(fileURLWithPath:a[4]),format:a[5],script:URL(fileURLWithPath:a[6]))
        case "format-numbers":  // format-numbers <doubles, one per line> <output lines>: JavaScript's String(number)
            let values = try String(contentsOfFile:a[2],encoding:.utf8).split(separator:"\n").map { Double($0)! }
            try values.map(Snapshot.jsNumber).joined(separator:"\n").write(toFile:a[3],atomically:true,encoding:.utf8)
        default: fatalError("Unknown command")
        }
    }
}
