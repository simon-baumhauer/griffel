import Foundation

/// Was gesucht wird und wie, wie im Dialog «Suchen» von Notepad++.
public struct SuchOptionen: Equatable, Codable {
    /// Die drei Suchmodi von Notepad++.
    public enum Modus: Int, CaseIterable, Codable {
        /// Der Text gilt wörtlich.
        case normal
        /// Wörtlich, aber \n \r \t \0 \\ \xHH \uHHHH \oOOO \dDDD \bBBBBBBBB stehen für ein Zeichen.
        case erweitert
        /// Regulärer Ausdruck (ICU, nahe an der Boost-Regex von Notepad++).
        case regulaer

        public var name: String {
            switch self {
            case .normal: return "Normal"
            case .erweitert: return "Erweitert (\\n, \\t …)"
            case .regulaer: return "Regulärer Ausdruck"
            }
        }
    }

    public var text = ""
    public var ersetzung = ""
    public var modus = Modus.normal
    public var grossKlein = false
    public var ganzesWort = false
    /// Nur im Modus «Regulärer Ausdruck»: «.» passt auch auf Zeilenenden.
    public var punktFindetZeilenende = false
    /// Am Ende des Textes vorne weitersuchen.
    public var umbruch = true

    public init() {}
}

public struct Suchfehler: LocalizedError, Equatable {
    public let meldung: String
    public init(meldung: String) { self.meldung = meldung }
    public var errorDescription: String? { meldung }
}

/// Ein Treffer. Bereiche als Bytes im UTF-8-Text (wie die Positionen in
/// Scintilla) und als UTF-16 (für die Gruppen des Ausdrucks).
public struct Treffer: Equatable {
    public let bereich: Range<Int>
    /// Gruppe 0 ist der ganze Treffer; nicht beteiligte Gruppen: NSNotFound.
    public let gruppen: [NSRange]
}

/// Ein Text, in dem gesucht wird. Hält ihn als UTF-8 (wie Scintilla) und
/// rechnet zwischen Bytes und UTF-16 (wie NSRegularExpression) um.
public final class Suchtext {
    public let utf8: Data
    public let string: String
    let ns: NSString
    private lazy var zeilenanfaenge: [Int] = Self.zeilenanfaenge(in: utf8)

    public init(utf8: Data) {
        self.utf8 = utf8
        string = String(decoding: utf8, as: UTF8.self)
        ns = string as NSString
    }

    public convenience init(_ text: String) { self.init(utf8: Data(text.utf8)) }

    public var laenge: Int { utf8.count }

    func utf16(_ byte: Int) -> Int {
        string.utf8.index(string.startIndex, offsetBy: min(max(0, byte), utf8.count)).utf16Offset(in: string)
    }

    func byte(_ utf16: Int) -> Int {
        let stelle = String.Index(utf16Offset: utf16, in: string)
        return string.utf8.distance(from: string.utf8.startIndex, to: stelle)
    }

    func teil(_ bereich: NSRange) -> String {
        bereich.location == NSNotFound ? "" : ns.substring(with: bereich)
    }

    /// Zeile (ab 1) und ihr Bereich in Bytes, ohne Zeilenende. Zeilen enden
    /// wie in Scintilla mit \r\n, \n oder \r.
    public func zeile(bei byte: Int) -> (nummer: Int, bereich: Range<Int>) {
        let anfaenge = zeilenanfaenge
        var unten = 0
        var oben = anfaenge.count - 1
        while unten < oben {
            let mitte = (unten + oben + 1) / 2
            if anfaenge[mitte] <= byte { unten = mitte } else { oben = mitte - 1 }
        }
        let anfang = anfaenge[unten]
        var ende = unten + 1 < anfaenge.count ? anfaenge[unten + 1] : utf8.count
        while ende > anfang, utf8[utf8.startIndex + ende - 1] == 0x0A || utf8[utf8.startIndex + ende - 1] == 0x0D {
            ende -= 1
        }
        return (unten + 1, anfang..<ende)
    }

