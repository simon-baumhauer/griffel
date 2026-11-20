import Foundation

/// Ein Eintrag der Funktionsliste: eine Klasse mit ihren Funktionen, oder eine Funktion.
public struct Funktionseintrag: Equatable {
    public let name: String
    /// Wo der Name steht, in Bytes (zum Hinspringen); bei Klassen ohne eigene Stelle die der ersten Funktion.
    public let stelle: Int
    public var kinder: [Funktionseintrag]

    public init(name: String, stelle: Int, kinder: [Funktionseintrag] = []) {
        self.name = name
        self.stelle = stelle
        self.kinder = kinder
    }
}

/// Ein Parser der Funktionsliste von Notepad++ (installer/functionList/<sprache>.xml),
/// nachgebaut nach FunctionParser in functionParser.cpp:
///
/// - `commentExpr` findet Kommentare; was darin beginnt, zählt nicht.
/// - `classRange` findet Klassen; mit `openSymbole`/`closeSymbole` reicht eine
///   Klasse bis zur passenden schliessenden Klammer. Darin sucht `function`.
/// - `function` ausserhalb von Klassen findet Funktionen; eine `className`-Kette
///   kann ihnen eine Klasse geben (etwa `Foo::bar` in C++).
/// - Namen entstehen über eine Kette von Ausdrücken: der erste sucht im Treffer,
///   jeder weitere im Ergebnis des vorherigen.
///
/// Die Ausdrücke sind für Boost geschrieben; die Unterschiede zu ICU gleicht
/// `uebersetze` aus (vor allem `\K`). Wie in Notepad++ gelten sie ohne Gross-/
/// Kleinschreibung, «.» passt auf Zeilenenden und ^/$ gelten je Zeile.
public struct Funktionsliste {
    public struct Funktionsregel {
        let haupt: NSRegularExpression
        let name: [NSRegularExpression]
        let klasse: [NSRegularExpression]
    }

    public struct Klassenregel {
        let haupt: NSRegularExpression
        let auf: NSRegularExpression?
        let klammern: NSRegularExpression?
        let name: [NSRegularExpression]
        let funktion: Funktionsregel?
    }

    public let anzeigename: String
    let kommentar: NSRegularExpression?
    let klassen: Klassenregel?
    let funktionen: Funktionsregel?

    // MARK: Laden

    public static func lade(_ url: URL) throws -> Funktionsliste {
        try lade(xml: Data(contentsOf: url))
    }

    public static func lade(xml: Data) throws -> Funktionsliste {
        let dokument = try XMLDocument(data: zeilenumbruecheBewahrt(xml))
        guard let parser = try dokument.nodes(forXPath: "//functionList/parser").first as? XMLElement else {
            throw Suchfehler(meldung: "Kein <parser> in der Funktionsliste")
        }
        func attribut(_ e: XMLElement?, _ name: String) -> String? {
            guard let wert = e?.attribute(forName: name)?.stringValue, !wert.isEmpty else { return nil }
            return wert
        }
        func kind(_ e: XMLElement?, _ name: String) -> XMLElement? { e?.elements(forName: name).first }
        func kette(_ e: XMLElement?, _ name: String) throws -> [NSRegularExpression] {
            try (e?.elements(forName: name) ?? []).compactMap { attribut($0, "expr") }.map(ausdruck)
        }
        func funktion(_ e: XMLElement?) throws -> Funktionsregel? {
            guard let e, let haupt = attribut(e, "mainExpr") else { return nil }
            let namen = kind(e, "functionName")
            return Funktionsregel(
                haupt: try ausdruck(haupt),
                name: try kette(namen, "nameExpr") + kette(namen, "funcNameExpr"),
                klasse: try kette(kind(e, "className"), "nameExpr"))
        }

        var klassen: Klassenregel?
        if let bereich = kind(parser, "classRange"), let haupt = attribut(bereich, "mainExpr") {
            let auf = attribut(bereich, "openSymbole")
            let zu = attribut(bereich, "closeSymbole")
            klassen = Klassenregel(
                haupt: try ausdruck(haupt),
                auf: try auf.map(ausdruck),
                klammern: try auf.flatMap { a in try zu.map { try ausdruck("(\(a)|\($0))") } },
                name: try kette(kind(bereich, "className"), "nameExpr"),
                funktion: try funktion(kind(bereich, "function")))
        }
        return Funktionsliste(
            anzeigename: attribut(parser, "displayName") ?? attribut(parser, "id") ?? "",
            // Ein kaputter Kommentarausdruck (fortran77.xml hat eine Klammer zu wenig) soll
            // die Liste nicht verhindern; dann zählen eben auch Treffer in Kommentaren.
            kommentar: attribut(parser, "commentExpr").flatMap { try? ausdruck($0) },
            klassen: klassen,
            funktionen: try funktion(kind(parser, "function")))
    }

