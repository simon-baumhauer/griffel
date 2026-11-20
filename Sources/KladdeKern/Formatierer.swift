import Foundation

// Die Werkzeuge, die in Notepad++ als Plugins kommen: JSON Viewer, XML Tools,
// MIME Tools und Converter. Neu geschrieben, ohne Code der Plugins; sie
// arbeiten auf Text und kennen keine Oberfläche.

/// Ein Fehler mit Stelle im Text (Zeile und Spalte ab 1).
public struct Formatfehler: Error, Equatable {
    public let meldung: String
    public let zeile: Int
    public let spalte: Int

    public var text: String { "\(meldung) (Zeile \(zeile), Spalte \(spalte))" }
}

// MARK: - JSON

/// Ein JSON-Wert. Schlüssel bleiben in ihrer Reihenfolge, Zahlen und Texte so,
/// wie sie im Text stehen (Texte ohne Anführungszeichen, Escapes unverändert).
public indirect enum JSONWert: Equatable {
    case objekt([(String, JSONWert)])
    case liste([JSONWert])
    case text(String)
    case zahl(String)
    case wahr
    case falsch
    case null

    public static func == (a: JSONWert, b: JSONWert) -> Bool {
        switch (a, b) {
        case let (.objekt(x), .objekt(y)): return x.count == y.count && zip(x, y).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        case let (.liste(x), .liste(y)): return x == y
        case let (.text(x), .text(y)), let (.zahl(x), .zahl(y)): return x == y
        case (.wahr, .wahr), (.falsch, .falsch), (.null, .null): return true
        default: return false
        }
    }

    /// Wie der Wert in einer Zeile aussieht (für die Baumansicht).
    public var kurz: String {
        switch self {
        case .objekt(let e): return "{\(e.count)}"
        case .liste(let e): return "[\(e.count)]"
        case .text(let t): return "\"\(t)\""
        case .zahl(let z): return z
        case .wahr: return "true"
        case .falsch: return "false"
        case .null: return "null"
        }
    }
}

public enum JSONWerkzeug {
    /// Liest JSON streng nach RFC 8259; ein Fehler nennt die Stelle.
    public static func lies(_ text: String) throws -> JSONWert {
        var leser = JSONLeser(Array(text.utf8))
        leser.leer()
        let wert = try leser.wert()
        leser.leer()
        guard leser.amEnde else { throw leser.fehler("Unerwartetes Zeichen nach dem Ende des JSON") }
        return wert
    }

    /// Eingerückt, ein Wert je Zeile, wie «Format JSON» im JSON Viewer.
    public static func formatiere(_ text: String, einzug: String = "    ") throws -> String {
        var aus = ""
        schreibe(try lies(text), einzug: einzug, tiefe: 0, in: &aus)
        return aus
    }

    /// Alles in einer Zeile ohne Leerraum, wie «Compress JSON».
    public static func komprimiere(_ text: String) throws -> String {
        var aus = ""
        schreibe(try lies(text), einzug: nil, tiefe: 0, in: &aus)
        return aus
    }

    private static func schreibe(_ w: JSONWert, einzug: String?, tiefe: Int, in aus: inout String) {
        let umbruch = einzug == nil ? "" : "\n"
        func rand(_ t: Int) -> String { einzug.map { String(repeating: $0, count: t) } ?? "" }
        switch w {
        case .objekt(let e):
            guard !e.isEmpty else { aus += "{}"; return }
            aus += "{" + umbruch
            for (i, (k, v)) in e.enumerated() {
                aus += rand(tiefe + 1) + "\"\(k)\"" + (einzug == nil ? ":" : ": ")
                schreibe(v, einzug: einzug, tiefe: tiefe + 1, in: &aus)
                aus += (i < e.count - 1 ? "," : "") + umbruch
            }
            aus += rand(tiefe) + "}"
        case .liste(let e):
            guard !e.isEmpty else { aus += "[]"; return }
            aus += "[" + umbruch
            for (i, v) in e.enumerated() {
                aus += rand(tiefe + 1)
                schreibe(v, einzug: einzug, tiefe: tiefe + 1, in: &aus)
                aus += (i < e.count - 1 ? "," : "") + umbruch
            }
            aus += rand(tiefe) + "]"
        case .text(let t): aus += "\"\(t)\""
        default: aus += w.kurz
        }
    }
}

