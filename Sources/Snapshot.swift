import Foundation

// Typed columnar worksheet snapshot, the format shared with Grid/snapshot.mjs and
// FullEngine/WorkbookIO.cs. Little-endian. Header: "SCOL" u32, version u32 (1), sheet count
// u32, flags u32 (bit 0: every column carries an extras group). Sheet: name length u32, UTF-8
// name, pad to 4, column count u32. Column: index u32, cell count n u32, text count u32,
// formula count u32, (extras count u32 when flagged), rows u32[n], kinds u8[n], pad to 8,
// numbers f64[n], then the text, formula and extras entries (cell ordinal u32, byte length
// u32, UTF-8), each group padded to 4. Kinds: 0 blank, 1 number, 2 text, 3 datetime,
// 4 timespan, 5 boolean, 6 error. A number cell carries its value; other kinds carry text.
// An extras entry is a JSON object of loader metadata for the cell (the R data markers).
struct SnapshotColumn {
    var col: Int
    var rows: [UInt32] = []
    var kinds: [UInt8] = []
    var nums: [Double] = []
    var texts: [Int: String] = [:]
    var formulas: [Int: String] = [:]
    var extras: [Int: String] = [:]
}
struct SnapshotSheet {
    var name: String
    var columns: [SnapshotColumn]
}
enum Snapshot {
    static let magic: UInt32 = 0x4C4F4353
    struct Failure: LocalizedError { let message: String; var errorDescription: String? { message } }
    private static func align(_ p: Int, _ a: Int) -> Int { (p + a - 1) & ~(a - 1) }

    static func decode(_ data: Data) throws -> [SnapshotSheet] {
        let bytes = [UInt8](data)
        var p = 0
        func u32() throws -> Int {
            guard p + 4 <= bytes.count else { throw Failure(message: "The worksheet snapshot is truncated.") }
            let v = UInt32(bytes[p]) | UInt32(bytes[p + 1]) << 8 | UInt32(bytes[p + 2]) << 16 | UInt32(bytes[p + 3]) << 24
            p += 4; return Int(v)
        }
        func string(_ length: Int) throws -> String {
            guard p + length <= bytes.count else { throw Failure(message: "The worksheet snapshot is truncated.") }
            let s = String(decoding: bytes[p..<p + length], as: UTF8.self); p += length; return s
        }
        func group(_ count: Int) throws -> [Int: String] {
            var map: [Int: String] = [:]
            for _ in 0..<count { let ordinal = try u32(); let length = try u32(); map[ordinal] = try string(length) }
            p = align(p, 4); return map
        }
        guard try u32() == Int(magic), try u32() == 1 else { throw Failure(message: "The worksheet snapshot is not in a recognised format.") }
        let sheetCount = try u32(), flags = try u32()
        var sheets: [SnapshotSheet] = []
        for _ in 0..<sheetCount {
            let name = try string(try u32()); p = align(p, 4)
            let columnCount = try u32()
            var columns: [SnapshotColumn] = []
            for _ in 0..<columnCount {
                let col = try u32(), n = try u32(), textCount = try u32(), formulaCount = try u32()
                let extraCount = flags & 1 != 0 ? try u32() : 0
                guard align(p + 5 * n, 8) + 8 * n <= bytes.count else { throw Failure(message: "The worksheet snapshot is truncated.") }
                var column = SnapshotColumn(col: col)
                column.rows.reserveCapacity(n); column.nums.reserveCapacity(n)
                for _ in 0..<n { column.rows.append(UInt32(try u32())) }
                column.kinds = Array(bytes[p..<p + n]); p = align(p + n, 8)
                bytes.withUnsafeBytes { raw in
                    for i in 0..<n { column.nums.append(Double(bitPattern: raw.loadUnaligned(fromByteOffset: p + 8 * i, as: UInt64.self).littleEndian)) }
                }
                p += 8 * n
                column.texts = try group(textCount); column.formulas = try group(formulaCount)
                if flags & 1 != 0 { column.extras = try group(extraCount) }
                columns.append(column)
            }
            sheets.append(SnapshotSheet(name: name, columns: columns))
        }
        return sheets
    }

    static func encode(_ sheets: [SnapshotSheet]) -> Data {
        var out = Data()
        func u32(_ v: Int) { var x = UInt32(v).littleEndian; withUnsafeBytes(of: &x) { out.append(contentsOf: $0) } }
        func pad(_ a: Int) { while out.count % a != 0 { out.append(0) } }
        func group(_ map: [Int: String]) {
            for ordinal in map.keys.sorted() { let bytes = Array(map[ordinal]!.utf8); u32(ordinal); u32(bytes.count); out.append(contentsOf: bytes) }
            pad(4)
        }
        let flags = sheets.contains { $0.columns.contains { !$0.extras.isEmpty } } ? 1 : 0
        u32(Int(magic)); u32(1); u32(sheets.count); u32(flags)
        for sheet in sheets {
            let name = Array(sheet.name.utf8); u32(name.count); out.append(contentsOf: name); pad(4)
            u32(sheet.columns.count)
            for column in sheet.columns {
                let n = column.rows.count
                precondition(column.kinds.count == n && column.nums.count == n, "Snapshot column arrays differ in length.")
                u32(column.col); u32(n); u32(column.texts.count); u32(column.formulas.count)
                if flags & 1 != 0 { u32(column.extras.count) }
                for r in column.rows { var x = r.littleEndian; withUnsafeBytes(of: &x) { out.append(contentsOf: $0) } }
                out.append(contentsOf: column.kinds); pad(8)
                for v in column.nums { var x = v.bitPattern.littleEndian; withUnsafeBytes(of: &x) { out.append(contentsOf: $0) } }
                group(column.texts); group(column.formulas)
                if flags & 1 != 0 { group(column.extras) }
            }
        }
        return out
    }

    // JavaScript's String(number): the shortest round-trip digits in ECMAScript's layout, so
    // a number formatted natively matches what the grid shows (Swift's own description gives
    // "100.0" and "1e-07" where JavaScript gives "100" and "1e-7").
    static func jsNumber(_ v: Double) -> String {
        if v.isNaN { return "NaN" }
        if v.isInfinite { return v > 0 ? "Infinity" : "-Infinity" }
        if v == 0 { return "0" }
        var s = "\(abs(v))"
        var exponent = 0
        if let e = s.firstIndex(where: { $0 == "e" || $0 == "E" }) { exponent = Int(s[s.index(after: e)...].replacingOccurrences(of: "+", with: "")) ?? 0; s = String(s[..<e]) }
        var digits = s, intDigits = s.count
        if let point = s.firstIndex(of: ".") { intDigits = s.distance(from: s.startIndex, to: point); digits.remove(at: point) }
        while digits.count > 1 && digits.first == "0" { digits.removeFirst(); intDigits -= 1 }
        while digits.count > 1 && digits.last == "0" { digits.removeLast() }
        let k = digits.count, n = intDigits + exponent
        var body: String
        if k <= n && n <= 21 { body = digits + String(repeating: "0", count: n - k) }
        else if 0 < n && n <= 21 { body = String(digits.prefix(n)) + "." + String(digits.dropFirst(n)) }
        else if -6 < n && n <= 0 { body = "0." + String(repeating: "0", count: -n) + digits }
        else { let ex = n - 1; body = (k == 1 ? digits : String(digits.prefix(1)) + "." + String(digits.dropFirst())) + "e" + (ex < 0 ? "-" : "+") + String(abs(ex)) }
        return v < 0 ? "-" + body : body
    }
}