    private static func zeilenanfaenge(in daten: Data) -> [Int] {
        var anfaenge = [0]
        daten.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            var i = 0
            while i < bytes.count {
                let b = bytes[i]
                if b == 0x0D {
                    if i + 1 < bytes.count, bytes[i + 1] == 0x0A { i += 1 }
                    anfaenge.append(i + 1)
                } else if b == 0x0A {
                    anfaenge.append(i + 1)
                }
                i += 1
            }
        }
        return anfaenge
    }
}

/// Eine übersetzte Suche: findet Treffer und baut Ersetzungen.
public struct Suchmuster {
    public let optionen: SuchOptionen
    private let ausdruck: NSRegularExpression
    private let ersetzungsteile: [Ersetzungsteil]

    public init(_ optionen: SuchOptionen) throws {
        guard !optionen.text.isEmpty else { throw Suchfehler(meldung: "Kein Suchtext") }
        self.optionen = optionen

        var muster: String
        switch optionen.modus {
        case .normal:
            muster = NSRegularExpression.escapedPattern(for: optionen.text)
        case .erweitert:
            muster = NSRegularExpression.escapedPattern(for: try Self.entschluessele(optionen.text))
        case .regulaer:
            muster = optionen.text
        }
        if optionen.ganzesWort {
            // Wortzeichen wie in Scintilla: Buchstaben, Ziffern, «_».
            muster = "(?<![\\p{L}\\p{N}_])(?:\(muster))(?![\\p{L}\\p{N}_])"
        }
        var schalter: NSRegularExpression.Options = [.anchorsMatchLines]
        if !optionen.grossKlein { schalter.insert(.caseInsensitive) }
        if optionen.modus == .regulaer, optionen.punktFindetZeilenende { schalter.insert(.dotMatchesLineSeparators) }
        do {
            ausdruck = try NSRegularExpression(pattern: muster, options: schalter)
        } catch {
            throw Suchfehler(meldung: "Ungültiger Ausdruck")
        }

        switch optionen.modus {
        case .normal: ersetzungsteile = [.text(optionen.ersetzung)]
        case .erweitert: ersetzungsteile = [.text(try Self.entschluessele(optionen.ersetzung))]
        case .regulaer: ersetzungsteile = try Self.zerlegeVorlage(optionen.ersetzung)
        }
    }

    // MARK: Finden

    /// Alle Treffer, die in den Bereich fallen (Bytes; ohne: der ganze Text).
    /// Der Ausdruck sieht dabei auch über die Grenzen (für ^, $ und \b).
    public func alle(in text: Suchtext, bereich: Range<Int>? = nil) -> [Treffer] {
        let von = text.utf16(bereich?.lowerBound ?? 0)
        let bis = text.utf16(bereich?.upperBound ?? text.laenge)
        return ausdruck.matches(
            in: text.string, options: [.withTransparentBounds, .withoutAnchoringBounds],
            range: NSRange(location: von, length: bis - von)
        ).map { treffer(aus: $0, in: text) }
    }

    /// Der erste Treffer ab einer Stelle (vorwärts) oder der letzte, der vor
    /// ihr beginnt (rückwärts). Mit Umbruch geht die Suche ums Ende herum;
    /// `umgebrochen` sagt, ob sie das musste.
    public func naechster(
        in text: Suchtext, ab stelle: Int, rueckwaerts: Bool = false, ausser leererBei: Int? = nil
    ) -> (treffer: Treffer, umgebrochen: Bool)? {
        if rueckwaerts {
            let alle = alle(in: text)
            if let davor = alle.last(where: { $0.bereich.lowerBound < stelle }) { return (davor, false) }
            if optionen.umbruch, let letzter = alle.last { return (letzter, true) }
            return nil
        }
        if let treffer = erster(in: text, ab: stelle, ausser: leererBei) { return (treffer, false) }
        if optionen.umbruch, stelle > 0, let treffer = erster(in: text, ab: 0, ausser: nil) { return (treffer, true) }
        return nil
    }

