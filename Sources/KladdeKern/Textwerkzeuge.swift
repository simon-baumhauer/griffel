import Foundation

/// Die Zeilenbefehle von Notepad++ («Edit → Line Operations» und «Blank
/// Operations»), als reine Funktionen auf Zeilen ohne Zeilenende.
public enum Zeilenwerkzeug {
    /// Wie «Sort Lines …» in Notepad++.
    public enum Sortierung: String, CaseIterable {
        case aufsteigend, absteigend
        case ohneGrossKleinAuf, ohneGrossKleinAb
        case ganzzahlAuf, ganzzahlAb
        case dezimalPunktAuf, dezimalPunktAb
        case dezimalKommaAuf, dezimalKommaAb
        case laengeAuf, laengeAb
        case gebietsschemaAuf, gebietsschemaAb
        case umkehren, zufaellig

        public var name: String {
            switch self {
            case .aufsteigend: return "Aufsteigend"
            case .absteigend: return "Absteigend"
            case .ohneGrossKleinAuf: return "Aufsteigend, ohne Gross/klein"
            case .ohneGrossKleinAb: return "Absteigend, ohne Gross/klein"
            case .ganzzahlAuf: return "Als Ganzzahlen aufsteigend"
            case .ganzzahlAb: return "Als Ganzzahlen absteigend"
            case .dezimalPunktAuf: return "Als Dezimalzahlen (1.5) aufsteigend"
            case .dezimalPunktAb: return "Als Dezimalzahlen (1.5) absteigend"
            case .dezimalKommaAuf: return "Als Dezimalzahlen (1,5) aufsteigend"
            case .dezimalKommaAb: return "Als Dezimalzahlen (1,5) absteigend"
            case .laengeAuf: return "Nach Länge aufsteigend"
            case .laengeAb: return "Nach Länge absteigend"
            case .gebietsschemaAuf: return "Nach Gebietsschema aufsteigend"
            case .gebietsschemaAb: return "Nach Gebietsschema absteigend"
            case .umkehren: return "Reihenfolge umkehren"
            case .zufaellig: return "Zufällig"
            }
        }
    }

    /// Stabil: Gleiche bleiben in ihrer Reihenfolge. Bei den Zahlen stehen
    /// Zeilen, die keine Zahl sind, unverändert am Ende.
    public static func sortiere(_ zeilen: [String], _ art: Sortierung) -> [String] {
        let nummeriert = Array(zeilen.enumerated())
        func stabil(_ vorher: (String, String) -> Bool) -> [String] {
            nummeriert.sorted { a, b in
                if vorher(a.element, b.element) { return true }
                if vorher(b.element, a.element) { return false }
                return a.offset < b.offset
            }.map(\.element)
        }
        func nachZahl(_ lies: (String) -> Double?, absteigend: Bool) -> [String] {
            let mit = nummeriert.compactMap { e in lies(e.element).map { (e.offset, $0, e.element) } }
            let ohne = nummeriert.filter { lies($0.element) == nil }.map(\.element)
            let sortiert = mit.sorted { a, b in
                a.1 != b.1 ? (absteigend ? a.1 > b.1 : a.1 < b.1) : a.0 < b.0
            }
            return sortiert.map(\.2) + ohne
        }
        switch art {
        case .aufsteigend: return stabil { $0.unicodeScalars.lexicographicallyPrecedes($1.unicodeScalars) }
        case .absteigend: return stabil { $1.unicodeScalars.lexicographicallyPrecedes($0.unicodeScalars) }
        case .ohneGrossKleinAuf: return stabil { $0.caseInsensitiveCompare($1) == .orderedAscending }
        case .ohneGrossKleinAb: return stabil { $0.caseInsensitiveCompare($1) == .orderedDescending }
        case .ganzzahlAuf: return nachZahl(ganzzahl, absteigend: false)
        case .ganzzahlAb: return nachZahl(ganzzahl, absteigend: true)
        case .dezimalPunktAuf: return nachZahl({ dezimal($0, komma: false) }, absteigend: false)
        case .dezimalPunktAb: return nachZahl({ dezimal($0, komma: false) }, absteigend: true)
        case .dezimalKommaAuf: return nachZahl({ dezimal($0, komma: true) }, absteigend: false)
        case .dezimalKommaAb: return nachZahl({ dezimal($0, komma: true) }, absteigend: true)
        case .laengeAuf: return stabil { $0.count < $1.count }
        case .laengeAb: return stabil { $0.count > $1.count }
        case .gebietsschemaAuf: return stabil { $0.localizedCompare($1) == .orderedAscending }
        case .gebietsschemaAb: return stabil { $0.localizedCompare($1) == .orderedDescending }
        case .umkehren: return zeilen.reversed()
        case .zufaellig: return zeilen.shuffled()
        }
    }

