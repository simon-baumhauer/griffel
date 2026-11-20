import Foundation

/// Eine Zeile mit Treffern, wie sie die Ergebnisliste zeigt: «Zeile 12: …».
public struct Fundzeile: Equatable {
    /// Ab 1.
    public let nummer: Int
    /// Die Zeile, bei langen Zeilen ein Ausschnitt um den ersten Treffer; Tabs als Leerzeichen.
    public let text: String
    /// Die Treffer in `text` (UTF-16, für NSAttributedString).
    public let hervorhebungen: [NSRange]
    /// Die Treffer im ganzen Text (Bytes), zum Hinspringen.
    public let bereiche: [Range<Int>]
}

public enum Fundzeilen {
    /// So viele Bytes einer Zeile zeigt die Liste höchstens.
    public static let hoechstens = 400

    /// Fasst Treffer zeilenweise zusammen, in der Reihenfolge des Textes. Ein
    /// Treffer über mehrere Zeilen zählt zu der, in der er beginnt.
    public static func aus(_ treffer: [Treffer], in text: Suchtext) -> [Fundzeile] {
        var zeilen: [Fundzeile] = []
        var i = 0
        while i < treffer.count {
            let (nummer, zeile) = text.zeile(bei: treffer[i].bereich.lowerBound)
            var bereiche: [Range<Int>] = []
            while i < treffer.count, treffer[i].bereich.lowerBound <= zeile.upperBound,
                treffer[i].bereich.lowerBound >= zeile.lowerBound
            {
                bereiche.append(treffer[i].bereich)
                i += 1
            }
            zeilen.append(baue(nummer: nummer, zeile: zeile, bereiche: bereiche, in: text))
        }
        return zeilen
    }

    private static func baue(nummer: Int, zeile: Range<Int>, bereiche: [Range<Int>], in text: Suchtext) -> Fundzeile {
        let daten = text.utf8
        func istFolgebyte(_ stelle: Int) -> Bool {
            stelle < zeile.upperBound && daten[daten.startIndex + stelle] & 0xC0 == 0x80
        }
        // Ausschnitt: ab etwas vor dem ersten Treffer, nicht mitten in einem Zeichen.
        var von = zeile.lowerBound
        if zeile.count > hoechstens, let erster = bereiche.first {
            von = max(zeile.lowerBound, erster.lowerBound - 60)
            while von > zeile.lowerBound, istFolgebyte(von) { von -= 1 }
        }
        var bis = min(zeile.upperBound, von + hoechstens)
        while bis < zeile.upperBound, istFolgebyte(bis) { bis -= 1 }

        func utf16(_ byte: Int) -> Int {
            let b = min(max(byte, von), bis)
            return String(decoding: daten[(daten.startIndex + von)..<(daten.startIndex + b)], as: UTF8.self).utf16.count
        }
        let hervorhebungen = bereiche.compactMap { bereich -> NSRange? in
            let anfang = utf16(bereich.lowerBound)
            let ende = utf16(min(bereich.upperBound, zeile.upperBound))
            return ende > anfang ? NSRange(location: anfang, length: ende - anfang) : nil
        }
        var ausschnitt = String(decoding: daten[(daten.startIndex + von)..<(daten.startIndex + bis)], as: UTF8.self)
        ausschnitt = ausschnitt.replacingOccurrences(of: "\t", with: " ")
        if von > zeile.lowerBound { ausschnitt = "…" + ausschnitt }
        let versatz = von > zeile.lowerBound ? 1 : 0
        if bis < zeile.upperBound { ausschnitt += "…" }
        return Fundzeile(
            nummer: nummer, text: ausschnitt,
            hervorhebungen: hervorhebungen.map { NSRange(location: $0.location + versatz, length: $0.length) },
            bereiche: bereiche)
    }
}
