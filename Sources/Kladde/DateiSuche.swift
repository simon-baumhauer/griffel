import AppKit

/// «In Dateien suchen» und «Ersetzen in Dateien» ohne eigenes Fenster: Der
/// Reiter im Suchen-Dialog ruft das auf. Sucht im Hintergrund, füllt das
/// Suchergebnis unten im Fenster und fragt vor dem Ersetzen nach.
final class Dateisuche {
    struct Auftrag {
        var ordner: String
        var filter: String
        var unterordner: Bool
        var versteckte: Bool
    }

    /// Gesetzt, solange eine Suche läuft; der Lauf fragt ihn vor jeder Datei.
    private final class Abbruch {
        private let schloss = NSLock()
        private var gesetzt = false
        func setze() { schloss.lock(); gesetzt = true; schloss.unlock() }
        var istGesetzt: Bool { schloss.lock(); defer { schloss.unlock() }; return gesetzt }
    }

    static let gemeinsam = Dateisuche()
    private var abbruch: Abbruch?
    var laeuft: Bool { abbruch != nil }

    func abbrechen() { abbruch?.setze() }

    /// `meldung` bekommt Zwischenstand und Ergebnis, `fertig` den Schlusssatz (für die Selbstprüfung).
    func starte(
        _ auftrag: Auftrag, ersetzen: Bool, bestaetigt: Bool = false, fenster: NSWindow?,
        meldung: @escaping (String, Bool) -> Void, fertig: ((String) -> Void)? = nil
    ) {
        guard abbruch == nil else { return }
        let muster: Suchmuster
        do { muster = try SuchZustand.gemeinsam.muster() } catch {
            return meldung((error as? Suchfehler)?.meldung ?? error.localizedDescription, true)
        }
        let pfad = (auftrag.ordner as NSString).expandingTildeInPath
        var istOrdner: ObjCBool = false
        guard !pfad.isEmpty, FileManager.default.fileExists(atPath: pfad, isDirectory: &istOrdner), istOrdner.boolValue
        else { return meldung("Verzeichnis nicht gefunden", true) }

        let suche = Ordnersuche(
            ordner: URL(fileURLWithPath: pfad, isDirectory: true), filter: Dateifilter(auftrag.filter),
            unterordner: auftrag.unterordner, versteckte: auftrag.versteckte)
        let abbruch = Abbruch()
        self.abbruch = abbruch
        meldung(Oberflaeche.gemeinsam.texte["find-in-files-progress-title"] ?? "Suche läuft …", false)

        let ergebnisse = Suchergebnisse.gemeinsam
        let liste = ergebnisse.beginne(muster.optionen, ort: nil)
        liste.laeuft = true
        DispatchQueue.global(qos: .userInitiated).async {
            var gefunden: [URL] = []
            let stand = suche.durchsuche(muster, abbrechen: { abbruch.istGesetzt }) { fund in
                gefunden.append(fund.url)
                let funde = Fundzeilen.aus(fund.treffer, in: fund.text)
                DispatchQueue.main.async {
                    ergebnisse.fuegeHinzu(Suchergebnisse.Datei(name: fund.url.path, url: fund.url, dokument: nil, funde: funde), zu: liste)
                }
            }
            DispatchQueue.main.async {
                liste.geprueft = stand.geprueft
                ergebnisse.beende(liste)
                self.abbruch = nil
                var satz = "In Dateien suchen: \(stand.treffer) Treffer in \(stand.dateienMitTreffern) von \(stand.geprueft) Dateien"
                if stand.uebersprungen > 0 { satz += ", \(stand.uebersprungen) übersprungen (binär oder zu gross)" }
                if stand.abgebrochen { satz += " – abgebrochen" }
                meldung(satz, stand.treffer == 0)
                guard ersetzen, !stand.abgebrochen, stand.treffer > 0 else { fertig?(satz); return }
                self.frageUndErsetze(gefunden, treffer: stand.treffer, muster: muster, bestaetigt: bestaetigt,
                                     fenster: fenster, meldung: meldung, fertig: fertig)
            }
        }
    }

    private func frageUndErsetze(
        _ dateien: [URL], treffer: Int, muster: Suchmuster, bestaetigt: Bool, fenster: NSWindow?,
        meldung: @escaping (String, Bool) -> Void, fertig: ((String) -> Void)?
    ) {
        let los = { self.ersetze(dateien, muster: muster, fenster: fenster, meldung: meldung, fertig: fertig) }
        guard !bestaetigt, let fenster else { return los() }
        let frage = NSAlert()
        frage.messageText = "\(treffer) Treffer in \(dateien.count) \(dateien.count == 1 ? "Datei" : "Dateien") ersetzen?"
        frage.informativeText = """
            Dateien, die in NoteMac++ offen sind, ändert NoteMac++ dort und speichert sie nicht. \
            Alle anderen schreibt NoteMac++ sofort auf die Platte; das lässt sich nicht rückgängig machen.
            """
        frage.alertStyle = .warning
        frage.addButton(withTitle: "Ersetzen")
        frage.addButton(withTitle: "Abbrechen")
        frage.beginSheetModal(for: fenster) { antwort in
            if antwort == .alertFirstButtonReturn { los() } else { fertig?("nicht ersetzt") }
        }
    }

    private func ersetze(
        _ dateien: [URL], muster: Suchmuster, fenster: NSWindow?, meldung: @escaping (String, Bool) -> Void,
        fertig: ((String) -> Void)?
    ) {
        var offen: [Dokument] = []
        var aufPlatte: [URL] = []
        for url in dateien {
            if let dokument = NSDocumentController.shared.document(for: url) as? Dokument, dokument.editor != nil {
                offen.append(dokument)
            } else {
                aufPlatte.append(url)
            }
        }
        var anzahl = 0
        for dokument in offen {
            guard let editor = dokument.editor else { continue }
            let liste = muster.ersetzungen(in: editor.suchtext)
            editor.ersetze(liste)
            anzahl += liste.count
        }
        DispatchQueue.global(qos: .userInitiated).async {
            var fehler: [String] = []
            var geschrieben = 0
            for url in aufPlatte {
                do {
                    let n = try Ordnersuche.ersetze(in: url, mit: muster)
                    anzahl += n
                    if n > 0 { geschrieben += 1 }
                } catch {
                    fehler.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            DispatchQueue.main.async {
                var satz = "Ersetzen in Dateien: \(anzahl) ersetzt, \(geschrieben) Dateien geschrieben, \(offen.count) offene geändert"
                if !fehler.isEmpty { satz += ", \(fehler.count) nicht geändert" }
                meldung(satz, !fehler.isEmpty)
                if !fehler.isEmpty, let fenster {
                    let hinweis = NSAlert()
                    hinweis.messageText = "\(fehler.count) \(fehler.count == 1 ? "Datei blieb" : "Dateien blieben") unverändert"
                    hinweis.informativeText = fehler.prefix(12).joined(separator: "\n")
                    hinweis.beginSheetModal(for: fenster)
                }
                fertig?(satz)
            }
        }
    }
}
