import AppKit

/// Was gerade gesucht wird. Gilt für alle Fenster und Tabs gleich und
/// übersteht den Neustart, wie in Notepad++.
final class SuchZustand {
    static let gemeinsam = SuchZustand()
    static let geaendert = Notification.Name("KladdeSucheGeaendert")

    var optionen: SuchOptionen {
        didSet {
            guard optionen != oldValue else { return }
            if let json = try? JSONEncoder().encode(optionen) { UserDefaults.standard.set(json, forKey: "Suche") }
            NotificationCenter.default.post(name: Self.geaendert, object: self)
        }
    }

    private init() {
        optionen = UserDefaults.standard.data(forKey: "Suche")
            .flatMap { try? JSONDecoder().decode(SuchOptionen.self, from: $0) } ?? SuchOptionen()
    }

    func muster() throws -> Suchmuster { try Suchmuster(optionen) }
}

/// Suchen, Ersetzen und Markieren in einem Editor. Die Antwort ist der Satz
/// für die Anzeige der Suchleiste.
enum Suchaktion {
    struct Antwort {
        var text: String
        var fehler = false
    }

    /// Nächster oder vorheriger Treffer ab der Auswahl; wählt ihn aus.
    static func weiter(in editor: Editor, rueckwaerts: Bool = false) -> Antwort {
        let muster: Suchmuster
        do { muster = try SuchZustand.gemeinsam.muster() } catch { return fehler(error) }
        let text = editor.suchtext
        let auswahl = editor.auswahl
        let ab = rueckwaerts ? auswahl.lowerBound : auswahl.upperBound
        guard
            let (treffer, umgebrochen) = muster.naechster(
                in: text, ab: ab, rueckwaerts: rueckwaerts, ausser: auswahl.isEmpty ? auswahl.lowerBound : nil)
        else { return Antwort(text: "Nicht gefunden", fehler: true) }
        editor.waehleAus(treffer.bereich)
        return Antwort(text: zaehle(muster, in: text, aktuell: treffer.bereich, umgebrochen: umgebrochen, rueckwaerts: rueckwaerts))
    }

    /// Wie die Suche im Feld beim Tippen: ab einer festen Stelle, mit allen
    /// Treffern hinterlegt.
    static func live(in editor: Editor, ab stelle: Int) -> Antwort {
        editor.loescheMarkierungen(Editor.indikatorSuche)
        guard !SuchZustand.gemeinsam.optionen.text.isEmpty else { return Antwort(text: "") }
        let muster: Suchmuster
        do { muster = try SuchZustand.gemeinsam.muster() } catch { return fehler(error) }
        let text = editor.suchtext
        guard let (treffer, umgebrochen) = muster.naechster(in: text, ab: stelle) else {
            editor.waehleAus(stelle..<stelle)
            return Antwort(text: "Nicht gefunden", fehler: true)
        }
        editor.waehleAus(treffer.bereich)
        // Grosse Texte: nur den einen Treffer, damit das Tippen flüssig bleibt.
        guard text.laenge < 10_000_000 else { return Antwort(text: umgebrochen ? "Vom Anfang weitergesucht" : "") }
        let alle = muster.alle(in: text)
        editor.markiere(alle.map(\.bereich), indikator: Editor.indikatorSuche)
        return Antwort(text: satz(nummer: alle.firstIndex { $0.bereich == treffer.bereich }, von: alle.count, umgebrochen: umgebrochen, rueckwaerts: false))
    }

    /// Ersetzt die Auswahl, wenn sie ein Treffer ist, und sucht den nächsten.
    static func ersetzen(in editor: Editor) -> Antwort {
        let muster: Suchmuster
        do { muster = try SuchZustand.gemeinsam.muster() } catch { return fehler(error) }
        let text = editor.suchtext
        let auswahl = editor.auswahl
        if let treffer = muster.alle(in: text, bereich: auswahl).first(where: { $0.bereich == auswahl }) {
            let ersatz = muster.ersetzung(fuer: treffer, in: text)
            editor.ersetze([(auswahl, ersatz)])
            let danach = auswahl.lowerBound + ersatz.utf8.count
            editor.waehleAus(danach..<danach)
        }
        return weiter(in: editor)
    }