    /// Nach dem XML-Standard werden Zeilenumbrüche und Tabs in Attributwerten
    /// zu Leerzeichen. Die Ausdrücke von Notepad++ brauchen sie aber: Im Modus
    /// (?x) reicht ein «# Kommentar» bis zum Zeilenende. Darum werden sie vor
    /// dem Lesen zu Zeichenreferenzen, die das überstehen.
    static func zeilenumbruecheBewahrt(_ xml: Data) -> Data {
        var aus = Data(capacity: xml.count + 1024)
        var imTag = false
        var anfuehrung: UInt8 = 0
        let bytes = [UInt8](xml)
        var i = 0
        while i < bytes.count {
            let b = bytes[i]
            i += 1
            // Kommentare <!-- … --> und Verarbeitungsanweisungen <? … ?> unverändert übernehmen.
            if !imTag, anfuehrung == 0, b == 0x3C, i + 2 < bytes.count, bytes[i] == 0x21, bytes[i + 1] == 0x2D, bytes[i + 2] == 0x2D {
                var j = i + 3
                while j + 2 < bytes.count, !(bytes[j] == 0x2D && bytes[j + 1] == 0x2D && bytes[j + 2] == 0x3E) { j += 1 }
                let ende = min(bytes.count, j + 3)
                aus.append(b)
                aus.append(contentsOf: bytes[i..<ende])
                i = ende
                continue
            }
            if anfuehrung != 0 {
                if b == anfuehrung {
                    anfuehrung = 0
                } else if b == 0x0A {
                    aus.append(contentsOf: Array("&#10;".utf8)); continue
                } else if b == 0x0D {
                    aus.append(contentsOf: Array("&#13;".utf8)); continue
                } else if b == 0x09 {
                    aus.append(contentsOf: Array("&#9;".utf8)); continue
                }
            } else if imTag, b == 0x22 || b == 0x27 {
                anfuehrung = b
            } else if b == 0x3C {
                imTag = true
            } else if b == 0x3E {
                imTag = false
            }
            aus.append(b)
        }
        return aus
    }

    static func ausdruck(_ boost: String) throws -> NSRegularExpression {
        do {
            return try NSRegularExpression(
                pattern: uebersetze(boost), options: [.caseInsensitive, .dotMatchesLineSeparators, .anchorsMatchLines])
        } catch {
            throw Suchfehler(meldung: "Ausdruck nicht unterstützt: \(boost)")
        }
    }

