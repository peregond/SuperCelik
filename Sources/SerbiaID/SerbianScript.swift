import Foundation

/// Serbian Latin -> Cyrillic, so the app can show Serbian in either script from one set of strings.
/// Same rules as scripts/translit_sr.py and windows/SerbiaID.Windows/SerbianScript.cs:
/// letters map one to one (lj, nj, dž are single letters); Serbian acronyms become Cyrillic (PIN, PUK, JMBG, MUP, RS);
/// international acronyms (NFC, USB, PDF, ID, CA), brand/product names, words with digits, a lone capital after a hyphen (USB-C),
/// placeholders (%s %d %@) and file extensions (.cer .p7s) stay unchanged.
enum SerbianScript {
    private static let lower: [Character: Character] = [
        "a": "а", "b": "б", "c": "ц", "č": "ч", "ć": "ћ", "d": "д", "đ": "ђ", "e": "е", "f": "ф", "g": "г", "h": "х",
        "i": "и", "j": "ј", "k": "к", "l": "л", "m": "м", "n": "н", "o": "о", "p": "п", "r": "р", "s": "с", "š": "ш",
        "t": "т", "u": "у", "v": "в", "z": "з", "ž": "ж",
    ]
    private static let digraphs: [String: Character] = ["lj": "љ", "nj": "њ", "dž": "џ"]
    private static let acronyms = ["PIN": "ПИН", "PUK": "ПУК", "JMBG": "ЈМБГ", "MUP": "МУП", "RS": "РС"]
    private static let international: Set<String> = ["NFC", "USB", "PDF", "CMS", "OTG", "CCID", "ID", "CA", "OK", "APDU", "SHA", "RSA", "SIM", "UI", "API"]
    private static let protected: Set<String> = [
        "Super", "Celik", "SuperCelik", "Material", "You", "Liquid", "Glass", "iPhone", "iPad", "Mac", "macOS", "iOS",
        "Windows", "Android", "Xcode", "Apollo", "NetSeT", "Veridos", "CardEdge", "Chrome", "Safari", "Firefox",
        "MFi", "Quick", "Look", "GitHub", "Wi", "Fi",
    ]

    private static func isWordChar(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }

    private static func convert(_ word: String) -> String {
        let chars = Array(word)
        var out = ""
        var i = 0
        while i < chars.count {
            if i + 1 < chars.count {
                let pair = String(chars[i...i + 1]).lowercased()
                if let c = digraphs[pair] {
                    out.append(chars[i].isUppercase ? Character(String(c).uppercased()) : c)
                    i += 2
                    continue
                }
            }
            let ch = chars[i]
            if let c = lower[ch] { out.append(c) }
            else if let c = lower[Character(ch.lowercased())], ch.isUppercase { out.append(Character(String(c).uppercased())) }
            else { out.append(ch) }
            i += 1
        }
        return out
    }

    private static func word(_ w: String, prev: Character?) -> String {
        if let p = prev, "%$&\\.".contains(p) { return w }
        if let a = acronyms[w] { return a }
        if w.contains(where: { $0.isNumber }) || protected.contains(w) { return w }
        if international.contains(w) { return w }
        if w.count == 1, w.allSatisfy({ $0.isASCII && $0.isUppercase }), prev == "-" { return w }     // the C in USB-C
        return convert(w)
    }

    static func cyrillic(_ text: String) -> String {
        let chars = Array(text)
        var out = ""
        var i = 0
        while i < chars.count {
            // URLs stay as they are
            if chars[i] == "h", String(chars[i...].prefix(7)) == "http://" || String(chars[i...].prefix(8)) == "https://" {
                while i < chars.count, !chars[i].isWhitespace { out.append(chars[i]); i += 1 }
                continue
            }
            if isWordChar(chars[i]) {
                var j = i
                while j < chars.count, isWordChar(chars[j]) { j += 1 }
                out += word(String(chars[i..<j]), prev: i > 0 ? chars[i - 1] : nil)
                i = j
            } else {
                out.append(chars[i]); i += 1
            }
        }
        return out
    }
}