    private func erster(in text: Suchtext, ab stelle: Int, ausser leererBei: Int?) -> Treffer? {
        var von = text.utf16(stelle)
        let ende = (text.string as NSString).length
        while von <= ende {
            guard
                let roh = ausdruck.firstMatch(
                    in: text.string, options: [.withTransparentBounds, .withoutAnchoringBounds],
                    range: NSRange(location: von, length: ende - von))
            else { return nil }
            let treffer = treffer(aus: roh, in: text)
            // Ein leerer Treffer genau dort, wo der letzte war, zählt nicht: sonst
            // bliebe «Weitersuchen» bei ^ oder $ stehen.
            if treffer.bereich.isEmpty, treffer.bereich.lowerBound == leererBei {
                von = roh.range.location + max(1, (text.string as NSString).rangeOfComposedCharacterSequence(at: min(roh.range.location, max(0, ende - 1))).length)
                continue
            }
            return treffer
        }
        return nil
    }

    private func treffer(aus roh: NSTextCheckingResult, in text: Suchtext) -> Treffer {
        let gruppen = (0..<roh.numberOfRanges).map { roh.range(at: $0) }
        let bereich = text.byte(roh.range.location)..<text.byte(roh.range.location + roh.range.length)
        return Treffer(bereich: bereich, gruppen: gruppen)
    }

    // MARK: Ersetzen

    /// Der Ersatz für einen Treffer, mit Gruppen und Gross-/Kleinschreibung.
    public func ersetzung(fuer treffer: Treffer, in text: Suchtext) -> String {
        var ergebnis = ""
        var dauerhaft: Fall?  // \U \L bis \E
        var einmal: Fall?  // \u \l für das nächste Zeichen
        func haenge(_ teil: String) {
            for zeichen in teil {
                var z = String(zeichen)
                if let fall = einmal {
                    z = fall == .gross ? z.uppercased() : z.lowercased()
                    einmal = nil
                } else if let fall = dauerhaft {
                    z = fall == .gross ? z.uppercased() : z.lowercased()
                }
                ergebnis += z
            }
        }
        for teil in ersetzungsteile {
            switch teil {
            case .text(let t): haenge(t)
            case .gruppe(let n): haenge(n < treffer.gruppen.count ? text.teil(treffer.gruppen[n]) : "")
            case .fall(let f, let nurEinmal):
                if nurEinmal { einmal = f } else { dauerhaft = f }
            case .fallEnde: dauerhaft = nil
            }
        }
        return ergebnis
    }

    /// Alle Ersetzungen im Text: Bereich in Bytes und neuer Text, von vorne nach hinten.
    public func ersetzungen(in text: Suchtext, bereich: Range<Int>? = nil) -> [(bereich: Range<Int>, text: String)] {
        alle(in: text, bereich: bereich).map { ($0.bereich, ersetzung(fuer: $0, in: text)) }
    }

    /// Der ganze Text mit allen Ersetzungen, als UTF-8.
    public func ersetzeAlle(in text: Suchtext) -> (utf8: Data, anzahl: Int) {
        let liste = ersetzungen(in: text)
        guard !liste.isEmpty else { return (text.utf8, 0) }
        var neu = Data(capacity: text.utf8.count)
        var bisher = 0
        for (bereich, ersatz) in liste {
            neu.append(text.utf8[text.utf8.startIndex + bisher..<text.utf8.startIndex + bereich.lowerBound])
            neu.append(contentsOf: Array(ersatz.utf8))
            bisher = bereich.upperBound
        }
        neu.append(text.utf8[(text.utf8.startIndex + bisher)...])
        return (neu, liste.count)
    }

    // MARK: Übersetzen

    enum Fall { case gross, klein }

    enum Ersetzungsteil: Equatable {
        case text(String)
        case gruppe(Int)
        case fall(Fall, einmal: Bool)
        case fallEnde
    }