    /// Boost → ICU: `\K` wird eine leere Gruppe «kladdeK…», deren Anfang der
    /// neue Trefferanfang ist; `(?'name'` wird `(?<name>`; `\<` und `\>` werden `\b`.
    static func uebersetze(_ boost: String) -> String {
        var ergebnis = ""
        var nummer = 0
        var inKlasse = false
        let z = Array(boost)
        // Freier Modus (?x): «# …» bis zum Zeilenende ist Kommentar. Den lässt die
        // Übersetzung weg, damit Klammern darin nichts durcheinanderbringen.
        let frei: Bool = {
            guard boost.hasPrefix("(?"), let zu = boost.firstIndex(of: ")") else { return false }
            let schalter = boost[boost.index(boost.startIndex, offsetBy: 2)..<zu]
            return schalter.prefix { $0 != "-" }.contains("x") && !schalter.contains(":")
        }()
        var i = 0
        while i < z.count {
            let c = z[i]
            if frei, !inKlasse, c == "#" {
                while i < z.count, z[i] != "\n", z[i] != "\r" { i += 1 }
                continue
            }
            // Im freien Modus sind «#» und Leerzeichen in einer Klasse für Boost Zeichen, für ICU nicht.
            if frei, inKlasse, c == "#" || c == " " {
                ergebnis += c == "#" ? "\\#" : "\\x20"
                i += 1
                continue
            }
            // \k'name' → \k<name>
            if c == "\\", i + 2 < z.count, z[i + 1] == "k", z[i + 2] == "'", let zu = z[(i + 3)...].firstIndex(of: "'") {
                ergebnis += "\\k<" + String(z[(i + 3)..<zu]) + ">"
                i = zu + 1
                continue
            }
            if c == "\\", i + 1 < z.count {
                let n = z[i + 1]
                if !inKlasse, n == "K" {
                    ergebnis += "(?<kladdeK\(nummer)>)"
                    nummer += 1
                } else if !inKlasse, n == "<" || n == ">" {
                    ergebnis += "\\b"
                } else {
                    ergebnis.append(c)
                    ergebnis.append(n)
                }
                i += 2
                continue
            }
            if c == "[", inKlasse {
                // In Boost ist «[» in einer Klasse ein Zeichen, in ICU der Anfang einer
                // inneren Menge. POSIX-Klassen wie [:alpha:] bleiben.
                if i + 1 < z.count, z[i + 1] == ":" {
                    if let zu = z[(i + 2)...].firstIndex(of: "]"), zu > i + 2, z[zu - 1] == ":" {
                        ergebnis += String(z[i...zu])
                        i = zu + 1
                        continue
                    }
                }
                ergebnis += "\\["
                i += 1
                continue
            }
            if c == "{", !inKlasse {
                // Ein Quantor {n}, {n,} oder {n,m} bleibt; jedes andere «{» ist in Boost ein Zeichen.
                if let zu = quantorende(z, ab: i) {
                    ergebnis += String(z[i...zu])
                    i = zu + 1
                } else {
                    ergebnis += "\\{"
                    i += 1
                }
                continue
            }
            if !inKlasse, c == "}" || c == "]" {
                // Ohne Gegenstück sind sie in Boost Zeichen; ICU lehnt sie ab.
                ergebnis += "\\" + String(c)
                i += 1
                continue
            }
            if c == "[", !inKlasse {
                inKlasse = true
                ergebnis.append(c)
                // «[]» und «[^]» am Anfang sind Zeichen, kein Ende.
                if i + 1 < z.count, z[i + 1] == "^" { ergebnis.append("^"); i += 1 }
                if i + 1 < z.count, z[i + 1] == "]" { ergebnis.append("]"); i += 1 }
                i += 1
                continue
            }
            if c == "]", inKlasse { inKlasse = false }
            if !inKlasse, c == "(", i + 2 < z.count, z[i + 1] == "?", z[i + 2] == "'",
                let ende = z[(i + 3)...].firstIndex(of: "'")
            {
                ergebnis += "(?<" + String(z[(i + 3)..<ende]) + ">"
                i = ende + 1
                continue
            }
            ergebnis.append(c)
            i += 1
        }
        return ersetzeUnteraufrufe(einfacheNamen(ergebnis))
    }

