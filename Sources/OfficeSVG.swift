import Cocoa
import CoreText

/// Outlines canonical chart labels only in public clipboard SVG. Reports,
/// private fragments and saved SVG retain their original editable text.
@MainActor enum OfficeSVG {
    private static let maximumBytes = 20_000_000
    private static let maximumLabelLength = 4096
    private struct Budget {
        var glyphs = 100_000
        var points = 500_000
        var attempts = 10_000
        var exhausted: Bool { glyphs <= 0 || points <= 0 || attempts <= 0 }
    }
    private static let namespace = "http://www.w3.org/2000/svg"
    private static let length = try! NSRegularExpression(pattern: "^([+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][+-]?[0-9]+)?)(?:px)?$")

    static func forClipboard(_ data: Data) -> Data {
        guard data.count <= maximumBytes, let source = String(data: data, encoding: .utf8),
              source.contains("<text") || source.contains(":text"),
              source.range(of: "<!DOCTYPE", options: .caseInsensitive) == nil else { return data }
        do {
            let document = try XMLDocument(data: data, options: [.nodeLoadExternalEntitiesNever, .nodePreserveWhitespace])
            guard let root = document.rootElement(), root.localName == "svg", root.uri == namespace else { return data }
            let elements = [root] + (try root.nodes(forXPath: ".//*")).compactMap { $0 as? XMLElement }
            guard !elements.contains(where: { $0.localName == "style" }) else { return data }
            var changed = false, bytes = data.count
            var budget = Budget()
            for text in elements where text.localName == "text" && text.uri == namespace {
                guard !budget.exhausted else { break }
                budget.attempts -= 1
                guard let path = outline(text, budget: &budget) else { continue }
                bytes += path.xmlString.utf8.count - text.xmlString.utf8.count
                guard bytes <= maximumBytes else { return data }
                guard let parent = text.parent as? XMLElement, let index = parent.children?.firstIndex(where: { $0 === text }) else { continue }
                parent.replaceChild(at: index, with: path)
                changed = true
            }
            guard changed else { return data }
            let result = document.xmlData(options: .nodeCompactEmptyElement)
            return result.count <= maximumBytes ? result : data
        } catch { return data }
    }

