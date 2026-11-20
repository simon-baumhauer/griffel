import Foundation

/// Eine benutzerdefinierte Sprache (UDL) von Notepad++, aus ihrer XML-Datei
/// (<NotepadPlus><UserLang …>). Gelesen wie NppParameters::feedUserLang und
/// aufbereitet wie ScintillaEditView::setUserLexer. Unterstützt ist das Format
/// ab udlVersion 2.0.
public struct Benutzersprache: Equatable {
    public struct Stil: Equatable {
        public let id: Int
        public let vorne: Int?
        public let hinten: Int?
        public let schrift: Int?
        public let verschachtelung: Int
    }

    public let name: String
    public let endungen: [String]
    public let ohneGrossKlein: Bool
    public let kommentareFalten: Bool
    public let kompaktFalten: Bool
    public let reinesLC: Int
    public let dezimaltrenner: Int
    /// Ob die Schlüsselwortgruppen 1–8 als Präfix gelten.
    public let praefix: [Bool]
    /// Die 28 Listen in der Reihenfolge von SCE_USER_KWLIST_*.
    public let listen: [String]
    public let stile: [Stil]

    /// Die Listen, die als Eigenschaft an den Lexer gehen (setLexerMapper), alle anderen
    /// gehen der Reihe nach mit SCI_SETKEYWORDS.
    public static let eigenschaften: [Int: String] = [
        0: "userDefine.comments", 27: "userDefine.delimiters", 8: "userDefine.operators1",
        1: "userDefine.numberPrefix1", 2: "userDefine.numberPrefix2", 3: "userDefine.numberExtras1",
        4: "userDefine.numberExtras2", 5: "userDefine.numberSuffix1", 6: "userDefine.numberSuffix2",
        7: "userDefine.numberRange", 10: "userDefine.foldersInCode1Open", 11: "userDefine.foldersInCode1Middle",
        12: "userDefine.foldersInCode1Close",
    ]

    static let listenNamen: [String: Int] = [
        "Comments": 0, "Numbers, prefix1": 1, "Numbers, prefix2": 2, "Numbers, extras1": 3, "Numbers, extras2": 4,
        "Numbers, suffix1": 5, "Numbers, suffix2": 6, "Numbers, range": 7, "Operators1": 8, "Operators2": 9,
        "Folders in code1, open": 10, "Folders in code1, middle": 11, "Folders in code1, close": 12,
        "Folders in code2, open": 13, "Folders in code2, middle": 14, "Folders in code2, close": 15,
        "Folders in comment, open": 16, "Folders in comment, middle": 17, "Folders in comment, close": 18,
        "Keywords1": 19, "Keywords2": 20, "Keywords3": 21, "Keywords4": 22, "Keywords5": 23,
        "Keywords6": 24, "Keywords7": 25, "Keywords8": 26, "Delimiters": 27,
    ]

    static let stilNamen: [String: Int] = [
        "DEFAULT": 0, "COMMENTS": 1, "LINE COMMENTS": 2, "NUMBERS": 3,
        "KEYWORDS1": 4, "KEYWORDS2": 5, "KEYWORDS3": 6, "KEYWORDS4": 7,
        "KEYWORDS5": 8, "KEYWORDS6": 9, "KEYWORDS7": 10, "KEYWORDS8": 11,
        "OPERATORS": 12, "FOLDER IN CODE1": 13, "FOLDER IN CODE2": 14, "FOLDER IN COMMENT": 15,
        "DELIMITERS1": 16, "DELIMITERS2": 17, "DELIMITERS3": 18, "DELIMITERS4": 19,
        "DELIMITERS5": 20, "DELIMITERS6": 21, "DELIMITERS7": 22, "DELIMITERS8": 23,
    ]

    /// Alle Sprachen einer Datei (eine Datei kann mehrere enthalten).
    public static func lade(_ url: URL) throws -> [Benutzersprache] {
        try lade(xml: Data(contentsOf: url))
    }

    public static func lade(xml: Data) throws -> [Benutzersprache] {
        let dokument = try XMLDocument(data: xml)
        return try dokument.nodes(forXPath: "//UserLang").compactMap { knoten in
            guard let e = knoten as? XMLElement else { return nil }
            return try sprache(aus: e)
        }
    }

