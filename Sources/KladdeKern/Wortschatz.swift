import Foundation

/// Die Autovervollständigung einer Sprache aus installer/APIs/<sprache>.xml von
/// Notepad++: Schlüsselwörter und Funktionen samt Aufrufen für die Aufrufhilfe.
public struct Wortschatz {
    public struct Aufruf: Equatable {
        public let rueckgabe: String
        public let parameter: [String]
        public let beschreibung: String
    }

    public let woerter: [String]
    /// Funktion → ihre Aufrufe (Überladungen).
    public let funktionen: [String: [Aufruf]]
    public let ohneGrossKlein: Bool
    public let aufrufAnfang: Character
    public let aufrufEnde: Character
    public let trenner: Character
    /// Zeichen, die hier zum Wort gehören (etwa «.» in Python für os.path).
    public let wortzeichen: String

    public static let leer = Wortschatz(
        woerter: [], funktionen: [:], ohneGrossKlein: false, aufrufAnfang: "(", aufrufEnde: ")", trenner: ",",
        wortzeichen: "")

    public static func lade(_ url: URL) throws -> Wortschatz {
        try lade(xml: Data(contentsOf: url))
    }

    public static func lade(xml: Data) throws -> Wortschatz {
        let dokument = try XMLDocument(data: Funktionsliste.zeilenumbruecheBewahrt(xml))
        let umgebung = try dokument.nodes(forXPath: "//AutoComplete/Environment").first as? XMLElement
        func attribut(_ e: XMLElement?, _ name: String) -> String? { e?.attribute(forName: name)?.stringValue }
        func zeichen(_ name: String, _ vorgabe: Character) -> Character { attribut(umgebung, name)?.first ?? vorgabe }

        var woerter: [String] = []
        var funktionen: [String: [Aufruf]] = [:]
        for case let wort as XMLElement in try dokument.nodes(forXPath: "//AutoComplete/KeyWord") {
            guard let name = attribut(wort, "name"), !name.isEmpty else { continue }
            woerter.append(name)
            guard attribut(wort, "func") == "yes" else { continue }
            funktionen[name] = wort.elements(forName: "Overload").map { ueber in
                Aufruf(
                    rueckgabe: attribut(ueber, "retVal") ?? "",
                    parameter: ueber.elements(forName: "Param").compactMap { attribut($0, "name") },
                    beschreibung: attribut(ueber, "descr") ?? "")
            }
        }
        return Wortschatz(
            woerter: woerter, funktionen: funktionen,
            ohneGrossKlein: attribut(umgebung, "ignoreCase") == "yes",
            aufrufAnfang: zeichen("startFunc", "("), aufrufEnde: zeichen("stopFunc", ")"),
            trenner: zeichen("paramSeparator", ","), wortzeichen: attribut(umgebung, "additionalWordChar") ?? "")
    }

    /// Vorschläge für einen Wortanfang: Wörter der Sprache und des Textes, die
    /// mit ihm beginnen, ohne ihn selbst, alphabetisch, höchstens `hoechstens`.
    public func vorschlaege(fuer anfang: String, ausText textwoerter: Set<String>, hoechstens: Int = 400) -> [String] {
        guard !anfang.isEmpty else { return [] }
        let klein = anfang.lowercased()
        var gesehen = Set<String>()
        var ergebnis: [String] = []
        let passt: (String) -> Bool = ohneGrossKlein
            ? { $0.lowercased().hasPrefix(klein) }
            : { $0.hasPrefix(anfang) }
        // Wörter aus dem Text immer ohne Rücksicht auf Gross/klein, wie die Wortvervollständigung in Notepad++.
        for wort in woerter where passt(wort) && wort != anfang && gesehen.insert(wort).inserted {
            ergebnis.append(wort)
        }
        for wort in textwoerter where wort.lowercased().hasPrefix(klein) && wort != anfang && gesehen.insert(wort).inserted {
            ergebnis.append(wort)
        }
        return Array(ergebnis.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }.prefix(hoechstens))
    }

    /// Die Wörter eines Textes, ab drei Zeichen (Buchstaben, Ziffern, «_»).
    public static func woerter(in text: String, zusaetzlich: String = "") -> Set<String> {
        var ergebnis = Set<String>()
        var wort = ""
        func schliesse() {
            if wort.count >= 3, !(wort.first?.isNumber ?? false) { ergebnis.insert(wort) }
            wort = ""
        }
        for z in text {
            if z.isLetter || z.isNumber || z == "_" || zusaetzlich.contains(z) { wort.append(z) } else { schliesse() }
        }
        schliesse()
        return ergebnis
    }

    /// Der Text der Aufrufhilfe: «rückgabe name(a, b)» und darunter die
    /// Beschreibung; dazu, wo der Parameter Nummer `aktiv` steht (UTF-8-Bytes,
    /// wie SCI_CALLTIPSETHLT sie will).
    public func aufrufhilfe(fuer name: String, aktiv: Int) -> (text: String, hervorheben: Range<Int>?)? {
        guard let aufruf = funktionen[name]?.first else { return nil }
        var text = aufruf.rueckgabe.isEmpty ? "" : aufruf.rueckgabe + " "
        text += name + String(aufrufAnfang)
        var hervor: Range<Int>?
        for (i, p) in aufruf.parameter.enumerated() {
            if i > 0 { text += String(trenner) + " " }
            let von = text.utf8.count
            text += p
            if i == aktiv { hervor = von..<text.utf8.count }
        }
        text += String(aufrufEnde)
        if !aufruf.beschreibung.isEmpty {
            // Manche Beschreibungen sind seitenlang; die Hilfe zeigt den Anfang.
            let zeilen = aufruf.beschreibung.split(separator: "\n", omittingEmptySubsequences: false)
            text += "\n" + zeilen.prefix(15).joined(separator: "\n") + (zeilen.count > 15 ? "\n…" : "")
        }
        if let mehr = funktionen[name]?.count, mehr > 1 { text += "\n(\(mehr) Varianten)" }
        return (text, hervor)
    }
}