private struct JSONLeser {
    let b: [UInt8]
    var i = 0
    var zeile = 1
    var zeilenAnfang = 0

    init(_ b: [UInt8]) {
        self.b = b
        // Ein BOM am Anfang zählt nicht.
        if b.starts(with: [0xEF, 0xBB, 0xBF]) { i = 3; zeilenAnfang = 3 }
    }

    var amEnde: Bool { i >= b.count }

    func fehler(_ m: String) -> Formatfehler {
        // Spalte in Zeichen, nicht in Bytes.
        let spalte = String(decoding: b[zeilenAnfang..<min(i, b.count)], as: UTF8.self).count + 1
        return Formatfehler(meldung: m, zeile: zeile, spalte: spalte)
    }

    mutating func leer() {
        while i < b.count {
            switch b[i] {
            case 0x20, 0x09, 0x0D: i += 1
            case 0x0A: i += 1; zeile += 1; zeilenAnfang = i
            default: return
            }
        }
    }

    mutating func wert() throws -> JSONWert {
        guard i < b.count else { throw fehler("Unerwartetes Ende, ein Wert fehlt") }
        switch b[i] {
        case UInt8(ascii: "{"): return try objekt()
        case UInt8(ascii: "["): return try liste()
        case UInt8(ascii: "\""): return .text(try text())
        case UInt8(ascii: "t"): try wort("true"); return .wahr
        case UInt8(ascii: "f"): try wort("false"); return .falsch
        case UInt8(ascii: "n"): try wort("null"); return .null
        case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return .zahl(try zahl())
        default: throw fehler("Unerwartetes Zeichen «\(String(decoding: [b[i]], as: UTF8.self))»")
        }
    }

    mutating func wort(_ w: String) throws {
        let soll = Array(w.utf8)
        guard b.count - i >= soll.count, Array(b[i..<i + soll.count]) == soll else { throw fehler("Erwartet «\(w)»") }
        i += soll.count
    }

    mutating func objekt() throws -> JSONWert {
        i += 1
        var eintraege: [(String, JSONWert)] = []
        leer()
        if i < b.count, b[i] == UInt8(ascii: "}") { i += 1; return .objekt([]) }
        while true {
            leer()
            guard i < b.count, b[i] == UInt8(ascii: "\"") else { throw fehler("Ein Schlüssel in Anführungszeichen fehlt") }
            let k = try text()
            leer()
            guard i < b.count, b[i] == UInt8(ascii: ":") else { throw fehler("«:» nach dem Schlüssel fehlt") }
            i += 1
            leer()
            eintraege.append((k, try wert()))
            leer()
            guard i < b.count else { throw fehler("Unerwartetes Ende, «}» fehlt") }
            if b[i] == UInt8(ascii: ",") { i += 1; continue }
            if b[i] == UInt8(ascii: "}") { i += 1; return .objekt(eintraege) }
            throw fehler("«,» oder «}» erwartet")
        }
    }

    mutating func liste() throws -> JSONWert {
        i += 1
        var werte: [JSONWert] = []
        leer()
        if i < b.count, b[i] == UInt8(ascii: "]") { i += 1; return .liste([]) }
        while true {
            leer()
            werte.append(try wert())
            leer()
            guard i < b.count else { throw fehler("Unerwartetes Ende, «]» fehlt") }
            if b[i] == UInt8(ascii: ",") { i += 1; continue }
            if b[i] == UInt8(ascii: "]") { i += 1; return .liste(werte) }
            throw fehler("«,» oder «]» erwartet")
        }
    }

