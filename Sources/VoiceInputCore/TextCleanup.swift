import Foundation

public enum TextCleanup {
    private static let tag = try! NSRegularExpression(pattern: #"<\|[^|]{0,64}\|>"#)
    private static let extraSpace = try! NSRegularExpression(pattern: #"\s+"#)
    private static let leadingFiller = try! NSRegularExpression(
        pattern: #"^((?:嗯+|啊+|呃+|额+|唔+)[，,。、]?\s*)+"#
    )
    private static let englishFiller = try! NSRegularExpression(
        pattern: #"(?i)\b(?:um+|uh+|er+|erm+)\b[，,。、]?\s*"#
    )
    private static let trailingFiller = try! NSRegularExpression(
        pattern: #"(嗯+|啊+|呃+|额+|唔+)(?=[，,。、？?！!]*$)"#
    )
    private static let ahBeforePunct = try! NSRegularExpression(pattern: #"啊(?=[，,。、？?！!]|$)"#)
    private static let trailingMa = try! NSRegularExpression(pattern: #"嘛(?=[。.?？!！]*$)"#)
    private static let stutter = try! NSRegularExpression(pattern: #"(这个|那个|就是)(\1)+"#)
    private static let doubledPunct = try! NSRegularExpression(pattern: #"[，,]{2,}"#)
    private static let doubledStop = try! NSRegularExpression(pattern: #"[。.]{2,}"#)
    private static let commaThenStop = try! NSRegularExpression(pattern: #"[，,][。.]"#)
    private static let leadingPunct = try! NSRegularExpression(pattern: #"^[，,。、；;：:]+"#)

    public static func transcript(_ raw: String) -> String {
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        var text = tag.stringByReplacingMatches(in: raw, range: range, withTemplate: "")
        text = text.replacingOccurrences(of: "\n", with: " ")
        text = sub(extraSpace, in: text, with: " ")
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return polish(text)
    }

    /// High-precision filler cleanup. Deletes or tightens only; never invents words.
    public static func polish(_ text: String) -> String {
        var s = text
        if s.isEmpty { return s }
        s = sub(stutter, in: s, with: "$1")
        s = s.replacingOccurrences(of: "啊，就是说", with: "，就是说")
        s = s.replacingOccurrences(of: "啊就是说", with: "就是说")
        s = stripJiushishuo(s)
        s = sub(leadingFiller, in: s, with: "")
        s = sub(englishFiller, in: s, with: "")
        s = sub(trailingFiller, in: s, with: "")
        s = sub(ahBeforePunct, in: s, with: "")
        s = sub(trailingMa, in: s, with: "")
        s = s.replacingOccurrences(of: "一些这种", with: "一些")
        s = stripTrailingDehua(s)
        s = collapsePunct(s)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
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

    /// Drop discourse 就是说. If the left fragment is a false start of the right, drop it too.
    /// `也就是说` is real content and is left alone. Bare `那` right after 就是说 is also dropped.
    private static func stripJiushishuo(_ text: String) -> String {
        let token = "\u{E000}"
        var s = text.replacingOccurrences(of: "也就是说", with: token)
        let mark = "就是说"
        while let range = s.range(of: mark) {
            let left = String(s[..<range.lowerBound])
            var right = String(s[range.upperBound...])
            let frag = trailingClause(left)
            let keepLeft = isFalseStart(frag, right: right) ? String(left.dropLast(frag.count)) : left
            if right.hasPrefix("那"), !isNaContent(right.dropFirst()) {
                right = String(right.dropFirst())
            }
            s = keepLeft + right
        }
        return s.replacingOccurrences(of: token, with: "也就是说")
    }

    private static func trailingClause(_ text: String) -> String {
        var chars: [Character] = []
        for ch in text.reversed() {
            if "，,。、？?！!；;：: \t".contains(ch) { break }
            chars.append(ch)
            if chars.count >= 4 { break }
        }
        return String(chars.reversed())
    }

    private static func isFalseStart(_ left: String, right: String) -> Bool {
        guard (1...4).contains(left.count) else { return false }
        if right.hasPrefix(left) { return true }
        if let last = left.last, right.hasPrefix(String(last)) { return true }
        return false
    }

    private static func isNaContent<S: StringProtocol>(_ rest: S) -> Bool {
        guard let first = rest.first else { return false }
        return "个些边里时天种么儿".contains(first)
    }

    private static func stripTrailingDehua(_ text: String) -> String {
        let condition = ["如果", "要是", "假如", "的话就"]
        if condition.contains(where: { text.contains($0) }) { return text }
        guard text.hasSuffix("的话") || text.contains("的话。") || text.contains("的话.") ||
                text.contains("的话？") || text.contains("的话!") || text.contains("的话！") else {
            return text
        }
        if let range = text.range(of: "的话", options: .backwards),
           text[range.upperBound...].allSatisfy({ "。.?？!！".contains($0) }) {
            return String(text[..<range.lowerBound]) + String(text[range.upperBound...])
        }
        return text
    }

    private static func collapsePunct(_ text: String) -> String {
        var s = sub(doubledPunct, in: text, with: "，")
        s = sub(commaThenStop, in: s, with: "。")
        s = sub(doubledStop, in: s, with: "。")
        s = sub(leadingPunct, in: s, with: "")
        return s
    }

    private static func sub(_ re: NSRegularExpression, in text: String, with template: String) -> String {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return re.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}