    /// ICU erlaubt in Gruppennamen nur Buchstaben und Ziffern (kein «_»).
    static func einfacheNamen(_ muster: String) -> String {
        guard let ausdruck = try? NSRegularExpression(pattern: #"\(\?<([A-Za-z]\w*)>|\\k<(\w+)>|\(\?&(\w+)\)"#) else { return muster }
        let ns = muster as NSString
        var namen = Set<String>()
        for m in ausdruck.matches(in: muster, range: NSRange(location: 0, length: ns.length)) {
            for g in 1...3 where m.range(at: g).location != NSNotFound { namen.insert(ns.substring(with: m.range(at: g))) }
        }
        let schlecht = namen.filter { $0.contains("_") }
        guard !schlecht.isEmpty else { return muster }
        var ergebnis = muster
        for (i, name) in schlecht.sorted(by: { $0.count > $1.count }).enumerated() {
            let neu = "kn\(i)" + name.filter { $0.isLetter || $0.isNumber }
            for (alt, ersatz) in [("(?<\(name)>", "(?<\(neu)>"), ("\\k<\(name)>", "\\k<\(neu)>"), ("(?&\(name))", "(?&\(neu))")] {
                ergebnis = ergebnis.replacingOccurrences(of: alt, with: ersatz)
            }
        }
        return ergebnis
    }

    // MARK: Unteraufrufe

    /// `(?&NAME)` setzt in Boost den Ausdruck der Gruppe NAME noch einmal ein;
    /// ICU kennt das nicht. Hier steht er an der Stelle selbst (als Gruppe ohne
    /// Namen), bis zur Tiefe 3; was sich tiefer selbst aufruft, passt nicht mehr.
    /// Blöcke `(?(DEFINE)…)` liefern nur Gruppen und fallen weg.
    static func ersetzeUnteraufrufe(_ muster: String) -> String {
        let rekursiv = ["(?&", "(?(DEFINE)", "(?R)", "(?0)"].contains { muster.contains($0) }
            || muster.range(of: #"\(\?[1-9]\)"#, options: .regularExpression) != nil
        guard rekursiv else { return muster }
        let z = Array(muster)
        // Gruppen nach Namen und nach Nummer; «R» ist der ganze Ausdruck.
        var gruppen: [String: String] = ["R": muster, "0": muster]
        var nummer = 0
        var i = 0
        while i < z.count {
            if z[i] == "\\" { i += 2; continue }
            if z[i] == "[", let zu = klassenende(z, ab: i) { i = zu + 1; continue }
            if z[i] == "(", i + 1 < z.count, z[i + 1] != "?", let zu = klammerende(z, ab: i) {
                nummer += 1
                gruppen["\(nummer)"] = String(z[(i + 1)..<zu])
            }
            if z[i] == "(", i + 2 < z.count, z[i + 1] == "?", z[i + 2] == "<", i + 3 < z.count, z[i + 3] != "=", z[i + 3] != "!",
                let nameEnde = z[(i + 3)...].firstIndex(of: ">"), let zu = klammerende(z, ab: i)
            {
                nummer += 1
                let name = String(z[(i + 3)..<nameEnde])
                let inhalt = String(z[(nameEnde + 1)..<zu])
                if gruppen[name] == nil { gruppen[name] = inhalt }
                gruppen["\(nummer)"] = inhalt
            }
            i += 1
        }
        // DEFINE-Blöcke entfernen.
        var ohneDefine: [Character] = []
        i = 0
        while i < z.count {
            if z[i] == "\\", i + 1 < z.count { ohneDefine += [z[i], z[i + 1]]; i += 2; continue }
            if z[i] == "(", String(z[i..<min(z.count, i + 10)]) == "(?(DEFINE)", let zu = klammerende(z, ab: i) {
                i = zu + 1
                continue
            }
            ohneDefine.append(z[i])
            i += 1
        }
        return setzeEin(String(ohneDefine), gruppen: gruppen, tiefe: 0)
    }

    private static func setzeEin(_ text: String, gruppen: [String: String], tiefe: Int) -> String {
        let z = Array(text)
        var aus = ""
        var i = 0
        while i < z.count {
            if z[i] == "\\", i + 1 < z.count { aus.append(z[i]); aus.append(z[i + 1]); i += 2; continue }
            if z[i] == "[", let zu = klassenende(z, ab: i) { aus += String(z[i...zu]); i = zu + 1; continue }
            // (?&name), (?R), (?0), (?1) …
            if z[i] == "(", i + 2 < z.count, z[i + 1] == "?",
                z[i + 2] == "&" || z[i + 2] == "R" || (z[i + 2].isASCII && z[i + 2].isNumber),
                let zu = z[(i + 2)...].firstIndex(of: ")"),
                z[i + 2] == "&" || z[(i + 2)..<zu].allSatisfy({ $0 == "R" || ($0.isASCII && $0.isNumber) })
            {
                let name = String(z[(z[i + 2] == "&" ? i + 3 : i + 2)..<zu])
                if tiefe >= 3 || gruppen[name] == nil {
                    aus += "(?!)"
                } else {
                    aus += "(?:" + setzeEin(ohneNamen(gruppen[name]!), gruppen: gruppen, tiefe: tiefe + 1) + ")"
                }
                i = zu + 1
                continue
            }
            aus.append(z[i])
            i += 1
        }
        return aus
    }

    /// Benannte Gruppen in einer eingesetzten Kopie werden namenlos (Namen dürfen nur einmal vorkommen).
    private static func ohneNamen(_ text: String) -> String {
        let z = Array(text)
        var aus = ""
        var i = 0
        while i < z.count {
            if z[i] == "\\", i + 1 < z.count { aus.append(z[i]); aus.append(z[i + 1]); i += 2; continue }
            if z[i] == "(", i + 3 < z.count, z[i + 1] == "?", z[i + 2] == "<", z[i + 3] != "=", z[i + 3] != "!",
                let nameEnde = z[(i + 3)...].firstIndex(of: ">")
            {
                aus += "(?:"
                i = nameEnde + 1
                continue
            }
            aus.append(z[i])
            i += 1
        }
        return aus
    }

    /// Index der «)», die die «(» bei `ab` schliesst; Escapes und Klassen zählen nicht.
    static func klammerende(_ z: [Character], ab: Int) -> Int? {
        var tiefe = 0
        var i = ab
        while i < z.count {
            switch z[i] {
            case "\\": i += 1
            case "[": if let zu = klassenende(z, ab: i) { i = zu }
            case "(": tiefe += 1
            case ")":
                tiefe -= 1
                if tiefe == 0 { return i }
            default: break
            }
            i += 1
        }
        return nil
    }

    /// Index der «]», die die Klasse bei `ab` schliesst.
    static func klassenende(_ z: [Character], ab: Int) -> Int? {
        var i = ab + 1
        if i < z.count, z[i] == "^" { i += 1 }
        if i < z.count, z[i] == "]" { i += 1 }
        while i < z.count {
            if z[i] == "\\" { i += 2; continue }
            if z[i] == "[", i + 1 < z.count, z[i + 1] == ":", let zu = z[(i + 2)...].firstIndex(of: "]") { i = zu + 1; continue }
            if z[i] == "]" { return i }
            i += 1
        }
        return nil
    }

    /// Index der «}» eines Quantors {n}, {n,} oder {n,m} ab `i`, sonst nil.
    private static func quantorende(_ z: [Character], ab i: Int) -> Int? {
        var j = i + 1
        var ziffern = 0
        while j < z.count, z[j].isASCII, z[j].isNumber { j += 1; ziffern += 1 }
        guard ziffern > 0, j < z.count else { return nil }
        if z[j] == "}" { return j }
        guard z[j] == "," else { return nil }
        j += 1
        while j < z.count, z[j].isASCII, z[j].isNumber { j += 1 }
        return j < z.count && z[j] == "}" ? j : nil
    }

    // MARK: Auswerten

    public func eintraege(in text: Suchtext) -> [Funktionseintrag] {
        let ns = text.string as NSString
        let laenge = ns.length
        let kommentare = kommentar.map { treffer($0, in: ns, von: 0, bis: laenge).map(\.ganz) } ?? []
        func imKommentar(_ stelle: Int) -> Bool { kommentare.contains { NSLocationInRange(stelle, $0) } }

        var funde: [Fund] = []
        var klassenZonen: [NSRange] = []

        if let klassen {
            var von = 0
            while von < laenge, let roh = treffer(klassen.haupt, in: ns, von: von, bis: laenge).first {
                var ende = NSMaxRange(roh.ganz)
                let name = kette(klassen.name, in: ns, bereich: roh.wirksam)
                if let klammern = klassen.klammern, let auf = klassen.auf {
                    ende = schliessendeKlammer(ab: ende, klammern: klammern, auf: auf, in: ns, kommentare: imKommentar)
                }
                let zone = NSRange(location: roh.wirksam.location, length: max(0, ende - roh.wirksam.location))
                klassenZonen.append(zone)
                if !imKommentar(roh.wirksam.location), let regel = klassen.funktion {
                    for f in funktionen(regel, in: ns, zone: zone, klasse: name?.text, imKommentar: imKommentar) {
                        funde.append(f)
                    }
                    // Die Klasse selbst, auch wenn sie (noch) keine Funktionen hat.
                    if let name { funde.append(Fund(name: name.text, stelle: name.stelle, klasse: nil, istKlasse: true)) }
                }
                guard ende > von else { break }
                von = max(ende, roh.wirksam.location + 1)
            }
        }

        if let regel = funktionen {
            // Ausserhalb der Klassen und (beim reinen Funktionsparser) der Kommentare.
            let sperren = klassen == nil ? kommentare : klassenZonen
            for zone in Self.luecken(zwischen: sperren, laenge: laenge) {
                funde += funktionen(regel, in: ns, zone: zone, klasse: nil, imKommentar: imKommentar)
            }
        }

        // Baum: Funktionen mit Klasse unter ihrer Klasse, in der Reihenfolge des Textes.
        var ergebnis: [Funktionseintrag] = []
        var klassenIndex: [String: Int] = [:]
        for fund in funde.sorted(by: { $0.stelle < $1.stelle }) {
            let byte = text.byte(fund.stelle)
            if fund.istKlasse {
                if klassenIndex[fund.name] == nil {
                    klassenIndex[fund.name] = ergebnis.count
                    ergebnis.append(Funktionseintrag(name: fund.name, stelle: byte))
                }
            } else if let klasse = fund.klasse {
                if let i = klassenIndex[klasse] {
                    ergebnis[i].kinder.append(Funktionseintrag(name: fund.name, stelle: byte))
                } else {
                    klassenIndex[klasse] = ergebnis.count
                    ergebnis.append(Funktionseintrag(name: klasse, stelle: byte, kinder: [Funktionseintrag(name: fund.name, stelle: byte)]))
                }
            } else {
                ergebnis.append(Funktionseintrag(name: fund.name, stelle: byte))
            }
        }
        return ergebnis
    }

    struct Fund {
        var name: String
        var stelle: Int
        var klasse: String?
        var istKlasse = false
    }

    private func funktionen(
        _ regel: Funktionsregel, in ns: NSString, zone: NSRange, klasse: String?, imKommentar: (Int) -> Bool
    ) -> [Fund] {
        var ergebnis: [Fund] = []
        for roh in treffer(regel.haupt, in: ns, von: zone.location, bis: NSMaxRange(zone)) {
            let name: (text: String, stelle: Int)?
            if regel.name.isEmpty {
                name = (ns.substring(with: roh.wirksam), roh.wirksam.location)
            } else {
                name = kette(regel.name, in: ns, bereich: roh.wirksam)
            }
            let eigeneKlasse = klasse ?? (regel.klasse.isEmpty ? nil : kette(regel.klasse, in: ns, bereich: roh.wirksam)?.text)
            guard let name, !imKommentar(name.stelle) else { continue }
            let sauber = name.text.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            guard !sauber.isEmpty else { continue }
            ergebnis.append(Fund(name: sauber, stelle: name.stelle, klasse: eigeneKlasse?.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return ergebnis
    }

    /// Wendet die Ausdrücke nacheinander an, jeden im Treffer des vorherigen.
    private func kette(_ ausdruecke: [NSRegularExpression], in ns: NSString, bereich: NSRange) -> (text: String, stelle: Int)? {
        guard !ausdruecke.isEmpty else { return nil }
        var aktuell = bereich
        for a in ausdruecke {
            guard let t = treffer(a, in: ns, von: aktuell.location, bis: NSMaxRange(aktuell), nurErster: true).first else {
                return nil
            }
            aktuell = t.wirksam
        }
        return (ns.substring(with: aktuell), aktuell.location)
    }

    /// Bis zur passenden schliessenden Klammer (getBodyClosePos in Notepad++).
    private func schliessendeKlammer(
        ab: Int, klammern: NSRegularExpression, auf: NSRegularExpression, in ns: NSString, kommentare: (Int) -> Bool
    ) -> Int {
        var offen = 1
        var von = ab
        let laenge = ns.length
        while offen > 0 {
            guard let t = treffer(klammern, in: ns, von: von, bis: laenge, nurErster: true).first else { return laenge }
            let ende = NSMaxRange(t.ganz)
            if !kommentare(t.ganz.location) {
                let istAuf = auf.firstMatch(in: ns as String, options: [.anchored], range: t.ganz) != nil
                offen += istAuf ? 1 : -1
            }
            von = max(ende, t.ganz.location + 1)
            if von >= laenge { return laenge }
        }
        return von
    }

    /// Ein Treffer: ganz, und ab einem \K (sonst gleich).
    struct Roh {
        let ganz: NSRange
        let wirksam: NSRange
    }

    /// Alle Treffer zwischen von und bis. Der Ausdruck sieht den Text davor,
    /// aber nicht dahinter (wie die Suche im Zielbereich von Scintilla).
    private func treffer(
        _ a: NSRegularExpression, in ns: NSString, von: Int, bis: Int, nurErster: Bool = false
    ) -> [Roh] {
        guard bis > von else { return [] }
        let heu = bis < ns.length ? ns.substring(to: bis) : ns as String
        let bereich = NSRange(location: von, length: bis - von)
        let optionen: NSRegularExpression.MatchingOptions = [.withTransparentBounds, .withoutAnchoringBounds]
        let liste = nurErster
            ? [a.firstMatch(in: heu, options: optionen, range: bereich)].compactMap { $0 }
            : a.matches(in: heu, options: optionen, range: bereich)
        // Nur nach Gruppen fragen, die es gibt: range(withName:) mit fremdem Namen
        // kann eine Objective-C-Ausnahme werfen.
        let kGruppen = (0..<8).map { "kladdeK\($0)" }.filter { a.pattern.contains("(?<\($0)>)") }
        return liste.map { m in
            var anfang = m.range.location
            for name in kGruppen {
                let k = m.range(withName: name)
                if k.location != NSNotFound { anfang = max(anfang, k.location) }
            }
            let ende = NSMaxRange(m.range)
            return Roh(ganz: m.range, wirksam: NSRange(location: anfang, length: max(0, ende - anfang)))
        }
    }

    /// Die Bereiche zwischen den gesperrten (getInvertZones).
    static func luecken(zwischen gesperrt: [NSRange], laenge: Int) -> [NSRange] {
        var ergebnis: [NSRange] = []
        var von = 0
        for zone in gesperrt.sorted(by: { $0.location < $1.location }) {
            if zone.location > von { ergebnis.append(NSRange(location: von, length: zone.location - von)) }
            von = max(von, NSMaxRange(zone))
        }
        if von < laenge { ergebnis.append(NSRange(location: von, length: laenge - von)) }
        return ergebnis
    }
}