    /// Die Zahl am Anfang der Zeile (nach Leerzeichen), mit Vorzeichen.
    static func ganzzahl(_ zeile: String) -> Double? {
        let rest = zeile.drop(while: { $0 == " " || $0 == "\t" })
        var ziffern = ""
        for (i, z) in rest.enumerated() {
            if z.isASCII, z.isNumber { ziffern.append(z) } else if i == 0, z == "-" || z == "+" { ziffern.append(z) } else { break }
        }
        return Int(ziffern).map(Double.init)
    }

    static func dezimal(_ zeile: String, komma: Bool) -> Double? {
        let rest = zeile.drop(while: { $0 == " " || $0 == "\t" })
        var zahl = ""
        var trenner = false
        for (i, z) in rest.enumerated() {
            if z.isASCII, z.isNumber {
                zahl.append(z)
            } else if i == 0, z == "-" || z == "+" {
                zahl.append(z)
            } else if !trenner, z == (komma ? "," : ".") {
                zahl.append(".")
                trenner = true
            } else {
                break
            }
        }
        return Double(zahl)
    }

    /// Lässt nur das erste Vorkommen jeder Zeile stehen.
    public static func ohneDoppelte(_ zeilen: [String]) -> [String] {
        var gesehen = Set<String>()
        return zeilen.filter { gesehen.insert($0).inserted }
    }

    /// Entfernt Zeilen, die gleich der vorherigen sind.
    public static func ohneAufeinanderfolgendeDoppelte(_ zeilen: [String]) -> [String] {
        var ergebnis: [String] = []
        for zeile in zeilen where zeile != ergebnis.last || ergebnis.isEmpty {
            ergebnis.append(zeile)
        }
        return ergebnis
    }

    public static func ohneLeere(_ zeilen: [String], auchNurLeerzeichen: Bool) -> [String] {
        zeilen.filter { auchNurLeerzeichen ? !$0.allSatisfy { $0 == " " || $0 == "\t" } : !$0.isEmpty }
    }

    public enum Kuerzen { case ende, anfang, beide }

    public static func kuerze(_ zeilen: [String], _ wo: Kuerzen) -> [String] {
        let weiss: (Character) -> Bool = { $0 == " " || $0 == "\t" }
        return zeilen.map { zeile in
            var z = Substring(zeile)
            if wo != .ende { z = z.drop(while: weiss) }
            if wo != .anfang { while let letztes = z.last, weiss(letztes) { z = z.dropLast() } }
            return String(z)
        }
    }

    /// Tabs werden zu so vielen Leerzeichen, wie bis zur nächsten Tabstelle fehlen.
    public static func tabsZuLeerzeichen(_ zeilen: [String], breite: Int) -> [String] {
        zeilen.map { zeile in
            var ergebnis = ""
            var spalte = 0
            for z in zeile {
                if z == "\t" {
                    let fehlt = breite - spalte % breite
                    ergebnis += String(repeating: " ", count: fehlt)
                    spalte += fehlt
                } else {
                    ergebnis.append(z)
                    spalte += 1
                }
            }
            return ergebnis
        }
    }