    static func alleErsetzen(in editor: Editor, nurAuswahl: Bool) -> Antwort {
        let muster: Suchmuster
        do { muster = try SuchZustand.gemeinsam.muster() } catch { return fehler(error) }
        let auswahl = editor.auswahl
        if nurAuswahl, auswahl.isEmpty { return Antwort(text: "Keine Auswahl", fehler: true) }
        let liste = muster.ersetzungen(in: editor.suchtext, bereich: nurAuswahl ? auswahl : nil)
        editor.ersetze(liste)
        return Antwort(text: liste.isEmpty ? "Nicht gefunden" : "\(liste.count) ersetzt", fehler: liste.isEmpty)
    }

    /// Wie «Alle markieren» in Notepad++: bleibt stehen, bis «Markierungen entfernen».
    static func alleMarkieren(in editor: Editor, nurAuswahl: Bool, lesezeichen: Bool = false, leeren: Bool = true) -> Antwort {
        let muster: Suchmuster
        do { muster = try SuchZustand.gemeinsam.muster() } catch { return fehler(error) }
        let auswahl = editor.auswahl
        if nurAuswahl, auswahl.isEmpty { return Antwort(text: "Keine Auswahl", fehler: true) }
        let treffer = muster.alle(in: editor.suchtext, bereich: nurAuswahl ? auswahl : nil)
        if leeren { editor.loescheMarkierungen(Editor.indikatorMarkiert) }
        editor.markiere(treffer.map(\.bereich), indikator: Editor.indikatorMarkiert)
        if lesezeichen { editor.setzeLesezeichen(fuer: treffer.map(\.bereich)) }
        return Antwort(text: treffer.isEmpty ? "Nicht gefunden" : "\(treffer.count) markiert", fehler: treffer.isEmpty)
    }

    /// Ersetzt in allen offenen Dokumenten; jedes wird geändert, nicht gesichert.
    static func alleErsetzenInOffenen() -> Antwort {
        let muster: Suchmuster
        do { muster = try SuchZustand.gemeinsam.muster() } catch { return fehler(error) }
        var anzahl = 0
        var dokumente = 0
        for dokument in Dokumente.inTabfolge() {
            guard let editor = dokument.editor else { continue }
            let liste = muster.ersetzungen(in: editor.suchtext)
            guard !liste.isEmpty else { continue }
            editor.ersetze(liste)
            anzahl += liste.count
            dokumente += 1
        }
        return Antwort(
            text: anzahl == 0 ? "Nicht gefunden" : "\(anzahl) ersetzt in \(dokumente) \(dokumente == 1 ? "Datei" : "Dateien")",
            fehler: anzahl == 0)
    }

    // MARK: Sätze

    private static func zaehle(
        _ muster: Suchmuster, in text: Suchtext, aktuell: Range<Int>, umgebrochen: Bool, rueckwaerts: Bool
    ) -> String {
        guard text.laenge < 10_000_000 else { return umgebrochen ? (rueckwaerts ? "Vom Ende weitergesucht" : "Vom Anfang weitergesucht") : "" }
        let alle = muster.alle(in: text)
        return satz(nummer: alle.firstIndex { $0.bereich == aktuell }, von: alle.count, umgebrochen: umgebrochen, rueckwaerts: rueckwaerts)
    }

    private static func satz(nummer: Int?, von: Int, umgebrochen: Bool, rueckwaerts: Bool) -> String {
        var satz = nummer.map { "\($0 + 1) von \(von)" } ?? "\(von) Treffer"
        if umgebrochen { satz += rueckwaerts ? " · vom Ende weitergesucht" : " · vom Anfang weitergesucht" }
        return satz
    }

    private static func fehler(_ fehler: Error) -> Antwort {
        Antwort(text: (fehler as? Suchfehler)?.meldung ?? fehler.localizedDescription, fehler: true)
    }
}