    /// Ein Text ohne die Anführungszeichen, Escapes bleiben wie sie sind.
    mutating func text() throws -> String {
        i += 1
        let anfang = i
        while i < b.count {
            switch b[i] {
            case UInt8(ascii: "\""):
                let t = String(decoding: b[anfang..<i], as: UTF8.self)
                i += 1
                return t
            case UInt8(ascii: "\\"):
                guard i + 1 < b.count else { break }
                let n = b[i + 1]
                if n == UInt8(ascii: "u") {
                    let hex = b[min(i + 2, b.count)..<min(i + 6, b.count)]
                    guard hex.count == 4, hex.allSatisfy({ ($0 >= 48 && $0 <= 57) || ($0 | 0x20 >= 97 && $0 | 0x20 <= 102) })
                    else { throw fehler("Ungültiges \\u-Escape") }
                    i += 6
                } else if Array("\"\\/bfnrt".utf8).contains(n) {
                    i += 2
                } else {
                    throw fehler("Ungültiges Escape «\\\(String(decoding: [n], as: UTF8.self))»")
                }
            case 0x00..<0x20:
                throw fehler(b[i] == 0x0A ? "Zeilenumbruch im Text, «\"» fehlt" : "Steuerzeichen im Text")
            default: i += 1
            }
        }
        throw fehler("Unerwartetes Ende, «\"» fehlt")
    }

    mutating func zahl() throws -> String {
        let anfang = i
        func ziffern() -> Int { let a = i; while i < b.count, b[i] >= 48, b[i] <= 57 { i += 1 }; return i - a }
        if b[i] == UInt8(ascii: "-") { i += 1 }
        guard i < b.count else { throw fehler("Ziffer erwartet") }
        if b[i] == UInt8(ascii: "0") { i += 1 } else if ziffern() == 0 { throw fehler("Ziffer erwartet") }
        if i < b.count, b[i] == UInt8(ascii: ".") {
            i += 1
            if ziffern() == 0 { throw fehler("Ziffer nach dem Punkt erwartet") }
        }
        if i < b.count, b[i] | 0x20 == UInt8(ascii: "e") {
            i += 1
            if i < b.count, b[i] == UInt8(ascii: "+") || b[i] == UInt8(ascii: "-") { i += 1 }
            if ziffern() == 0 { throw fehler("Ziffer im Exponenten erwartet") }
        }
        return String(decoding: b[anfang..<i], as: UTF8.self)
    }
}

// MARK: - XML

public enum XMLWerkzeug {
    /// Prüft, ob der Text wohlgeformtes XML ist (wie «Check XML syntax now»).
    public static func pruefe(_ text: String) -> Formatfehler? {
        let pruefer = XMLPruefer()
        let parser = XMLParser(data: Data(text.utf8))
        parser.delegate = pruefer
        if parser.parse() { return nil }
        let meldung = parser.parserError.map { ($0 as NSError).localizedDescription } ?? "Kein wohlgeformtes XML"
        return Formatfehler(meldung: meldung, zeile: max(1, parser.lineNumber), spalte: max(1, parser.columnNumber))
    }

    private final class XMLPruefer: NSObject, XMLParserDelegate {}

    /// Eingerückt, ein Element je Zeile («Pretty print»). Text zwischen
    /// Start- und End-Tag bleibt in derselben Zeile; Kommentare, CDATA und
    /// Anweisungen bleiben unverändert.
    public static func formatiere(_ text: String, einzug: String = "    ") -> String {
        let teile = zerlege(text)
        var zeilen: [String] = []
        var tiefe = 0
        var i = 0
        while i < teile.count {
            let t = teile[i]
            switch t.art {
            case .start:
                // <a>Text</a> bleibt eine Zeile.
                if i + 2 < teile.count, teile[i + 1].art == .text, teile[i + 2].art == .ende {
                    zeilen.append(String(repeating: einzug, count: tiefe) + t.roh + teile[i + 1].roh + teile[i + 2].roh)
                    i += 3
                    continue
                }
                if i + 1 < teile.count, teile[i + 1].art == .ende {
                    zeilen.append(String(repeating: einzug, count: tiefe) + t.roh + teile[i + 1].roh)
                    i += 2
                    continue
                }
                zeilen.append(String(repeating: einzug, count: tiefe) + t.roh)
                tiefe += 1
            case .ende:
                tiefe = max(0, tiefe - 1)
                zeilen.append(String(repeating: einzug, count: tiefe) + t.roh)
            default:
                zeilen.append(String(repeating: einzug, count: tiefe) + t.roh)
            }
            i += 1
        }
        return zeilen.joined(separator: "\n")
    }

    /// Alles in eine Zeile, ohne Leerraum zwischen den Tags («Linarize XML»).
    public static func linearisiere(_ text: String) -> String {
        zerlege(text).map(\.roh).joined()
    }