    /// Überall: Leerzeichen bis zu einer Tabstelle werden zu einem Tab (wie
    /// «Leerzeichen in TAB (alle)» in Notepad++). Einzelne Leerzeichen bleiben.
    public static func leerzeichenZuTabs(_ zeilen: [String], breite: Int) -> [String] {
        zeilen.map { zeile in
            var ergebnis = ""
            var spalte = 0
            var leer = 0
            func schreibeLeer(bisTabstelle: Bool) {
                if bisTabstelle, leer > 1 { ergebnis.append("\t") } else { ergebnis += String(repeating: " ", count: leer) }
                leer = 0
            }
            for z in zeile {
                if z == " " {
                    leer += 1
                    spalte += 1
                    if spalte % breite == 0 { schreibeLeer(bisTabstelle: true) }
                } else if z == "\t" {
                    leer = 0
                    ergebnis.append("\t")
                    spalte += breite - spalte % breite
                } else {
                    schreibeLeer(bisTabstelle: false)
                    ergebnis.append(z)
                    spalte += 1
                }
            }
            schreibeLeer(bisTabstelle: false)
            return ergebnis
        }
    }

    /// Nur die Einrückung: volle Tabbreiten aus Leerzeichen werden zu Tabs.
    public static func fuehrendeLeerzeichenZuTabs(_ zeilen: [String], breite: Int) -> [String] {
        zeilen.map { zeile in
            let einzug = zeile.prefix { $0 == " " || $0 == "\t" }
            let rest = zeile.dropFirst(einzug.count)
            let spalten = tabsZuLeerzeichen([String(einzug)], breite: breite)[0].count
            return String(repeating: "\t", count: spalten / breite) + String(repeating: " ", count: spalten % breite) + rest
        }
    }
}

/// «Edit → Convert Case to» in Notepad++.
public enum Schreibung: String, CaseIterable {
    case gross, klein, woerterGross, woerterGrossBelassen, satzanfang, satzanfangBelassen, umkehren, zufaellig

    public var name: String {
        switch self {
        case .gross: return "GROSSBUCHSTABEN"
        case .klein: return "kleinbuchstaben"
        case .woerterGross: return "Jedes Wort Gross"
        case .woerterGrossBelassen: return "Jedes Wort Gross (Rest belassen)"
        case .satzanfang: return "Satzanfang gross"
        case .satzanfangBelassen: return "Satzanfang gross (Rest belassen)"
        case .umkehren: return "gROSS/kLEIN uMKEHREN"
        case .zufaellig: return "ZuFäLLiG"
        }
    }

    public func wende(an text: String) -> String {
        switch self {
        case .gross: return text.uppercased()
        case .klein: return text.lowercased()
        case .umkehren:
            return String(text.map { z in
                let s = String(z)
                return Character(s == s.uppercased() ? s.lowercased() : s.uppercased())
            }.map(String.init).joined())
        case .zufaellig:
            return text.map { Bool.random() ? String($0).uppercased() : String($0).lowercased() }.joined()
        case .woerterGross, .woerterGrossBelassen:
            var ergebnis = ""
            var imWort = false
            for z in text {
                let s = String(z)
                let wortzeichen = z.isLetter || z.isNumber || z == "'" || z == "’"
                if wortzeichen, !imWort {
                    ergebnis += s.uppercased()
                } else if wortzeichen {
                    ergebnis += self == .woerterGross ? s.lowercased() : s
                } else {
                    ergebnis += s
                }
                imWort = wortzeichen
            }
            return ergebnis
        case .satzanfang, .satzanfangBelassen:
            var ergebnis = ""
            var neuerSatz = true
            for z in text {
                let s = String(z)
                if z.isLetter {
                    ergebnis += neuerSatz ? s.uppercased() : (self == .satzanfang ? s.lowercased() : s)
                    neuerSatz = false
                } else {
                    ergebnis += s
                    if z == "." || z == "!" || z == "?" || z.isNewline { neuerSatz = true }
                }
            }
            return ergebnis
        }
    }
}

