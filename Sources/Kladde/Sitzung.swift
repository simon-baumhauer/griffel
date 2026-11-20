import AppKit

/// Was beim Beenden offen war, ist beim nächsten Start wieder da — auch Tabs,
/// die nie gesichert wurden, und ungesicherte Änderungen. Wie Notepad++ fragt
/// Kladde darum beim Beenden nicht nach.
///
/// Ablage: ~/Library/Application Support/Kladde/Sitzung/ mit sitzung.json und
/// je ungesichertem Dokument einer Datei «<id>.sicherung» (der Text als UTF-8).
/// Die Dateien der Dokumente selbst fasst die Sitzung nie an.
enum Sitzung {
    private struct Eintrag: Codable {
        var pfad: String?
        var sicherung: String?
        var kodierung: Textdatei.Kodierung
        var zeilenende: Textdatei.Zeilenende
        var position: Int
        var ersteZeile: Int
        var aktiv: Bool
        /// Nur wenn von Hand im Menü «Sprache» gewählt; sonst wird neu erkannt.
        var sprache: String?
        /// Zeilen mit Lesezeichen, ab 0.
        var lesezeichen: [Int]?
    }

    /// Mit «-KladdeSitzung /pfad» beim Start liegt die Sitzung woanders (für Prüfläufe).
    private static let ordner: URL = {
        if let pfad = UserDefaults.standard.string(forKey: "KladdeSitzung") {
            return URL(fileURLWithPath: pfad, isDirectory: true)
        }
        let ablage = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return ablage.appendingPathComponent("Kladde/Sitzung", isDirectory: true)
    }()

    private static var liste: URL { ordner.appendingPathComponent("sitzung.json") }

    // MARK: Sichern

    static func sichere() {
        let dateien = FileManager.default
        try? dateien.createDirectory(at: ordner, withIntermediateDirectories: true)
        guard Einstellungen.sitzungMerken else {
            // Abgeschaltet: nichts merken, auch keine alten Sicherungen liegen lassen.
            try? dateien.removeItem(at: ordner)
            return
        }

        // Das vorderste Fenster, auch wenn die App gerade nicht aktiv ist
        // (dann gibt es kein mainWindow).
        let vorne = Hauptfenster.gemeinsam.aktivesDokument
        var eintraege: [Eintrag] = []
        var sicherungen: Set<String> = []
        for dokument in Dokumente.inTabfolge() {
            guard let editor = dokument.editor else { continue }
            let stand = dokument.aktuell()
            var sicherung: String?
            if dokument.isDocumentEdited {
                let name = dokument.sitzungsId + ".sicherung"
                guard (try? stand.utf8.write(to: ordner.appendingPathComponent(name), options: .atomic)) != nil else {
                    continue
                }
                sicherung = name
                sicherungen.insert(name)
            } else if dokument.fileURL == nil {
                continue  // leer und nie gesichert: nichts zu merken
            }
            eintraege.append(
                Eintrag(
                    pfad: dokument.fileURL?.path, sicherung: sicherung,
                    kodierung: stand.kodierung, zeilenende: stand.zeilenende,
                    position: editor.position, ersteZeile: editor.ersteZeile,
                    aktiv: dokument === vorne, sprache: dokument.gewaehlteSprache,
                    lesezeichen: editor.lesezeichen.isEmpty ? nil : editor.lesezeichen))
        }

        guard let json = try? JSONEncoder().encode(eintraege),
            (try? json.write(to: liste, options: .atomic)) != nil
        else { return }

        // Sicherungen, die keine Zeile der Liste mehr nennt.
        for datei in (try? dateien.contentsOfDirectory(at: ordner, includingPropertiesForKeys: nil)) ?? []
        where datei.pathExtension == "sicherung" && !sicherungen.contains(datei.lastPathComponent) {
            try? dateien.removeItem(at: datei)
        }
    }

    // MARK: Als Datei (Datei → Sitzung speichern/öffnen)

    private struct Datei: Codable {
        var dateien: [String]
        var aktiv: Int?
    }

    /// Speichert die Liste der offenen Dateien (ohne ungesicherte Inhalte) in eine Datei.
    static func sichereInDatei() {
        guard let fenster = Hauptfenster.gemeinsam.window else { return }
        let wahl = NSSavePanel()
        wahl.nameFieldStringValue = "Sitzung.kladde-sitzung"
        wahl.beginSheetModal(for: fenster) { antwort in
            guard antwort == .OK, let ziel = wahl.url else { return }
            let tabs = Hauptfenster.gemeinsam.tabs
            let inhalt = Datei(
                dateien: tabs.compactMap { $0.fileURL?.path },
                aktiv: tabs.filter { $0.fileURL != nil }.firstIndex { $0 === Hauptfenster.gemeinsam.aktivesDokument })
            do {
                let kodierer = JSONEncoder()
                kodierer.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
                try kodierer.encode(inhalt).write(to: ziel)
            } catch {
                NSApp.presentError(error)
            }
        }
    }

    /// Öffnet die Dateien einer gespeicherten Sitzung als weitere Tabs.
    static func ladeAusDatei() {
        guard let fenster = Hauptfenster.gemeinsam.window else { return }
        let wahl = NSOpenPanel()
        wahl.beginSheetModal(for: fenster) { antwort in
            guard antwort == .OK, let url = wahl.url else { return }
            do {
                let inhalt = try JSONDecoder().decode(Datei.self, from: Data(contentsOf: url))
                for (i, pfad) in inhalt.dateien.enumerated() {
                    NSDocumentController.shared.openDocument(withContentsOf: URL(fileURLWithPath: pfad), display: true) { d, _, _ in
                        if i == inhalt.aktiv, let d = d as? Dokument { Hauptfenster.gemeinsam.aktiviere(d) }
                    }
                }
            } catch {
                NSApp.presentError(error)
            }
        }
    }

    // MARK: Wiederherstellen

    /// Öffnet, was die letzte Sitzung nennt. Antwort: wie viele Dokumente.
    @discardableResult
    static func stelleWiederHer() -> Int {
        guard Einstellungen.sitzungMerken, let json = try? Data(contentsOf: liste),
            let eintraege = try? JSONDecoder().decode([Eintrag].self, from: json)
        else { return 0 }

        var geoeffnet = 0
        var vorne: Dokument?
        for eintrag in eintraege {
            let url = eintrag.pfad.map { URL(fileURLWithPath: $0) }
            let dokument: Dokument
            if let name = eintrag.sicherung,
                let text = try? Data(contentsOf: ordner.appendingPathComponent(name))
            {
                var datei = Textdatei()
                datei.utf8 = text
                datei.kodierung = eintrag.kodierung
                datei.zeilenende = eintrag.zeilenende
                dokument = Dokument()
                dokument.stelleUngesichertWiederHer(datei, datei: url)
            } else if let url, let ausDatei = try? Dokument(contentsOf: url, ofType: "public.plain-text") {
                dokument = ausDatei
            } else {
                continue  // Datei gelöscht oder verschoben, und keine Sicherung
            }
            NSDocumentController.shared.addDocument(dokument)
            dokument.gewaehlteSprache = eintrag.sprache
            dokument.makeWindowControllers()
            dokument.showWindows()
            dokument.editor?.position = eintrag.position
            dokument.editor?.ersteZeile = eintrag.ersteZeile
            if let zeilen = eintrag.lesezeichen { dokument.editor?.lesezeichen = zeilen }
            if eintrag.aktiv { vorne = dokument }
            geoeffnet += 1
        }
        if let vorne { Hauptfenster.gemeinsam.aktiviere(vorne) }
        return geoeffnet
    }
}