    private static func inherited(_ element: XMLElement, _ name: String) -> String? {
        var current: XMLElement? = element
        while let node = current {
            if let value = node.attribute(forName: name)?.stringValue, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return value }
            current = node.parent as? XMLElement
        }
        return nil
    }
    private static func isDefault(_ element: XMLElement, _ name: String, _ values: String...) -> Bool {
        guard let value = inherited(element, name) else { return true }
        return values.contains(value)
    }
    private static func number(_ value: String?) -> CGFloat? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              let match = length.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range(at: 1), in: value), let number = Double(value[range]), number.isFinite else { return nil }
        return CGFloat(number)
    }

    private static func outline(_ text: XMLElement, budget: inout Budget) -> XMLElement? {
        let labelValue = text.stringValue ?? ""
        guard !(text.children ?? []).contains(where: { $0 is XMLElement }), labelValue.utf16.count <= maximumLabelLength,
              !["style", "dx", "dy", "rotate", "textLength", "lengthAdjust"].contains(where: { text.attribute(forName: $0) != nil }),
              isDefault(text, "text-anchor", "start"), isDefault(text, "writing-mode", "horizontal-tb"),
              isDefault(text, "dominant-baseline", "auto", "alphabetic"), isDefault(text, "alignment-baseline", "auto", "baseline"),
              isDefault(text, "baseline-shift", "baseline", "0"), isDefault(text, "letter-spacing", "normal", "0"),
              isDefault(text, "word-spacing", "normal", "0"), isDefault(text, "direction", "ltr"),
              isDefault(text, "unicode-bidi", "normal"), isDefault(text, "font-variant", "normal"),
              isDefault(text, "font-stretch", "normal"), isDefault(text, "text-decoration", "none"),
              isDefault(text, "font-kerning", "auto"), isDefault(text, "kerning", "auto"),
              isDefault(text, "font-feature-settings", "normal"), isDefault(text, "font-variant-ligatures", "normal"),
              isDefault(text, "white-space", "normal"),
              let x = number(text.attribute(forName: "x")?.stringValue ?? "0"),
              let y = number(text.attribute(forName: "y")?.stringValue ?? "0"),
              let size = number(inherited(text, "font-size")), size > 0, size <= 1024,
              let families = inherited(text, "font-family") else { return nil }
        // Ancestor inline CSS can override inherited presentation attributes.
        // The canonical exporter resolves it; other text stays untouched.
        var ancestor = text.parent as? XMLElement
        while let node = ancestor {
            if let style = node.attribute(forName: "style")?.stringValue {
                // The host applies only viewport sizing to the root SVG.
                // These non-inherited properties do not alter glyph layout.
                guard node.parent is XMLDocument, node.localName == "svg", viewportStyle(style) else { return nil }
            }
            ancestor = node.parent as? XMLElement
        }
        var bold = false, italic = false
        if let weight = inherited(text, "font-weight") {
            switch weight {
            case "normal", "400": break
            case "bold", "700": bold = true
            default: return nil // Do not approximate light/medium/other faces.
            }
        }
        if let slant = inherited(text, "font-style"), slant != "normal" {
            guard slant == "italic" else { return nil }
            italic = true
        }
        guard let font = font(families, size: size, bold: bold, italic: italic) else { return nil }
        let label: String
        if inherited(text, "xml:space") == "preserve" {
            guard !labelValue.contains(where: { $0 == "\r" || $0 == "\n" || $0 == "\t" }) else { return nil }
            label = labelValue
        } else {
            label = labelValue.replacingOccurrences(of: "[\\t\\r\\n ]+", with: " ", options: .regularExpression).trimmingCharacters(in: CharacterSet(charactersIn: " "))
        }
        guard !label.isEmpty else { return nil }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: label, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
        let path = CGMutablePath()
        var pointCount = 0
        for run in CTLineGetGlyphRuns(line) as! [CTRun] {
            let count = CTRunGetGlyphCount(run)
            guard count <= budget.glyphs else { budget.glyphs = 0; return nil }
            // Charge attempted work even if an unsupported run or later
            // non-outline glyph makes this whole label fall back to text.
            budget.glyphs -= count
            guard !CTRunGetStatus(run).contains(.rightToLeft) else { return nil }
            let attributes = CTRunGetAttributes(run) as NSDictionary
            guard let runFont = attributes[kCTFontAttributeName] else { return nil }
            let actualFont = runFont as! CTFont
            var glyphs = [CGGlyph](repeating: 0, count: count), positions = [CGPoint](repeating: .zero, count: count)
            var indices = [CFIndex](repeating: 0, count: count)
            CTRunGetGlyphs(run, CFRange(), &glyphs); CTRunGetPositions(run, CFRange(), &positions); CTRunGetStringIndices(run, CFRange(), &indices)
            let characters = Array(label.utf16)
            for index in 0..<count {
                guard glyphs[index] != 0 else { return nil }
                guard let glyph = CTFontCreatePathForGlyph(actualFont, glyphs[index], nil) else {
                    // Spaces advance the line but have no outline. Color emoji
                    // or other non-outline glyphs keep the whole text label.
                    guard indices[index] >= 0, indices[index] < characters.count, characters[indices[index]] == 32 else { return nil }
                    continue
                }
                var glyphPoints = 0
                glyph.applyWithBlock { element in
                    switch element.pointee.type {
                    case .moveToPoint, .addLineToPoint: glyphPoints += 1
                    case .addQuadCurveToPoint: glyphPoints += 2
                    case .addCurveToPoint: glyphPoints += 3
                    default: break
                    }
                }
                // Charge and bound native storage before appending contours.
                // Failed labels do not refund their attempted path work.
                guard glyphPoints <= budget.points else { budget.points = 0; return nil }
                budget.points -= glyphPoints
                pointCount += glyphPoints
                guard pointCount <= 100_000 else { return nil }
                let position = positions[index]
                guard position.x.isFinite, position.y.isFinite else { return nil }
                path.addPath(glyph, transform: CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: x + position.x, ty: y - position.y))
            }
        }
        guard !path.isEmpty, let data = pathData(path) else { return nil }
        let result = XMLElement(name: "path", uri: namespace)
        let layout = Set(["x", "y", "font-family", "font-size", "font-weight", "font-style", "text-anchor", "dominant-baseline", "alignment-baseline", "baseline-shift", "letter-spacing", "word-spacing", "writing-mode", "xml:space"])
        for attribute in text.attributes ?? [] where !layout.contains(attribute.name ?? "") {
            if let copied = attribute.copy() as? XMLNode { result.addAttribute(copied) }
        }
        result.addAttribute(XMLNode.attribute(withName: "d", stringValue: data) as! XMLNode)
        if let rule = result.attribute(forName: "fill-rule") { rule.stringValue = "nonzero" }
        else { result.addAttribute(XMLNode.attribute(withName: "fill-rule", stringValue: "nonzero") as! XMLNode) }
        if result.attribute(forName: "aria-label") == nil { result.addAttribute(XMLNode.attribute(withName: "aria-label", stringValue: label) as! XMLNode) }
        let title = XMLElement(name: "title", uri: namespace); title.stringValue = label; result.addChild(title)
        return result
    }

    private static func viewportStyle(_ style: String) -> Bool {
        let allowed = Set(["width", "height", "max-width", "max-height"])
        return style.split(separator: ";").allSatisfy { declaration in
            let value = declaration.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty { return true }
            let pair = value.split(separator: ":", maxSplits: 1)
            return pair.count == 2 && allowed.contains(pair[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
                && !pair[1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private static func font(_ list: String, size: CGFloat, bold: Bool, italic: Bool) -> CTFont? {
        let manager = NSFontManager.shared, available = manager.availableFontFamilies
        var traits: NSFontTraitMask = []
        if bold { traits.insert(.boldFontMask) }; if italic { traits.insert(.italicFontMask) }
        for item in list.split(separator: ",") {
            let name = item.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            let family: String
            switch name.lowercased() {
            case "sans-serif": family = "Helvetica"
            case "serif": family = "Times"
            case "monospace": family = "Menlo"
            case "system-ui": family = NSFont.systemFont(ofSize: size).familyName ?? ""
            default: family = name
            }
            guard let known = available.first(where: { $0.caseInsensitiveCompare(family) == .orderedSame }),
                  let font = manager.font(withFamily: known, traits: traits, weight: bold ? 9 : 5, size: size),
                  font.familyName?.caseInsensitiveCompare(known) == .orderedSame,
                  manager.traits(of: font).intersection(traits) == traits else { continue }
            let result = CTFontCreateWithName(font.fontName as CFString, size, nil)
            guard (CTFontCopyFamilyName(result) as String).caseInsensitiveCompare(known) == .orderedSame else { continue }
            return result
        }
        return nil
    }

    private static func pathData(_ path: CGPath) -> String? {
        var result = "", valid = true
        path.applyWithBlock { element in
            guard valid else { return }
            let value = element.pointee
            let count: Int, command: String
            switch value.type {
            case .moveToPoint: command = "M"; count = 1
            case .addLineToPoint: command = "L"; count = 1
            case .addQuadCurveToPoint: command = "Q"; count = 2
            case .addCurveToPoint: command = "C"; count = 3
            case .closeSubpath: command = "Z"; count = 0
            @unknown default: valid = false; return
            }
            result += command
            for index in 0..<count {
                let point = value.points[index]
                guard point.x.isFinite, point.y.isFinite else { valid = false; return }
                result += "\(Double(point.x)) \(Double(point.y)) "
            }
            if result.utf8.count > maximumBytes { valid = false }
        }
        return valid ? result : nil
    }
}