    /// Ersetzungstext im Modus «Regulärer Ausdruck»: $0–$99, ${n}, $&, \0–\9,
    /// \n \r \t \\ \$, \xHH, \U \L \E \u \l. Jedes andere \x steht für x.
    static func zerlegeVorlage(_ vorlage: String) throws -> [Ersetzungsteil] {
        var teile: [Ersetzungsteil] = []
        var text = ""
        func schliesse() {
            if !text.isEmpty { teile.append(.text(text)); text = "" }
        }
        let z = Array(vorlage)
        var i = 0
        while i < z.count {
            let c = z[i]
            if c == "$", i + 1 < z.count {
                let n = z[i + 1]
                if n == "&" {
                    schliesse(); teile.append(.gruppe(0)); i += 2; continue
                }
                if n == "{", let zu = z[(i + 2)...].firstIndex(of: "}"), let nummer = Int(String(z[(i + 2)..<zu])) {
                    schliesse(); teile.append(.gruppe(nummer)); i = zu + 1; continue
                }
                if n.isASCII, n.isNumber {
                    var j = i + 1
                    var ziffern = ""
                    while j < z.count, z[j].isASCII, z[j].isNumber, ziffern.count < 2 { ziffern.append(z[j]); j += 1 }
                    schliesse(); teile.append(.gruppe(Int(ziffern)!)); i = j; continue
                }
            }
            if c == "\\", i + 1 < z.count {
                let n = z[i + 1]
                switch n {
                case "0"..."9":
                    schliesse(); teile.append(.gruppe(Int(String(n))!))
                case "n": text.append("\n")
                case "r": text.append("\r")
                case "t": text.append("\t")
                case "U": schliesse(); teile.append(.fall(.gross, einmal: false))
                case "L": schliesse(); teile.append(.fall(.klein, einmal: false))
                case "u": schliesse(); teile.append(.fall(.gross, einmal: true))
                case "l": schliesse(); teile.append(.fall(.klein, einmal: true))
                case "E": schliesse(); teile.append(.fallEnde)
                case "x":
                    let hex = String(z[(i + 2)..<min(i + 4, z.count)])
                    guard hex.count == 2, let wert = UInt32(hex, radix: 16), let skalar = Unicode.Scalar(wert) else {
                        throw Suchfehler(meldung: "\\x braucht zwei Hexziffern")
                    }
                    text.unicodeScalars.append(skalar)
                    i += 4
                    continue
                default: text.append(n)
                }
                i += 2
                continue
            }
            text.append(c)
            i += 1
        }
        schliesse()
        return teile
    }

    /// Modus «Erweitert»: Escapes wie in Notepad++ (FindReplaceDlg::convertExtendedToString).
    static func entschluessele(_ eingabe: String) throws -> String {
        var ergebnis = ""
        let z = Array(eingabe)
        var i = 0
        func zahl(_ stellen: Int, _ basis: Int, _ name: String) throws -> Character {
            let ziffern = String(z[(i + 2)..<min(i + 2 + stellen, z.count)])
            guard ziffern.count == stellen, let wert = UInt32(ziffern, radix: basis), let skalar = Unicode.Scalar(wert)
            else { throw Suchfehler(meldung: "\\\(name) braucht \(stellen) Ziffern") }
            i += 2 + stellen
            return Character(skalar)
        }
        while i < z.count {
            guard z[i] == "\\", i + 1 < z.count else {
                ergebnis.append(z[i]); i += 1; continue
            }
            switch z[i + 1] {
            case "n": ergebnis.append("\n"); i += 2
            case "r": ergebnis.append("\r"); i += 2
            case "t": ergebnis.append("\t"); i += 2
            case "0": ergebnis.append("\0"); i += 2
            case "\\": ergebnis.append("\\"); i += 2
            case "x": ergebnis.append(try zahl(2, 16, "x"))
            case "u": ergebnis.append(try zahl(4, 16, "u"))
            case "o": ergebnis.append(try zahl(3, 8, "o"))
            case "d": ergebnis.append(try zahl(3, 10, "d"))
            case "b": ergebnis.append(try zahl(8, 2, "b"))
            default: ergebnis.append(z[i]); ergebnis.append(z[i + 1]); i += 2
            }
        }
        return ergebnis
    }
}