    static func sprache(aus e: XMLElement) throws -> Benutzersprache {
        func attribut(_ x: XMLElement?, _ n: String) -> String? { x?.attribute(forName: n)?.stringValue }
        guard let name = attribut(e, "name"), !name.isEmpty else { throw Suchfehler(meldung: "UDL ohne Namen") }
        let version = attribut(e, "udlVersion") ?? ""
        guard version.hasPrefix("2.") else {
            throw Suchfehler(meldung: "«\(name)»: Nur benutzerdefinierte Sprachen ab Version 2.0 werden unterstützt.")
        }
        let einstellungen = e.elements(forName: "Settings").first
        let global = einstellungen?.elements(forName: "Global").first
        let praefixKnoten = einstellungen?.elements(forName: "Prefix").first
        func ja(_ x: XMLElement?, _ n: String) -> Bool { attribut(x, n) == "yes" }

        var listen = Array(repeating: "", count: 28)
        for kw in e.elements(forName: "KeywordLists").first?.elements(forName: "Keywords") ?? [] {
            guard let n = attribut(kw, "name"), let i = listenNamen[n] else { continue }
            listen[i] = kw.stringValue ?? ""
        }
        var stile: [Stil] = []
        for s in e.elements(forName: "Styles").first?.elements(forName: "WordsStyle") ?? [] {
            guard let n = attribut(s, "name"), let id = stilNamen[n] else { continue }
            // colorStyle: 1 Vordergrund, 2 Hintergrund gilt; fehlt es, gelten beide.
            let farbstil = Int(attribut(s, "colorStyle") ?? "") ?? 3
            stile.append(Stil(
                id: id,
                vorne: farbstil & 1 != 0 ? Int(attribut(s, "fgColor") ?? "", radix: 16) : nil,
                hinten: farbstil & 2 != 0 ? Int(attribut(s, "bgColor") ?? "", radix: 16) : nil,
                schrift: Int(attribut(s, "fontStyle") ?? ""),
                verschachtelung: Int(attribut(s, "nesting") ?? "") ?? 0))
        }
        return Benutzersprache(
            name: name,
            endungen: (attribut(e, "ext") ?? "").split(separator: " ").map(String.init),
            ohneGrossKlein: ja(global, "caseIgnored"),
            kommentareFalten: ja(global, "allowFoldOfComments"),
            kompaktFalten: ja(global, "foldCompact"),
            reinesLC: Int(attribut(global, "forcePureLC") ?? "") ?? 0,
            dezimaltrenner: Int(attribut(global, "decimalSeparator") ?? "") ?? 0,
            praefix: (1...8).map { ja(praefixKnoten, "Keywords\($0)") },
            listen: listen, stile: stile)
    }

    /// Eine Liste für SCI_SETKEYWORDS, wie setUserLexer sie baut: Anführungszeichen
    /// fassen mehrere Wörter zusammen; Leerzeichen darin werden «\v» (doppelte)
    /// oder «\b» (einfache); «\"», «\'» und «\\» stehen für das Zeichen.
    public static func aufbereitet(_ liste: String) -> String {
        let b = Array(liste.utf8)
        var aus: [UInt8] = []
        var doppelt = false
        var einfach = false
        var inhalt = false
        var j = 0
        while j < b.count {
            let c = b[j]
            if !einfach, c == 0x22 { doppelt.toggle(); j += 1; continue }
            if !doppelt, c == 0x27 { einfach.toggle(); j += 1; continue }
            if c == 0x5C, j + 1 < b.count, [0x22, 0x27, 0x5C].contains(b[j + 1]) {
                aus.append(b[j + 1])
                j += 2
                continue
            }
            if doppelt || einfach {
                if c > 0x20 {
                    aus.append(c)
                    inhalt = true
                } else if inhalt, j > 0, b[j - 1] != 0x22, j + 1 < b.count, b[j + 1] != 0x22, b[j + 1] > 0x20 {
                    aus.append(doppelt ? 0x0B : 0x08)
                }
            } else {
                aus.append(c)
            }
            j += 1
        }
        return String(decoding: aus, as: UTF8.self)
    }

    /// Die Kommentarzeichen aus der Liste «Comments» («00// 01 02 03/* 04*/»):
    /// 00 öffnet einen Zeilenkommentar, 03 und 04 öffnen und schliessen einen Block.
    public var kommentarzeichen: (zeile: String?, anfang: String?, ende: String?) {
        var zeile: String?
        var anfang: String?
        var ende: String?
        for teil in listen[0].split(separator: " ") where teil.count > 2 {
            let code = teil.prefix(2)
            let wert = String(teil.dropFirst(2))
            switch code {
            case "00": zeile = zeile ?? wert
            case "03": anfang = anfang ?? wert
            case "04": ende = ende ?? wert
            default: break
            }
        }
        return (zeile, anfang, ende)
    }
}