    enum Art { case start, ende, leer, text, sonst }
    struct Teil { let art: Art; let roh: String }

    /// Tags, Text, Kommentare, CDATA, Anweisungen; Text ohne Leerraum am Rand, leerer Text fällt weg.
    static func zerlege(_ text: String) -> [Teil] {
        let z = Array(text.unicodeScalars)
        var teile: [Teil] = []
        var i = 0
        func ab(_ s: String) -> Bool {
            let u = Array(s.unicodeScalars)
            return z.count - i >= u.count && Array(z[i..<i + u.count]) == u
        }
        func bis(_ s: String) -> Int {
            let u = Array(s.unicodeScalars)
            var j = i
            while j + u.count <= z.count { if Array(z[j..<j + u.count]) == u { return j + u.count }; j += 1 }
            return z.count
        }
        func roh(_ a: Int, _ e: Int) -> String { String(String.UnicodeScalarView(z[a..<e])) }
        while i < z.count {
            if z[i] == "<" {
                let e: Int
                var art = Art.sonst
                if ab("<!--") { e = bis("-->") }
                else if ab("<![CDATA[") { e = bis("]]>") }
                else if ab("<?") { e = bis("?>") }
                else if ab("<!") {
                    // DOCTYPE mit innerer Teilmenge [ … ].
                    var j = i, klammer = 0
                    while j < z.count { if z[j] == "[" { klammer += 1 } else if z[j] == "]" { klammer -= 1 } else if z[j] == ">", klammer <= 0 { break }; j += 1 }
                    e = min(j + 1, z.count)
                } else {
                    // Ein Tag; «>» in Attributwerten zählt nicht.
                    var j = i + 1
                    var quote: Unicode.Scalar?
                    while j < z.count {
                        if let q = quote { if z[j] == q { quote = nil } } else if z[j] == "\"" || z[j] == "'" { quote = z[j] } else if z[j] == ">" { break }
                        j += 1
                    }
                    e = min(j + 1, z.count)
                    art = z[i + 1] == "/" ? .ende : (e >= 2 && z[e - 2] == "/" ? .leer : .start)
                }
                teile.append(Teil(art: art, roh: roh(i, e)))
                i = e
            } else {
                var j = i
                while j < z.count, z[j] != "<" { j += 1 }
                let t = roh(i, j).trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { teile.append(Teil(art: .text, roh: t)) }
                i = j
            }
        }
        return teile
    }
}

// MARK: - MIME Tools und Converter

public enum Kodierwerkzeug {
    public static func base64(_ t: String) -> String { Data(t.utf8).base64EncodedString() }

    /// nil, wenn der Text kein gültiges Base64 ist oder kein UTF-8 ergibt.
    public static func ausBase64(_ t: String) -> String? {
        var s = t.filter { !$0.isWhitespace }
        s = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        guard let d = Data(base64Encoded: s) else { return nil }
        return String(data: d, encoding: .utf8)
    }

    /// Prozent-kodiert alles ausser A–Z, a–z, 0–9 und «-._~».
    public static func url(_ t: String) -> String {
        var erlaubt = CharacterSet.alphanumerics.intersection(CharacterSet(charactersIn: Unicode.Scalar(0)..<Unicode.Scalar(128)))
        erlaubt.insert(charactersIn: "-._~")
        return t.addingPercentEncoding(withAllowedCharacters: erlaubt) ?? t
    }

    public static func ausURL(_ t: String) -> String? {
        t.replacingOccurrences(of: "+", with: " ").removingPercentEncoding
    }

    /// «Hallo» → «48616C6C6F» (UTF-8), wie «ASCII -> HEX» im Converter.
    public static func hex(_ t: String) -> String { t.utf8.map { String(format: "%02X", $0) }.joined() }

    /// Umgekehrt; Leerraum zwischen den Paaren ist erlaubt.
    public static func ausHex(_ t: String) -> String? {
        let z = Array(t.filter { !$0.isWhitespace })
        guard z.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        for j in stride(from: 0, to: z.count, by: 2) {
            guard let b = UInt8(String(z[j...j + 1]), radix: 16) else { return nil }
            bytes.append(b)
        }
        return String(bytes: bytes, encoding: .utf8)
    }
}