/// Kommentare umschalten wie «Toggle Single Line Comment» (Ctrl+Q) und
/// «Block Comment» (Ctrl+Shift+Q) in Notepad++.
public enum Kommentar {
    /// Sind alle nicht leeren Zeilen kommentiert, fällt das Zeichen weg (samt
    /// einem Leerzeichen danach); sonst kommt es in alle, auf die kleinste
    /// Einrückung. Leere Zeilen bleiben, wie sie sind.
    public enum Art { case umschalten, setzen, entfernen }

    public static func zeilenUmschalten(_ zeilen: [String], zeichen: String, art: Art = .umschalten) -> [String] {
        let inhalt = zeilen.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !inhalt.isEmpty else { return zeilen }
        let alleKommentiert = inhalt.allSatisfy {
            $0.drop(while: { $0 == " " || $0 == "\t" }).hasPrefix(zeichen)
        }
        if art == .entfernen || (art == .umschalten && alleKommentiert) {
            return zeilen.map { zeile in
                let einzug = zeile.prefix { $0 == " " || $0 == "\t" }
                var rest = zeile.dropFirst(einzug.count)
                guard rest.hasPrefix(zeichen) else { return zeile }
                rest = rest.dropFirst(zeichen.count)
                if rest.first == " " { rest = rest.dropFirst() }
                return String(einzug) + rest
            }
        }
        let einzug = inhalt.map { $0.prefix { $0 == " " || $0 == "\t" }.count }.min() ?? 0
        return zeilen.map { zeile in
            guard !zeile.trimmingCharacters(in: .whitespaces).isEmpty else { return zeile }
            let i = zeile.index(zeile.startIndex, offsetBy: einzug)
            return String(zeile[..<i]) + zeichen + " " + zeile[i...]
        }
    }

    /// Umschliesst den Text mit Anfang und Ende, oder nimmt sie weg, wenn er
    /// schon so beginnt und endet (Leerzeichen innen inklusive).
    public static func blockUmschalten(_ text: String, anfang: String, ende: String) -> String {
        let innen = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if innen.hasPrefix(anfang), innen.hasSuffix(ende), innen.count >= anfang.count + ende.count {
            var kern = innen.dropFirst(anfang.count).dropLast(ende.count)
            if kern.first == " " { kern = kern.dropFirst() }
            if kern.last == " " { kern = kern.dropLast() }
            // Was vor und hinter dem Kommentar stand (Einrückung, Zeilenende), bleibt.
            let vorne = text.prefix { $0.isWhitespace }
            let hinten = String(text.reversed().prefix { $0.isWhitespace }.reversed())
            return vorne + kern + hinten
        }
        return anfang + " " + text + " " + ende
    }
}

/// Zahlen für den Spalteneditor («Edit → Column Editor» in Notepad++).
public struct Zahlenfolge: Equatable {
    public enum Fuehrend: Int { case keine, nullen, leerzeichen }

    public var anfang = 1
    public var schritt = 1
    /// Jede Zahl so oft hintereinander.
    public var wiederholen = 1
    public var basis = 10
    public var fuehrend = Fuehrend.keine
    public var grossbuchstaben = true

    public init() {}

    /// Die Zahlen für so viele Zeilen. Mit führenden Nullen oder Leerzeichen
    /// sind alle so breit wie die breiteste.
    public func texte(_ anzahl: Int) -> [String] {
        let werte = (0..<max(0, anzahl)).map { anfang + schritt * ($0 / max(1, wiederholen)) }
        let roh = werte.map { wert -> String in
            let ziffern = String(abs(wert), radix: basis, uppercase: grossbuchstaben)
            return (wert < 0 ? "-" : "") + ziffern
        }
        guard fuehrend != .keine, let breite = roh.map(\.count).max() else { return roh }
        return roh.map { text in
            let fehlt = breite - text.count
            guard fehlt > 0 else { return text }
            if fuehrend == .leerzeichen { return String(repeating: " ", count: fehlt) + text }
            // Nullen nach dem Minus: -007
            if text.hasPrefix("-") { return "-" + String(repeating: "0", count: fehlt) + text.dropFirst() }
            return String(repeating: "0", count: fehlt) + text
        }
    }
}
