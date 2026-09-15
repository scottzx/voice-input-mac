import Foundation

public enum TextCleanup {
    private static let tag = try! NSRegularExpression(pattern: #"<\|[^|]{0,64}\|>"#)

    public static func transcript(_ raw: String) -> String {
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        var text = tag.stringByReplacingMatches(in: raw, range: range, withTemplate: "")
        text = text.replacingOccurrences(of: "\n", with: " ")
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func isUseful(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        let stripped = trimmed.unicodeScalars.filter { !CharacterSet.punctuationCharacters.contains($0) && !CharacterSet.whitespacesAndNewlines.contains($0) }
        return !stripped.isEmpty
    }

    /// Prefix to paste in front of `incoming` so consecutive utterances read naturally.
    public static func glue(previous: String, incoming: String) -> String {
        guard let last = previous.unicodeScalars.last, let first = incoming.unicodeScalars.first else {
            return ""
        }
        if CharacterSet.whitespacesAndNewlines.contains(last) || CharacterSet.whitespacesAndNewlines.contains(first) {
            return ""
        }
        if isCJK(last) && isCJK(first) { return "" }
        if isCJKPunct(last) && isCJK(first) { return "" }
        if CharacterSet.punctuationCharacters.contains(last) && isCJK(first) { return "" }
        if isCJK(last) && !isCJK(first) && !CharacterSet.punctuationCharacters.contains(first) {
            return ""
        }
        if !isCJK(last) && isCJK(first) { return "" }
        return " "
    }

    public static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF,
             0x20000...0x2A6DF, 0x2A700...0x2B73F, 0x2B740...0x2B81F,
             0x3000...0x303F, 0x3040...0x309F, 0x30A0...0x30FF, 0x31F0...0x31FF,
             0xFF66...0xFF9D, 0xAC00...0xD7AF:
            return true
        default:
            return false
        }
    }

    private static func isCJKPunct(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x3001, 0x3002, 0xFF0C, 0xFF01, 0xFF1F, 0xFF1B, 0xFF1A,
             0x2014, 0x2026, 0x300A, 0x300B, 0x3010, 0x3011, 0xFF08, 0xFF09,
             0x201C, 0x201D, 0x2018, 0x2019:
            return true
        default:
            return false
        }
    }
}
