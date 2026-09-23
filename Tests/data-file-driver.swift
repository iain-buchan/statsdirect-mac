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
        case "read-r":
            let book = try RDataFileIO.read(URL(fileURLWithPath:a[2]),script:URL(fileURLWithPath:a[3]))
            try JSONSerialization.data(withJSONObject:book).write(to:URL(fileURLWithPath:a[4]))
        case "write-r":
            let tables = try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:a[2]))) as! [[String:Any]]
            try RDataFileIO.write(tables,to:URL(fileURLWithPath:a[3]),format:a[4],script:URL(fileURLWithPath:a[5]))
        default: fatalError("Unknown command")
        }
    }
}
