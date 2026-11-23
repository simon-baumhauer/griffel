import AppKit
import ScintillaBruecke

/// Selbstprüfung der laufenden App, für den Bau ohne Zuschauer:
///
///     open -n -a build/NoteMac++.app datei1 datei2 --args -KladdeProbe /pfad/zum/ordner \
///         [-KladdeProbeAktion sichern|tippen|nichts] [-KladdeSitzung /pfad/zur/sitzung]
///
/// Die App schreibt je Dokument ein Bild und in bericht.txt, was sie sieht.
/// Danach, je nach Aktion:
///   sichern  tippt ins letzte Dokument mit Datei und sichert es (Vorgabe)
///   tippen   tippt in jedes Dokument, ohne zu sichern, stellt das erste auf
///            UTF-16 LE und das letzte auf CRLF um — für die Sitzung
///   nichts   nur berichten
/// und beendet sich auf dem normalen Weg (also mit Sitzung). Ohne
/// «-KladdeProbe» geschieht nichts. («open --env» taugt nicht: Die Dateien
/// kommen dann nicht bei der App an.)
enum Probe {
    static func starteFallsVerlangt() {
        guard let pfad = UserDefaults.standard.string(forKey: "KladdeProbe") else { return }
        let aktion = UserDefaults.standard.string(forKey: "KladdeProbeAktion") ?? "sichern"
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            lauf(in: URL(fileURLWithPath: pfad, isDirectory: true), aktion: aktion)
        }
    }

    private static func lauf(in ordner: URL, aktion: String) {
        var bericht: [String] = []
        func schliesse() {
            try? bericht.joined(separator: "\n").write(
                to: ordner.appendingPathComponent("bericht.txt"), atomically: true, encoding: .utf8)
            NSApp.terminate(nil)
        }

        bericht.append("menü: " + (NSApp.mainMenu?.items.map(\.title).joined(separator: " | ") ?? "keines"))
        bericht.append("app-menü: " + (NSApp.mainMenu?.items.first?.submenu?.items
            .map { $0.isSeparatorItem ? "—" : $0.title }.joined(separator: " | ") ?? "keines"))
        bericht.append("fenstertitel: " + (Hauptfenster.gemeinsam.window?.title ?? "keiner"))
        let h = Hauptfenster.gemeinsam
        let vorne = h.aktivesDokument
        let dokumente = h.tabs
        let fenster = h.window!
        for (nummer, dokument) in dokumente.enumerated() {
            guard let editor = dokument.editor else { continue }
            let anfang = String(decoding: editor.utf8.prefix(40), as: UTF8.self)
                .replacingOccurrences(of: "\r", with: "\\r").replacingOccurrences(of: "\n", with: "\\n")
            bericht.append(
                "dokument \(nummer): «\(dokument.displayName ?? "?")» \(dokument.datei.kodierung.name), "
                    + "zeilenende \(dokument.datei.zeilenende), geändert \(dokument.isDocumentEdited), "
                    + "tabs \(dokumente.count), marke \(editor.position)"
                    + (dokument === vorne ? ", vorne" : "") + ", sprache \(editor.sprache.name)"
                    + (dokument.gewaehlteSprache != nil ? " (gewählt)" : "") + ", text «\(anfang)»")
        }
        for (nummer, dokument) in dokumente.enumerated() {
            do {
                h.aktiviere(dokument)
                bild(von: fenster, nach: ordner.appendingPathComponent("fenster-\(nummer).png"))
            }
        }

        switch aktion {
        case "etappe6":
            etappe6(ordner: ordner, bericht: { bericht.append($0) }, fertig: schliesse)
            return
        case "etappe5":
            etappe5(ordner: ordner, bericht: { bericht.append($0) }, fertig: schliesse)
            return
        case "review":
            review(ordner: ordner, bericht: { bericht.append($0) }, fertig: schliesse)
            return
        case "bedienung":
            bedienung(ordner: ordner, bericht: { bericht.append($0) }, fertig: schliesse)
            return
        case "plugins":
            plugins(ordner: ordner, bericht: { bericht.append($0) }, fertig: schliesse)
            return
        case "oberflaeche":
            oberflaeche(ordner: ordner, bericht: { bericht.append($0) }, fertig: schliesse)
            return
        case "bilder":
            bilder(ordner: ordner, bericht: { bericht.append($0) }, fertig: schliesse)
            return
        case "suchen":
            sucheProbe(dokumente: dokumente, ordner: ordner, bericht: { bericht.append($0) }, fertig: schliesse)
            return
        case "tippen":
            for dokument in dokumente {
                dokument.editor?.ansicht.insertText("ungesichert ✓\n")
            }
            if let erstes = dokumente.first { erstes.wandleUm(in: .utf16LE) }
            if dokumente.count > 1, let letztes = dokumente.last {
                letztes.setzeZeilenende(.crlf)
            }
            bericht.append("getippt in \(dokumente.count), geändert: "
                + dokumente.map { String($0.isDocumentEdited) }.joined(separator: " "))
            if let vorne { h.aktiviere(vorne) }
            return schliesse()
        case "nichts":
            return schliesse()
        case "darstellung":
            // Jedes Dokument in drei Farbschemata, dann mit Symbolen, markierter
            // Klammer und eingeklappt. Die Einstellungen gehen danach zurück.
            let vorher = (Einstellungen.farbschema, Einstellungen.leerzeichenZeigen, Einstellungen.zeilenendenZeigen)
            var schritte: [() -> Void] = []
            for (nummer, dokument) in dokumente.enumerated() {
                guard let editor = dokument.editor else { continue }
                schritte.append { h.aktiviere(dokument) }
                for schema in ["Standard", "DarkModeDefault", "Monokai"] {
                    schritte.append { Einstellungen.farbschema = schema }
                    schritte.append { bild(von: fenster, nach: ordner.appendingPathComponent("\(nummer)-\(schema).png")) }
                }
                schritte.append {
                    Einstellungen.farbschema = "Standard"
                    Einstellungen.leerzeichenZeigen = true
                    Einstellungen.zeilenendenZeigen = true
                    // Auf die erste öffnende Klammer, damit das Paar leuchtet.
                    if let stelle = editor.utf8.firstIndex(where: { $0 == UInt8(ascii: "{") || $0 == UInt8(ascii: "(") }) {
                        editor.position = stelle
                    }
                }
                schritte.append { bild(von: fenster, nach: ordner.appendingPathComponent("\(nummer)-symbole.png")) }
                schritte.append {
                    let offen = editor.sichtbareZeilen
                    editor.klappeAlles(ein: true)
                    bericht.append("dokument \(nummer): sichtbare zeilen \(offen), eingeklappt \(editor.sichtbareZeilen)")
                }
                schritte.append { bild(von: fenster, nach: ordner.appendingPathComponent("\(nummer)-eingeklappt.png")) }
                schritte.append {
                    editor.klappeAlles(ein: false)
                    Einstellungen.leerzeichenZeigen = false
                    Einstellungen.zeilenendenZeigen = false
                }
            }
            // «Automatisch» bei dunklem macOS (hier nur für die App umgestellt).
            if let erstes = dokumente.first {
                schritte.append { h.aktiviere(erstes); Einstellungen.farbschema = ""; NSApp.appearance = NSAppearance(named: .darkAqua) }
                schritte.append {}
                schritte.append { bild(von: fenster, nach: ordner.appendingPathComponent("0-automatisch-dunkel.png")) }
                schritte.append { NSApp.appearance = nil }
            }
            schritte.append {
                (Einstellungen.farbschema, Einstellungen.leerzeichenZeigen, Einstellungen.zeilenendenZeigen) = vorher
                schliesse()
            }
            // Mit Pausen, damit Scintilla zwischen den Schritten zeichnet und färbt.
            for (index, schritt) in schritte.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 * Double(index), execute: schritt)
            }
            return
        case "sprache":
            // Das erste Dokument von Hand auf Python stellen (für die Sitzung).
            if let erstes = dokumente.first {
                let wahl = NSMenuItem()
                wahl.representedObject = "python"
                erstes.spracheWaehlen(wahl)
                bericht.append("gewählt: \(erstes.editor?.sprache.name ?? "?")")
            }
            return schliesse()
        case "kodierung":
            // Erstes Dokument mit Datei: in UTF-16 LE sichern, dann als Windows-1252 neu öffnen.
            guard let dokument = dokumente.first(where: { $0.fileURL != nil }), let ziel = dokument.fileURL else {
                bericht.append("kodierung: kein Dokument mit Datei")
                return schliesse()
            }
            dokument.wandleUm(in: .utf16LE)
            bericht.append("umgestellt: \(dokument.datei.kodierung.name), geändert \(dokument.isDocumentEdited)")
            dokument.save(to: ziel, ofType: "public.plain-text", for: .saveOperation) { fehler in
                let bytes = (try? Data(contentsOf: ziel)) ?? Data()
                bericht.append(
                    "gesichert: fehler \(fehler?.localizedDescription ?? "keiner"), geändert \(dokument.isDocumentEdited), "
                        + "erste bytes \(bytes.prefix(6).map { String(format: "%02x", $0) }.joined(separator: " "))")
                dokument.oeffneNeu(als: .windows1252)
                let text = String(decoding: dokument.editor?.utf8.prefix(12) ?? Data(), as: UTF8.self)
                bericht.append(
                    "neu geöffnet als \(dokument.datei.kodierung.name), geändert \(dokument.isDocumentEdited), "
                        + "text «\(text.unicodeScalars.map { $0.value < 32 ? "·" : String($0) }.joined())»")
                schliesse()
            }
            return
        default:
            break
        }

        // Tippen, sichern, nachlesen — am letzten Dokument, das eine Datei hat.
        guard let dokument = dokumente.last(where: { $0.fileURL != nil }),
            let ziel = dokument.fileURL, let editor = dokument.editor
        else {
            bericht.append("sichern: kein Dokument mit Datei")
            return schliesse()
        }
        editor.ansicht.insertText("Äöü € getippt\n")
        bericht.append("nach dem Tippen: geändert \(dokument.isDocumentEdited)")
        let erwartet = editor.utf8
        dokument.save(to: ziel, ofType: dokument.fileType ?? "public.plain-text", for: .saveOperation) { fehler in
            if let fehler {
                bericht.append("sichern: FEHLER \(fehler.localizedDescription)")
            } else {
                let aufPlatte = Textdatei(daten: (try? Data(contentsOf: ziel)) ?? Data())
                bericht.append(
                    "nach dem Sichern: geändert \(dokument.isDocumentEdited), "
                        + "datei stimmt \(aufPlatte.utf8 == erwartet), auf der Platte \(aufPlatte.kodierung.name)")
            }
            if let fenster = dokument.windowControllers.first?.window {
                bild(von: fenster, nach: ordner.appendingPathComponent("nach-dem-sichern.png"))
            }
            schliesse()
        }
    }

    /// Suchleiste, Markieren, Ersetzen samt Widerrufen, Smart Highlighting,
    /// Ergebnisliste und Suchen/Ersetzen im Ordner «-KladdeProbeOrdner».
    /// Arbeitet am vordersten Dokument; die Suchoptionen gehen danach zurück.
    private static func sucheProbe(
        dokumente: [Dokument], ordner: URL, bericht: @escaping (String) -> Void, fertig: @escaping () -> Void
    ) {
        let h = Hauptfenster.gemeinsam
        guard let fenster = h.window, let editor = h.editor else {
            bericht("suchen: kein Dokument")
            return fertig()
        }
        let vorher = SuchZustand.gemeinsam.optionen
        func setze(_ text: String, ersetzung: String = "", modus: SuchOptionen.Modus = .normal, ganzesWort: Bool = false) {
            var o = SuchOptionen()
            o.text = text
            o.ersetzung = ersetzung
            o.modus = modus
            o.ganzesWort = ganzesWort
            SuchZustand.gemeinsam.optionen = o
        }
        func zeigeAuswahl() -> String {
            let a = editor.auswahl
            return "\(a.lowerBound)..<\(a.upperBound) «\(editor.text(a) ?? "")»"
        }

        // Schritte nacheinander, mit Pausen zum Zeichnen; ein Schritt mit
        // `weiter` wartet, bis er es selbst aufruft.
        var schritte: [(@escaping () -> Void) -> Void] = []
        func schritt(_ arbeit: @escaping () -> Void) { schritte.append { weiter in arbeit(); weiter() } }
        func warte(_ arbeit: @escaping (@escaping () -> Void) -> Void) { schritte.append(arbeit) }

        schritt {
            editor.waehleAus(0..<0)
            setze("bern")
            SuchenDialog.gemeinsam.zeige(.ersetzen)
            let antwort = Suchaktion.live(in: editor, ab: 0)
            bericht("live «bern»: \(antwort.text), auswahl \(zeigeAuswahl()), hinterlegt \(editor.anzahlMarkierungen(Editor.indikatorSuche))")
        }
        schritt {
            if let w = SuchenDialog.gemeinsam.window { bild(von: w, nach: ordner.appendingPathComponent("dialog-ersetzen.png")) }
            for (r, name) in [(SuchenDialog.Reiter.suchen, "suchen"), (.inDateien, "indateien"), (.markieren, "markieren")] {
                SuchenDialog.gemeinsam.zeige(r)
                if let w = SuchenDialog.gemeinsam.window { bild(von: w, nach: ordner.appendingPathComponent("dialog-\(name).png")) }
            }
            NSApp.appearance = NSAppearance(named: .darkAqua)
            SuchenDialog.gemeinsam.zeige(.ersetzen)
        }
        schritt {
            if let w = SuchenDialog.gemeinsam.window { bild(von: w, nach: ordner.appendingPathComponent("dialog-dunkel.png")) }
            NSApp.appearance = nil
            SuchenDialog.gemeinsam.close()
            fenster.makeKeyAndOrderFront(nil)
        }
        schritt {
            let a = Suchaktion.weiter(in: editor)
            let b = Suchaktion.weiter(in: editor)
            let c = Suchaktion.weiter(in: editor)
            bericht("weiter ×3: \(a.text) | \(b.text) | \(c.text), auswahl \(zeigeAuswahl())")
            let d = Suchaktion.weiter(in: editor, rueckwaerts: true)
            bericht("rückwärts: \(d.text), auswahl \(zeigeAuswahl())")
        }
        schritt {
            setze("bern", ganzesWort: true)
            let antwort = Suchaktion.alleMarkieren(in: editor, nurAuswahl: false)
            bericht("alle markieren (ganzes Wort): \(antwort.text), markiert \(editor.anzahlMarkierungen(Editor.indikatorMarkiert))")
        }
        schritt { bild(von: fenster, nach: ordner.appendingPathComponent("markiert.png")) }
        schritt {
            let vorher = editor.utf8
            setze("(\\w+)stadt", ersetzung: "\\U$1\\E-Stadt", modus: .regulaer)
            let antwort = Suchaktion.alleErsetzen(in: editor, nurAuswahl: false)
            let erste = String(decoding: editor.utf8, as: UTF8.self).split(separator: "\n").first { $0.contains("-Stadt") } ?? "?"
            bericht("regex ersetzen: \(antwort.text), zeile «\(erste)», geändert \(dokumente.first { $0.editor === editor }?.isDocumentEdited ?? false)")
            editor.ansicht.message(UInt32(SCI_UNDO), wParam: 0, lParam: 0)
            bericht("ein Widerrufen: text wie vorher \(editor.utf8 == vorher)")
        }
        schritt {
            setze("Bern", ersetzung: "BERN")
            editor.waehleAus(0..<0)
            _ = Suchaktion.weiter(in: editor)
            let a = Suchaktion.ersetzen(in: editor)
            bericht("ersetzen einzeln: \(a.text), auswahl danach \(zeigeAuswahl())")
            editor.ansicht.message(UInt32(SCI_UNDO), wParam: 0, lParam: 0)
        }
        schritt {
            // Smart Highlighting: ein ganzes Wort auswählen.
            editor.markierungenLoeschenFuerProbe()
            let text = editor.suchtext
            var o = SuchOptionen()
            o.text = "Bern"
            o.grossKlein = true
            o.ganzesWort = true
            if let erster = (try? Suchmuster(o))?.alle(in: text).first { editor.waehleAus(erster.bereich) }
        }
        schritt {
            bericht("smart highlighting: \(editor.anzahlMarkierungen(Editor.indikatorSmart)) weitere Stellen leuchten")
            bild(von: fenster, nach: ordner.appendingPathComponent("smart.png"))
        }
        schritt {
            editor.geheZuZeile(3)
            bericht("gehe zu Zeile 3: jetzt Zeile \(editor.aktuelleZeile)")
            setze("Bern")
            let antwort = Suchergebnisse.gemeinsam.findeAlle(in: Dokumente.inTabfolge())
            bericht("alle finden in offenen: \(antwort.text)")
        }
        schritt {
            bild(von: fenster, nach: ordner.appendingPathComponent("ergebnisse-offen.png"))
        }
        if let pfad = UserDefaults.standard.string(forKey: "KladdeProbeOrdner") {
            warte { weiter in
                setze("Bern")
                SuchenDialog.gemeinsam.zeige(.inDateien, ordner: pfad)
                SuchenDialog.gemeinsam.setze(ordner: pfad, filter: "*.txt !\\ausgelassen")
                SuchenDialog.gemeinsam.starteDateisuche(ersetzen: false) { satz in
                    bericht("ordner finden: \(satz)")
                    weiter()
                }
            }
            schritt {
                bild(von: fenster, nach: ordner.appendingPathComponent("ergebnisse-ordner.png"))
                if let w = SuchenDialog.gemeinsam.window { bild(von: w, nach: ordner.appendingPathComponent("dateisuche.png")) }
            }
            warte { weiter in
                setze("Bern", ersetzung: "Zürich")
                // Wie ein Mensch: Der Dialog nimmt, was in seinen Feldern steht.
                SuchenDialog.gemeinsam.setzeSuchtextFuerProbe("Bern", ersetzung: "Zürich")
                SuchenDialog.gemeinsam.starteDateisuche(ersetzen: true, bestaetigt: true) { satz in
                    bericht("ordner ersetzen: \(satz)")
                    weiter()
                }
            }
        }
        schritt {
            SuchenDialog.gemeinsam.close()
            SuchZustand.gemeinsam.optionen = vorher
        }

        func fuehreAus(_ index: Int) {
            guard index < schritte.count else { return fertig() }
            let arbeit = schritte[index]
            arbeit {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { fuehreAus(index + 1) }
            }
        }
        fuehreAus(0)
    }

    /// Funktionsliste, Vorschläge, Aufrufhilfe und benutzerdefinierte Sprache. Erwartet
    /// als erstes Dokument eine Python-Datei und als zweites eine Datei der Test-UDL.
    private static func etappe6(ordner: URL, bericht: @escaping (String) -> Void, fertig: @escaping () -> Void) {
        let h = Hauptfenster.gemeinsam
        let dokumente = h.tabs
        guard let python = dokumente.first(where: { $0.editor?.sprache.name == "python" }), let e = python.editor,
            let fenster = h.window
        else {
            bericht("etappe6: keine Python-Datei offen")
            return fertig()
        }
        let vorher = Einstellungen.funktionslisteSichtbar
        var schritte: [() -> Void] = []
        schritte.append {
            h.aktiviere(python)
            Einstellungen.funktionslisteSichtbar = true
        }
        schritte.append {}
        schritte.append {}
        schritte.append {
            bericht("funktionsliste: \(Panels.gemeinsam.funktionsliste.namen)")
            bild(von: fenster, nach: ordner.appendingPathComponent("funktionsliste.png"))
        }
        schritte.append {
            e.waehleAus(e.laenge..<e.laenge)
            e.ansicht.insertText("\nx = isinst")
        }
        schritte.append {
            bericht("vorschläge nach «isinst»: offen \(e.vorschlagOffen)")
            bild(von: fenster, nach: ordner.appendingPathComponent("vorschlaege.png"))
            _ = e.ansicht.message(UInt32(SCI_AUTOCCANCEL), wParam: 0, lParam: 0)
            e.ansicht.insertText("\nlen(")
        }
        schritte.append {
            bericht("aufrufhilfe nach «len(»: offen \(e.aufrufhilfeOffen)")
            bild(von: fenster, nach: ordner.appendingPathComponent("aufrufhilfe.png"))
            _ = e.ansicht.message(UInt32(SCI_CALLTIPCANCEL), wParam: 0, lParam: 0)
        }
        schritte.append {
            guard let eigene = dokumente.first(where: { $0.editor?.sprache.istBenutzersprache ?? false }), let ed = eigene.editor else {
                bericht("udl: kein Dokument erkannt; geladen \(Sprachdaten.gemeinsam.benutzersprachen.keys.sorted()), fehler \(Sprachdaten.gemeinsam.benutzerspracheFehler)")
                return
            }
            h.aktiviere(eigene)
            let text = String(decoding: ed.utf8, as: UTF8.self)
            let stelle = text.utf8.count - (text.components(separatedBy: "WENN").last?.utf8.count ?? 0) - 4
            bericht("udl: sprache \(ed.sprache.name), stil von «WENN» \(ed.stil(bei: max(0, stelle))) (Keywords1 = 4)")
        }
        schritte.append {
            bild(von: fenster, nach: ordner.appendingPathComponent("udl.png"))
            Einstellungen.funktionslisteSichtbar = vorher
            for d in dokumente { d.updateChangeCount(.changeCleared) }
        }
        func fuehreAus(_ i: Int) {
            guard i < schritte.count else { return fertig() }
            schritte[i]()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { fuehreAus(i + 1) }
        }
        fuehreAus(0)
    }

    /// Zeilenbefehle, Kommentare, Gross/klein, Lesezeichen, Makro, Spalteneditor,
    /// geteilte Ansicht, Statusleiste und Einstellungen am vordersten Dokument —
    /// alles über die Befehle der Menüs (IDM_…).
    private static func etappe5(ordner: URL, bericht: @escaping (String) -> Void, fertig: @escaping () -> Void) {
        let h = Hauptfenster.gemeinsam
        guard let fenster = h.window, let e = h.editor else {
            bericht("etappe5: kein Dokument")
            return fertig()
        }
        func text() -> String { String(decoding: e.utf8, as: UTF8.self).replacingOccurrences(of: "\n", with: "⏎") }
        func setze(_ t: String) {
            e.ersetze([(0..<e.laenge, t)])
            e.waehleAus(0..<0)
        }
        func befehl(_ id: String) { h.fuehreAus(id) }
        var schritte: [() -> Void] = []

        schritte.append {
            setze("birne\nApfel\n10\napfel\n\n2\nApfel\n")
            befehl("IDM_EDIT_SORTLINES_LEXICOGRAPHIC_ASCENDING")
            bericht("sortiert: \(text())")
            befehl("IDM_EDIT_SORTLINES_INTEGER_ASCENDING")
            bericht("als Zahlen: \(text())")
            befehl("IDM_EDIT_REMOVE_ANY_DUP_LINES")
            bericht("ohne Doppelte: \(text())")
            befehl("IDM_EDIT_REMOVEEMPTYLINES")
            bericht("ohne Leere: \(text())")
            setze("a  \n\tb\t\n")
            befehl("IDM_EDIT_TRIM_BOTH")
            bericht("gekürzt: \(text())")
        }
        schritte.append {
            setze("def f():\n    return 1\n")
            h.aktivesDokument?.gewaehlteSprache = "python"
            e.setzeSprache(Sprachdaten.gemeinsam.sprache("python")!)
            e.waehleAus(0..<e.laenge)
            befehl("IDM_EDIT_BLOCK_COMMENT")
            bericht("kommentiert (python): \(text())")
            befehl("IDM_EDIT_BLOCK_COMMENT")
            bericht("zurück: \(text())")
            setze("grüezi wohl")
            e.waehleAus(0..<e.laenge)
            befehl("IDM_EDIT_PROPERCASE_FORCE")
            bericht("Wörter gross: \(text())")
            e.waehleAus(0..<0)
            befehl("IDM_EDIT_DUP_LINE")
            bericht("dupliziert: \(text())")
        }
        schritte.append {
            setze("eins\nzwei\ndrei\nvier\nfünf")
            e.lesezeichen = [1, 3]
            e.geheZuZeile(1)
            befehl("IDM_SEARCH_NEXT_BOOKMARK")
            let erste = e.aktuelleZeile
            befehl("IDM_SEARCH_NEXT_BOOKMARK")
            bericht("lesezeichen \(e.lesezeichen), springt zu Zeile \(erste) und \(e.aktuelleZeile), text «\(e.lesezeichenText().replacingOccurrences(of: "\n", with: "⏎"))»")
            befehl("IDM_SEARCH_DELETEUNMARKEDLINES")
            bericht("nur Zeilen mit Lesezeichen: \(text())")
        }
        schritte.append {
            // Makro: Zeilenanfang, «- » einsetzen, eine Zeile tiefer; dann bis zum Ende.
            setze("a\nb\nc\nd")
            Makros.gemeinsam.starte(in: e)
            _ = e.ansicht.message(UInt32(SCI_HOME), wParam: 0, lParam: 0)
            e.ansicht.insertText("- ")
            _ = e.ansicht.message(UInt32(SCI_LINEDOWN), wParam: 0, lParam: 0)
            Makros.gemeinsam.beende()
            bericht("makro: \(Makros.gemeinsam.aktuelles.count) Schritte, nach Aufnahme: \(text())")
            let mal = Makros.gemeinsam.spieleBisEnde(Makros.gemeinsam.aktuelles, in: e)
            bericht("bis zum Ende (\(mal)×): \(text())")
            setze("aa\nbb\ncc\nlange letzte Zeile")
            e.geheZuZeile(2)
            let mal2 = Makros.gemeinsam.spieleBisEnde(Makros.gemeinsam.aktuelles, in: e)
            bericht("bis zum Ende ab Zeile 2 (\(mal2)×): \(text())")
        }
        schritte.append {
            setze("x\ny\nz")
            var folge = Zahlenfolge()
            folge.anfang = 8
            folge.fuehrend = .nullen
            e.waehleAus(0..<0)
            let zeilen = e.fuegeInSpalteEin { folge.texte($0) }
            bericht("spalteneditor in \(zeilen) Zeilen: \(text())")
        }
        schritte.append {
            setze((1...40).map { "Zeile \($0) mit etwas Text" }.joined(separator: "\n"))
            e.lesezeichen = [2, 5]
            e.waehleAus(30..<45)
            befehl("IDM_VIEW_CLONE_TO_ANOTHER_VIEW")
        }
        schritte.append {
            bericht("geteilt: \(h.geteilt), statusleiste «\(h.statusleiste.texte.joined(separator: " | "))»")
            bild(von: fenster, nach: ordner.appendingPathComponent("geteilt.png"))
            h.teile(nebeneinander: nil)
            bericht("wieder eine Ansicht: \(h.geteilt)")
        }
        schritte.append { EinstellungsFenster.gemeinsam.zeige() }
        schritte.append {
            if let w = EinstellungsFenster.gemeinsam.window { bild(von: w, nach: ordner.appendingPathComponent("einstellungen.png")) }
            EinstellungsFenster.gemeinsam.close()
            setze("")
            h.aktivesDokument?.updateChangeCount(.changeCleared)
        }
        func fuehreAus(_ i: Int) {
            guard i < schritte.count else { return fertig() }
            schritte[i]()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { fuehreAus(i + 1) }
        }
        fuehreAus(0)
    }

    /// Die Bilder fürs README (scripts/bilder.sh legt sie nach docs/bilder/): das
    /// Fenster hell mit Python und dunkel mit TypeScript, beide mit Seitenleisten,
    /// dazu der Suchen-Dialog, der JSON Viewer und «Optionen». Die Beispiele aus
    /// docs/bilder/beispiele/ kommen beim Start mit. Der kurze Fenstertitel zeigt
    /// nur den Dateinamen, keinen Pfad. Die Einstellungen gehen danach zurück.
    private static func bilder(ordner: URL, bericht: @escaping (String) -> Void, fertig: @escaping () -> Void) {
        let h = Hauptfenster.gemeinsam
        guard let fenster = h.window else { return fertig() }
        let vorher = (Einstellungen.funktionslisteSichtbar, Einstellungen.dokumentenlisteSichtbar,
                      Einstellungen.miniaturansichtSichtbar, Einstellungen.farbschema, Einstellungen.kurzerTitel)
        func vorne(_ endung: String) {
            if let d = h.tabs.first(where: { $0.fileURL?.pathExtension == endung }) { h.aktiviere(d) }
            h.tabsGeaendert()
            h.editor?.ersteZeile = 0
        }
        var schritte: [() -> Void] = []
        schritte.append {
            NSApp.appearance = NSAppearance(named: .aqua)
            Einstellungen.farbschema = "Standard"
            Einstellungen.kurzerTitel = true
            Einstellungen.funktionslisteSichtbar = true
            Einstellungen.dokumentenlisteSichtbar = true
            Einstellungen.miniaturansichtSichtbar = true
            Panels.gemeinsam.anwenden()
            fenster.setContentSize(NSSize(width: 1200, height: 740))
            h.ordneDocks()
            h.rechterDock.waehle(Panels.gemeinsam.funktionslisteLeiste)
            vorne("py")
        }
        schritte.append {}
        schritte.append { bild(von: fenster, nach: ordner.appendingPathComponent("notemac.png")) }
        schritte.append {
            NSApp.appearance = NSAppearance(named: .darkAqua)
            Einstellungen.farbschema = "DarkModeDefault"
            // Für TypeScript findet die Funktionsliste von Notepad++ keine Methoden.
            h.rechterDock.waehle(Panels.gemeinsam.miniaturLeiste)
            vorne("ts")
        }
        schritte.append {}
        schritte.append { bild(von: fenster, nach: ordner.appendingPathComponent("notemac-dunkel.png")) }
        schritte.append {
            NSApp.appearance = NSAppearance(named: .aqua)
            Einstellungen.farbschema = "Standard"
            vorne("py")
            SuchenDialog.gemeinsam.setzeSuchtextFuerProbe("Rechnung", ersetzung: "Beleg")
            SuchenDialog.gemeinsam.zeige(.ersetzen)
        }
        schritte.append {}
        schritte.append {
            if let w = SuchenDialog.gemeinsam.window { bild(von: w, nach: ordner.appendingPathComponent("suchen.png")) }
            SuchenDialog.gemeinsam.close()
            fenster.makeKeyAndOrderFront(nil)
            vorne("json")
            // Der Befehl schaltet um; nur öffnen, wenn der Viewer noch fehlt.
            if !h.rechterDock.enthaelt(Panels.gemeinsam.jsonLeiste) { Plugins.gemeinsam.fuehreAus("json.viewer") }
        }
        schritte.append { h.rechterDock.waehle(Panels.gemeinsam.jsonLeiste) }
        schritte.append { bild(von: fenster, nach: ordner.appendingPathComponent("json-viewer.png")) }
        schritte.append {
            EinstellungsFenster.gemeinsam.zeige()
            EinstellungsFenster.gemeinsam.zeigeSeite(kennung: "Tabbar")
        }
        schritte.append {}
        schritte.append {
            if let w = EinstellungsFenster.gemeinsam.window { bild(von: w, nach: ordner.appendingPathComponent("optionen.png")) }
            EinstellungsFenster.gemeinsam.close()
            bericht("bilder: tabs \(h.tabs.map(\.tabTitel)), titel «\(fenster.title)»")
            NSApp.appearance = nil
            (Einstellungen.funktionslisteSichtbar, Einstellungen.dokumentenlisteSichtbar,
             Einstellungen.miniaturansichtSichtbar, Einstellungen.farbschema, Einstellungen.kurzerTitel) = vorher
            fertig()
        }
        // Mit Pausen, damit Scintilla, Seitenleisten und Dialoge zeichnen.
        for (index, schritt) in schritte.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 * Double(index), execute: schritt)
        }
    }

    /// Bilder der Oberfläche: Fenster hell und dunkel, Seitenleisten, Suchergebnis,
    /// inkrementelle Suche, Menüs als Text (ausgegraute Einträge mit «·»).
    private static func oberflaeche(ordner: URL, bericht: @escaping (String) -> Void, fertig: @escaping () -> Void) {
        let h = Hauptfenster.gemeinsam
        guard let fenster = h.window else { return fertig() }
        fenster.setContentSize(NSSize(width: 1100, height: 720))
        let vorher = (Einstellungen.funktionslisteSichtbar, Einstellungen.dokumentenlisteSichtbar,
                      Einstellungen.miniaturansichtSichtbar, Einstellungen.farbschema)
        var schritte: [() -> Void] = []
        schritte.append {
            var zeilen: [String] = []
            for oben in NSApp.mainMenu?.items ?? [] {
                guard let m = oben.submenu else { continue }
                m.update()
                zeilen.append("[\(oben.title)]")
                func gehe(_ m: NSMenu, _ tiefe: Int) {
                    for i in m.items {
                        if i.isSeparatorItem { continue }
                        let k = i.keyEquivalent.isEmpty ? "" : "  \(i.keyEquivalentModifierMask.contains(.control) ? "⌃" : "")\(i.keyEquivalentModifierMask.contains(.option) ? "⌥" : "")\(i.keyEquivalentModifierMask.contains(.shift) ? "⇧" : "")\(i.keyEquivalentModifierMask.contains(.command) ? "⌘" : "")\(i.keyEquivalent.uppercased())"
                        let an = h.validateMenuItem(i) || i.submenu != nil || i.target !== h
                        zeilen.append(String(repeating: "  ", count: tiefe) + (an ? "" : "· ") + i.title + k)
                        if let s = i.submenu { s.update(); gehe(s, tiefe + 1) }
                    }
                }
                gehe(m, 1)
            }
            try? zeilen.joined(separator: "\n").write(to: ordner.appendingPathComponent("menues.txt"), atomically: true, encoding: .utf8)
            bericht("menüs: \(zeilen.count) Zeilen, ausgegraut \(zeilen.filter { $0.contains("· ") }.count)")
        }
        schritte.append { bild(von: fenster, nach: ordner.appendingPathComponent("ui-hell.png")) }
        schritte.append {
            // Hinweis über «Suchen» und die Aufklappmenüs als Text.
            func knoepfe(_ v: NSView) -> [Werkzeugleiste.Knopf] { v.subviews.flatMap { ($0 as? Werkzeugleiste.Knopf).map { [$0] } ?? knoepfe($0) } }
            if let k = knoepfe(h.werkzeugleiste).first(where: { $0.befehl == "IDM_SEARCH_FIND" }) {
                Hinweis.gemeinsam.plane(fuer: k, titel: Oberflaeche.gemeinsam.titel(k.befehl).replacingOccurrences(of: " …", with: ""),
                                        kuerzel: Beschreibung.kuerzel(k.befehl), text: Beschreibung.text(k.befehl))
            }
            for k in knoepfe(h.werkzeugleiste) {
                guard let m = k.aufklappen?() else { continue }
                bericht("▾ \(k.befehl): " + m.items.map { $0.isSeparatorItem ? "—" : $0.title + (h.validateMenuItem($0) || $0.target !== h ? "" : " (aus)") }.joined(separator: " | "))
            }
            let ohne = knoepfe(h.werkzeugleiste).filter { Beschreibung.text($0.befehl) == nil }.map(\.befehl)
            bericht("knöpfe ohne beschreibung: \(ohne)")
        }
        schritte.append {}
        schritte.append {
            bild(von: Hinweis.gemeinsam.fensterFuerProbe, nach: ordner.appendingPathComponent("ui-hinweis.png"))
            bericht("hinweis sichtbar: \(Hinweis.gemeinsam.fensterFuerProbe.isVisible)")
            Hinweis.gemeinsam.verberge()
        }
        schritte.append {
            Einstellungen.funktionslisteSichtbar = true
            Einstellungen.dokumentenlisteSichtbar = true
            Einstellungen.miniaturansichtSichtbar = true
            Panels.gemeinsam.anwenden()
            h.ordneDocks()
        }
        schritte.append {}
        schritte.append { bild(von: fenster, nach: ordner.appendingPathComponent("ui-seitenleisten.png")) }
        schritte.append {
            var o = SuchOptionen()
            o.text = "e"
            SuchZustand.gemeinsam.optionen = o
            _ = Suchergebnisse.gemeinsam.findeAlle(in: h.tabs)
            h.fuehreAus("IDM_SEARCH_FINDINCREMENT")
        }
        schritte.append {}
        schritte.append { bild(von: fenster, nach: ordner.appendingPathComponent("ui-suchergebnis.png")) }
        schritte.append {
            Einstellungen.farbschema = "DarkModeDefault"
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        schritte.append {}
        schritte.append { bild(von: fenster, nach: ordner.appendingPathComponent("ui-dunkel.png")) }
        schritte.append {
            NSApp.appearance = nil
            (Einstellungen.funktionslisteSichtbar, Einstellungen.dokumentenlisteSichtbar,
             Einstellungen.miniaturansichtSichtbar, Einstellungen.farbschema) = vorher
            Suchergebnisse.gemeinsam.verberge()
            Panels.gemeinsam.anwenden()
        }
        func fuehreAus(_ i: Int) {
            guard i < schritte.count else { return fertig() }
            schritte[i]()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { fuehreAus(i + 1) }
        }
        fuehreAus(0)
    }

    /// Bilder für eine Durchsicht: Hauptfenster in drei Breiten, alle Leisten,
    /// hell und dunkel, und jeder Dialog, auch die als Blatt.
    private static func review(ordner: URL, bericht: @escaping (String) -> Void, fertig: @escaping () -> Void) {
        let h = Hauptfenster.gemeinsam
        guard let fenster = h.window else { return fertig() }
        var schritte: [() -> Void] = []
        let vorher = (Einstellungen.funktionslisteSichtbar, Einstellungen.dokumentenlisteSichtbar, Einstellungen.miniaturansichtSichtbar)
        for (breite, hoehe) in [(1280.0, 800.0), (900.0, 640.0), (620.0, 520.0), (460.0, 420.0)] {
            schritte.append { fenster.setContentSize(NSSize(width: breite, height: hoehe)) }
            schritte.append { bild(von: fenster, nach: ordner.appendingPathComponent("w\(Int(breite)).png")) }
        }
        schritte.append {
            fenster.setContentSize(NSSize(width: 1280, height: 800))
            Einstellungen.funktionslisteSichtbar = true
            Einstellungen.dokumentenlisteSichtbar = true
            Einstellungen.miniaturansichtSichtbar = true
            Einstellungen.arbeitsbereichSichtbar = true
            Einstellungen.jsonViewerSichtbar = true
        }
        schritte.append { bild(von: fenster, nach: ordner.appendingPathComponent("leisten.png")) }
        schritte.append { fenster.setContentSize(NSSize(width: 820, height: 600)) }
        schritte.append { bild(von: fenster, nach: ordner.appendingPathComponent("leisten-schmal.png")) }
        schritte.append {
            fenster.setContentSize(NSSize(width: 1280, height: 800))
            Einstellungen.arbeitsbereichSichtbar = false
            Einstellungen.jsonViewerSichtbar = false
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        schritte.append {}
        schritte.append { bild(von: fenster, nach: ordner.appendingPathComponent("dunkel.png")) }
        schritte.append {
            NSApp.appearance = nil
            (Einstellungen.funktionslisteSichtbar, Einstellungen.dokumentenlisteSichtbar, Einstellungen.miniaturansichtSichtbar) = vorher
        }
        // Dialoge, die als Blatt am Fenster hängen.
        for (id, name) in [("IDM_SEARCH_GOTOLINE", "gehezu"), ("IDM_EDIT_COLUMNMODE", "spalten"), ("IDM_EXECUTE", "ausfuehren"),
                           ("IDM_MACRO_RUNMULTIMACRODLG", "makro"), ("IDM_TOOL_MD5_GENERATE", "md5"), ("IDM_FILE_RENAME", "umbenennen")] {
            schritte.append { h.fuehreAus(id) }
            schritte.append {
                if let blatt = fenster.attachedSheet {
                    bild(von: blatt, nach: ordner.appendingPathComponent("blatt-\(name).png"))
                    fenster.endSheet(blatt)
                } else if let w = fenster.childWindows?.first(where: { $0.isVisible && $0 !== Hinweis.gemeinsam.fensterFuerProbe }) {
                    bild(von: w, nach: ordner.appendingPathComponent("fenster-\(name).png"))
                    w.close()
                } else {
                    bericht("\(id): kein Dialog")
                }
            }
        }
        schritte.append { EinstellungsFenster.gemeinsam.zeige() }
        for seite in [0, 2, 3, 6] {
            schritte.append { EinstellungsFenster.gemeinsam.zeigeSeite(seite) }
            schritte.append {
                if let w = EinstellungsFenster.gemeinsam.window { bild(von: w, nach: ordner.appendingPathComponent("optionen-\(seite).png")) }
            }
        }
        schritte.append {
            EinstellungsFenster.gemeinsam.zeigeSeite(0)
            EinstellungsFenster.gemeinsam.close()
        }
        func fuehreAus(_ i: Int) {
            guard i < schritte.count else { return fertig() }
            schritte[i]()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { fuehreAus(i + 1) }
        }
        fuehreAus(0)
    }

    // MARK: Bedienung mit echten Ereignissen

    private static func ereignis(_ typ: NSEvent.EventType, _ v: NSView, _ p: NSPoint, klicks: Int = 1) -> NSEvent {
        NSEvent.mouseEvent(with: typ, location: v.convert(p, to: nil), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                           windowNumber: v.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: klicks, pressure: 1)!
    }

    /// Ein Klick wie mit der Maus: Die Ansicht, die an der Stelle zuoberst liegt, bekommt ihn.
    @discardableResult
    private static func klick(_ v: NSView, _ p: NSPoint, klicks: Int = 1) -> NSView? {
        guard let w = v.window, let wurzel = w.contentView?.superview ?? w.contentView else { return nil }
        guard let ziel = wurzel.hitTest(v.convert(p, to: nil)) else { return nil }
        let runter = ereignis(.leftMouseDown, v, p, klicks: klicks)
        let hoch = ereignis(.leftMouseUp, v, p, klicks: klicks)
        if let knopf = ziel as? NSButton {
            // NSButton verfolgt die Maus selbst und wartet auf ein echtes Loslassen;
            // getroffen ist er (Treffertest oben), also wie ein Klick auslösen.
            knopf.performClick(nil)
        } else {
            ziel.mouseDown(with: runter)
            ziel.mouseUp(with: hoch)
        }
        return ziel
    }

    private static func mitte(_ v: NSView) -> NSPoint { NSPoint(x: v.bounds.midX, y: v.bounds.midY) }

    private static func taste(_ zeichen: String, _ mod: NSEvent.ModifierFlags, _ code: UInt16, in w: NSWindow?) -> Bool {
        guard let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: mod, timestamp: ProcessInfo.processInfo.systemUptime,
                                       windowNumber: w?.windowNumber ?? 0, context: nil, characters: zeichen,
                                       charactersIgnoringModifiers: zeichen, isARepeat: false, keyCode: code) else { return false }
        return NSApp.mainMenu?.performKeyEquivalent(with: e) ?? false
    }

    private static func fensterTaste(_ zeichen: String, _ code: UInt16, in w: NSWindow) -> Bool {
        guard let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                       windowNumber: w.windowNumber, context: nil, characters: zeichen,
                                       charactersIgnoringModifiers: zeichen, isARepeat: false, keyCode: code) else { return false }
        return w.performKeyEquivalent(with: e)
    }

    /// Prüft die Bedienung wie ein Mensch: Tabs schliessen, anheften, verschieben,
    /// Optionen der Tableiste, Kürzel, Symbolleiste, Dialoge, Optionen, Rückfrage.
    /// Erwartet drei Dateien. Läuft in einer Kopie mit eigener Kennung, damit die
    /// Einstellungen des Nutzers unberührt bleiben.
    private static func bedienung(ordner: URL, bericht: @escaping (String) -> Void, fertig: @escaping () -> Void) {
        let h = Hauptfenster.gemeinsam
        guard let fenster = h.window else { return fertig() }
        let tl = h.tableiste
        var fehlerzahl = 0
        let fortschritt = ordner.appendingPathComponent("fortschritt.txt")
        try? Data().write(to: fortschritt)
        func notiere(_ zeile: String) {
            if let h = try? FileHandle(forWritingTo: fortschritt) { h.seekToEndOfFile(); h.write(Data((zeile + "\n").utf8)); try? h.close() }
        }
        let bericht: (String) -> Void = { zeile in bericht(zeile); notiere(zeile) }
        func pruefe(_ ok: Bool, _ text: String) {
            bericht((ok ? "✓ " : "✗ ") + text)
            if !ok { fehlerzahl += 1 }
        }
        func namen() -> String { h.tabs.map(\.tabTitel).joined(separator: ", ") }
        func bildTabs(_ name: String) {
            bild(von: fenster, nach: ordner.appendingPathComponent(name))
        }
        var schritte: [() -> Void] = []
        func s(_ f: @escaping () -> Void) { schritte.append(f) }

        s {
            fenster.setContentSize(NSSize(width: 1000, height: 620))
            bericht("start: \(h.tabs.count) tabs [\(namen())], aktiv \(h.aktivesDokument?.tabTitel ?? "-")")
            pruefe(Symbole.tab("closeTabButton", dunkel: false) != nil, "helles Schliessen-Kreuz lesbar (11×11 PNG in ICO)")
            pruefe(Symbole.tab("closeTabButton", dunkel: false)?.size == NSSize(width: 11, height: 11), "Kreuz in natürlicher Grösse 11 pt")
        }
        s { bildTabs("tabs-start.png") }
        // Überfahren eines inaktiven Tabs zeigt Kreuz und Pin; Klick aufs Kreuz schliesst genau diesen Tab.
        s {
            let r = tl.rechteckFuerProbe(0)
            tl.mouseMoved(with: ereignis(.mouseMoved, tl, NSPoint(x: r.midX, y: r.midY)))
        }
        s { bildTabs("tabs-hover-inaktiv.png") }
        s {
            let z = tl.schliessRechteckFuerProbe(0)
            tl.mouseMoved(with: ereignis(.mouseMoved, tl, NSPoint(x: z.midX, y: z.midY)))
        }
        s { bildTabs("tabs-hover-kreuz.png") }
        s {
            let vorher = h.tabs.count, erster = h.tabs.first?.tabTitel ?? ""
            let z = tl.schliessRechteckFuerProbe(0)
            let ziel = klick(tl, NSPoint(x: z.midX, y: z.midY))
            pruefe(ziel === tl, "Klick aufs Kreuz trifft die Tableiste (nichts liegt darüber)")
            pruefe(h.tabs.count == vorher - 1 && !h.tabs.contains { $0.tabTitel == erster }, "Kreuz schliesst inaktiven Tab «\(erster)» → [\(namen())]")
        }
        s {
            let vorher = h.tabs.count, aktiv = h.aktivesDokument?.tabTitel ?? ""
            guard let i = tl.aktiverIndexFuerProbe else { return pruefe(false, "kein aktiver Tab") }
            let z = tl.schliessRechteckFuerProbe(i)
            klick(tl, NSPoint(x: z.midX, y: z.midY))
            pruefe(h.tabs.count == vorher - 1, "Kreuz schliesst aktiven Tab «\(aktiv)» → [\(namen())]")
        }
        // Kürzel: Neu, Schliessen.
        s {
            let vorher = h.tabs.count
            pruefe(taste("n", .command, 45, in: fenster), "⌘N als Kürzel erkannt")
            pruefe(h.tabs.count == vorher + 1, "⌘N legt ein neues Dokument an → [\(namen())]")
        }
        s {
            let vorher = h.tabs.count
            pruefe(taste("w", .command, 13, in: fenster), "⌘W als Kürzel erkannt")
            pruefe(h.tabs.count == vorher - 1, "⌘W schliesst den aktiven Tab → [\(namen())]")
        }
        // Doppelklick auf freie Fläche: neues Dokument.
        s {
            let vorher = h.tabs.count
            let r = tl.rechteckFuerProbe(h.tabs.count - 1)
            klick(tl, NSPoint(x: min(tl.bounds.width - 60, r.maxX + 40), y: r.midY), klicks: 2)
            pruefe(h.tabs.count == vorher + 1, "Doppelklick auf freie Fläche legt «neu» an → [\(namen())]")
        }
        s {
            NSDocumentController.shared.newDocument(nil)
            bericht("drei Tabs: [\(namen())]")
        }
        // Mittlere Maustaste.
        s {
            let vorher = h.tabs.count
            let r = tl.rechteckFuerProbe(0)
            // Über Core Graphics, denn nur so trägt das Ereignis die mittlere Taste.
            let bildschirm = fenster.convertPoint(toScreen: tl.convert(NSPoint(x: r.midX, y: r.midY), to: nil))
            let hoehe = NSScreen.screens.first?.frame.height ?? 0
            let cg = CGEvent(mouseEventSource: nil, mouseType: .otherMouseUp,
                             mouseCursorPosition: CGPoint(x: bildschirm.x, y: hoehe - bildschirm.y), mouseButton: .center)!
            let e = NSEvent(cgEvent: cg)!
            if e.buttonNumber == 2 {
                tl.otherMouseUp(with: e)
                pruefe(h.tabs.count == vorher - 1, "Mittlere Maustaste schliesst → [\(namen())]")
            } else {
                bericht("· mittlere Maustaste hier nicht nachstellbar (buttonNumber \(e.buttonNumber))")
            }
            NSDocumentController.shared.newDocument(nil)
            NSDocumentController.shared.newDocument(nil)
        }
        // Anheften per Pin des aktiven Tabs.
        s {
            guard let i = tl.aktiverIndexFuerProbe else { return }
            let d = h.tabs[i]
            let p = tl.pinRechteckFuerProbe(i)
            klick(tl, NSPoint(x: p.midX, y: p.midY))
            pruefe(d.angeheftet, "Pin heftet «\(d.tabTitel)» an; steht jetzt an Stelle \((h.tabs.firstIndex { $0 === d } ?? -1) + 1)")
            pruefe(h.tabs.first === d, "Angehefteter Tab rückt nach vorn")
        }
        s { bildTabs("tabs-angeheftet.png") }
        s {
            let d = h.tabs[0]
            let p = tl.pinRechteckFuerProbe(0)
            tl.mouseMoved(with: ereignis(.mouseMoved, tl, NSPoint(x: p.midX, y: p.midY)))
            klick(tl, NSPoint(x: p.midX, y: p.midY))
            pruefe(!d.angeheftet, "Zweiter Klick auf den Pin löst ihn")
        }
        // Ziehen zum Umsortieren, und mit «Tabs nicht mit der Maus verschiebbar».
        s {
            let letzter = h.tabs[h.tabs.count - 1]
            let von = tl.rechteckFuerProbe(h.tabs.count - 1), nach = tl.rechteckFuerProbe(0)
            tl.mouseDown(with: ereignis(.leftMouseDown, tl, NSPoint(x: von.midX, y: von.midY)))
            tl.mouseDragged(with: ereignis(.leftMouseDragged, tl, NSPoint(x: (von.midX + nach.midX) / 2, y: von.midY)))
            tl.mouseDragged(with: ereignis(.leftMouseDragged, tl, NSPoint(x: nach.midX, y: nach.midY)))
            tl.mouseUp(with: ereignis(.leftMouseUp, tl, NSPoint(x: nach.midX, y: nach.midY)))
            pruefe(h.tabs.first === letzter, "Ziehen schiebt den letzten Tab nach vorn → [\(namen())]")
            Einstellungen.tabsSperren = true
            let zweiter = h.tabs[1]
            let a = tl.rechteckFuerProbe(1), b = tl.rechteckFuerProbe(0)
            tl.mouseDown(with: ereignis(.leftMouseDown, tl, NSPoint(x: a.midX, y: a.midY)))
            tl.mouseDragged(with: ereignis(.leftMouseDragged, tl, NSPoint(x: b.midX, y: b.midY)))
            tl.mouseUp(with: ereignis(.leftMouseUp, tl, NSPoint(x: b.midX, y: b.midY)))
            pruefe(h.tabs[1] === zweiter, "Gesperrt: Ziehen verschiebt nichts")
            Einstellungen.tabsSperren = false
        }
        // Doppelklick auf einen Tab: nur mit Option schliesst er.
        s {
            let vorher = h.tabs.count
            let r = tl.rechteckFuerProbe(0)
            klick(tl, NSPoint(x: r.minX + 30, y: r.midY), klicks: 2)
            pruefe(h.tabs.count == vorher, "Ohne Option schliesst Doppelklick keinen Tab")
            Einstellungen.tabDoppelklickSchliesst = true
            klick(tl, NSPoint(x: r.minX + 30, y: r.midY), klicks: 2)
            pruefe(h.tabs.count == vorher - 1, "Mit «Tabs per Doppelklick schließen» schliesst er → [\(namen())]")
            Einstellungen.tabDoppelklickSchliesst = false
            NSDocumentController.shared.newDocument(nil)
        }
        // Ohne Schliessen-Kreuz wählt ein Klick an seiner Stelle nur den Tab.
        s {
            // Ohne Kreuz rückt der Pin an dessen Stelle (wie in Notepad++); ohne beide wählt der Klick nur.
            Einstellungen.tabSchliessen = false
            Einstellungen.tabPin = false
            let i = 0
            let vorher = h.tabs.count
            let r = tl.rechteckFuerProbe(i)
            klick(tl, NSPoint(x: r.maxX - 8, y: r.midY))
            pruefe(h.tabs.count == vorher, "Ohne Kreuz schliesst ein Klick am rechten Rand nichts")
            pruefe(tl.aktiverIndexFuerProbe == i, "… sondern wählt den Tab")
        }
        s { bildTabs("tabs-ohne-kreuz.png") }
        s {
            Einstellungen.tabPin = true
            Einstellungen.tabSchliessen = true
            Einstellungen.tabKnoepfeInaktiv = true
        }
        s { bildTabs("tabs-knoepfe-inaktiv.png") }
        s {
            Einstellungen.tabKnoepfeInaktiv = false
            Einstellungen.tabNameMax = 4
        }
        s {
            bildTabs("tabs-name-kurz.png")
            pruefe(tl.rechteckFuerProbe(0).width < 110, "Max. Länge 4 kürzt die Tabs (Breite \(Int(tl.rechteckFuerProbe(0).width)))")
            Einstellungen.tabNameMax = 0
            Einstellungen.tabsVerkleinert = false
        }
        s {
            pruefe(tl.frame.height == 29, "«Verkleinern» aus: Leiste 29 statt 26 pt hoch (jetzt \(Int(tl.frame.height)))")
            bildTabs("tabs-gross.png")
            Einstellungen.tabsVerkleinert = true
            Einstellungen.tabsAusblenden = true
        }
        s {
            pruefe(tl.isHidden, "«Ausblenden» blendet die Tableiste aus")
            Einstellungen.tabsAusblenden = false
            Einstellungen.tabBalken = false
            Einstellungen.tabInaktivFarbe = false
        }
        s {
            bildTabs("tabs-ohne-balken-und-farbe.png")
            Einstellungen.tabBalken = true
            Einstellungen.tabInaktivFarbe = true
        }
        // Kontextmenü eines Tabs.
        s {
            let r = tl.rechteckFuerProbe(0)
            let m = tl.menu(for: ereignis(.rightMouseDown, tl, NSPoint(x: r.midX, y: r.midY)))
            let titel = m?.items.map(\.title) ?? []
            pruefe(titel.contains { $0.hasPrefix("Schließen") }, "Kontextmenü des Tabs hat «Schließen» (\(titel.count) Einträge)")
        }
        // Symbolleiste: Neu und Schliessen per Klick auf die Knöpfe.
        s {
            let knoepfe = h.werkzeugleiste.subviews.flatMap { $0.subviews }.compactMap { $0 as? Werkzeugleiste.Knopf }
            guard let neu = knoepfe.first(where: { $0.befehl == "IDM_FILE_NEW" }),
                  let zu = knoepfe.first(where: { $0.befehl == "IDM_FILE_CLOSE" }) else { return pruefe(false, "Knöpfe nicht gefunden") }
            let vorher = h.tabs.count
            klick(neu, mitte(neu))
            pruefe(h.tabs.count == vorher + 1, "Knopf «Neu» → [\(namen())]")
            klick(zu, NSPoint(x: 8, y: zu.bounds.midY))
            pruefe(h.tabs.count == vorher, "Knopf «Schließen» → [\(namen())]")
        }
        // Ungesicherte Änderung: Das Kreuz fragt wie Notepad++ («Speichern»). Abbruch lässt den
        // Tab offen, Nein schliesst ohne Sichern, Ja sichert in die Datei. Der Dialog ist modal;
        // die Antwort gibt ein vorher geplanter Schritt.
        func antworte(_ id: String, _ nach: Double = 0.5, bild name: String? = nil, pruefung: ((WinDialog) -> Void)? = nil) {
            // Ein Timer, der auch im modalen Modus des Dialogs läuft (DispatchQueue.main tut es nicht).
            let t = Timer(timeInterval: nach, repeats: false) { _ in
                guard let d = WinDialog.oberster else { return pruefe(false, "Rückfrage erscheint nicht") }
                if let name { bild(von: d.fenster, nach: ordner.appendingPathComponent(name)) }
                pruefung?(d)
                if let k = d.elemente[id] { klick(k, mitte(k)) }
            }
            RunLoop.main.add(t, forMode: .common)
            RunLoop.main.add(t, forMode: .modalPanel)
        }
        s {
            guard let e = h.editor, let i = tl.aktiverIndexFuerProbe else { return }
            e.ansicht.insertText("geändert")
            let vorher = h.tabs.count
            let z = tl.schliessRechteckFuerProbe(i)
            antworte("IDCANCEL", bild: "rueckfrage.png") { d in
                pruefe(d.text("IDC_DOSAVEORNOTTEXT").contains("speichern?"), "Rückfrage «\(d.text("IDC_DOSAVEORNOTTEXT"))»")
                pruefe(d.elemente["IDRETRY"]?.isHidden == true, "Bei einer Datei kein «Ja für alle»")
            }
            klick(tl, NSPoint(x: z.midX, y: z.midY))
            pruefe(h.tabs.count == vorher && h.aktivesDokument?.isDocumentEdited == true, "«Abbruch» lässt den geänderten Tab offen")
        }
        s {
            guard let i = tl.aktiverIndexFuerProbe else { return }
            let vorher = h.tabs.count, name = h.aktivesDokument?.tabTitel ?? ""
            let z = tl.schliessRechteckFuerProbe(i)
            antworte("IDNO")
            klick(tl, NSPoint(x: z.midX, y: z.midY))
            pruefe(h.tabs.count == vorher - 1 && !h.tabs.contains { $0.tabTitel == name }, "«Nein» schliesst «\(name)» ohne Sichern")
        }
        s {
            // Eine Datei mit Inhalt auf der Platte: «Ja» sichert hinein.
            let datei = ordner.appendingPathComponent("d/alpha.txt")
            if !h.tabs.contains(where: { $0.fileURL == datei }) {
                NSDocumentController.shared.openDocument(withContentsOf: datei, display: true) { _, _, _ in }
            }
        }
        s {
            guard let d = h.tabs.first(where: { $0.fileURL != nil }), let url = d.fileURL else { return pruefe(false, "keine Datei offen") }
            h.aktiviere(d)
            d.editor?.ansicht.insertText("Neu: ")
            let i = tl.aktiverIndexFuerProbe ?? 0
            let z = tl.schliessRechteckFuerProbe(i)
            antworte("IDYES")
            klick(tl, NSPoint(x: z.midX, y: z.midY))
            let inhalt = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            pruefe(inhalt.hasPrefix("Neu: "), "«Ja» sichert «\(url.lastPathComponent)» und schliesst (Datei beginnt mit «\(inhalt.prefix(12))»)")
            pruefe(!h.tabs.contains { $0 === d }, "… der Tab ist zu")
        }
        s {
            // Zwei geänderte: «Ja für alle» und «Nein für alle» erscheinen; «Nein für alle» schliesst beide.
            NSDocumentController.shared.newDocument(nil)
            h.editor?.ansicht.insertText("a")
            NSDocumentController.shared.newDocument(nil)
            h.editor?.ansicht.insertText("b")
            let geaenderte = h.tabs.filter(\.isDocumentEdited)
            antworte("IDIGNORE", bild: "rueckfrage-mehrere.png") { d in
                pruefe(d.elemente["IDRETRY"]?.isHidden == false && d.elemente["IDIGNORE"]?.isHidden == false,
                       "Bei mehreren: «Ja für alle» und «Nein für alle»")
            }
            h.schliesse(geaenderte)
            pruefe(!h.tabs.contains { $0.isDocumentEdited }, "«Nein für alle» schliesst alle geänderten → [\(namen())]")
        }
        // Suchen: ⌘F öffnet den Dialog, ↩ sucht, Esc schliesst.
        s {
            h.editor?.ersetze([(0..<(h.editor?.laenge ?? 0), "eins\nzwei\nzwei\n")])
            h.editor?.waehleAus(0..<0)
            pruefe(taste("f", .command, 3, in: fenster), "⌘F als Kürzel erkannt")
            pruefe(SuchenDialog.gemeinsam.window?.isVisible == true, "⌘F zeigt den Suchen-Dialog")
        }
        s {
            guard let w = SuchenDialog.gemeinsam.window else { return }
            SuchenDialog.gemeinsam.setzeSuchtextFuerProbe("zwei")
            pruefe(fensterTaste("\r", 36, in: w), "↩ im Suchen-Dialog wird angenommen")
            pruefe(h.editor?.aktuelleZeile == 2, "↩ findet «zwei» in Zeile 2 (Zeile \(h.editor?.aktuelleZeile ?? 0))")
            pruefe(fensterTaste("\u{1b}", 53, in: w), "Esc wird angenommen")
            pruefe(w.isVisible == false, "Esc schliesst den Suchen-Dialog")
        }
        // Gehe zu: ⌘G, Zahl tippen, ↩.
        s {
            pruefe(taste("g", .command, 5, in: fenster), "⌘G als Kürzel erkannt")
            guard let d = WinDialog.oberster else { return pruefe(false, "Gehe zu erscheint nicht") }
            d.eingabe("ID_GOLINE_EDIT")?.textAnsichtOderFeldFuerProbe?.insertText("3")
            pruefe(d.text("ID_GOLINE_EDIT") == "3", "Ziel «3» getippt")
            pruefe(fensterTaste("\r", 36, in: d.fenster), "↩ in Gehe zu wird angenommen")
            pruefe(h.editor?.aktuelleZeile == 3, "Gehe zu springt in Zeile 3 (Zeile \(h.editor?.aktuelleZeile ?? 0))")
            pruefe(WinDialog.oberster == nil, "Gehe zu schliesst sich danach")
        }
        // Optionen: ⌘, öffnet, Klicks auf Seiten und Kästchen wirken sofort.
        s {
            pruefe(taste(",", .command, 43, in: fenster), "⌘, als Kürzel erkannt")
            pruefe(EinstellungsFenster.gemeinsam.window?.isVisible == true, "⌘, zeigt «Optionen»")
            EinstellungsFenster.gemeinsam.zeigeSeite(kennung: "Tabbar")
        }
        s {
            guard let w = EinstellungsFenster.gemeinsam.window, let f = EinstellungsFenster.gemeinsam.formular("Tabbar"),
                  let k = f.elemente["IDC_CHECK_ENABLETABCLOSE"] else { return pruefe(false, "Seite Dateireiter fehlt") }
            bild(von: w, nach: ordner.appendingPathComponent("optionen-tabbar.png"))
            klick(k, NSPoint(x: 6, y: k.bounds.midY))
            pruefe(!Einstellungen.tabSchliessen, "Klick auf «Schließen-Kreuz anzeigen» schaltet es aus")
            klick(k, NSPoint(x: 6, y: k.bounds.midY))
            pruefe(Einstellungen.tabSchliessen, "… und wieder ein")
            if let v = f.elemente["IDC_CHECK_TAB_VERTICAL"] as? NSControl { pruefe(!v.isEnabled, "«Vertikal» (nicht umgesetzt) ist ausgegraut") }
            if let p = f.elemente["IDC_CHECK_ENABLETABPIN"], let nur = f.elemente["IDC_CHECK_SHOWONLYPINNEDBUTTON"] as? NSControl {
                klick(p, NSPoint(x: 6, y: p.bounds.midY))
                pruefe(!nur.isEnabled, "Ohne Pin-Funktion ist «Nur angeheftete Pins anzeigen» ausgegraut")
                klick(p, NSPoint(x: 6, y: p.bounds.midY))
                pruefe(nur.isEnabled, "… und mit ihr wieder frei")
            }
            if let e = f.elemente["IDC_EDIT_TABCOMPACTLABELLEN"] as? WinEingabe, let t = e.textAnsichtOderFeldFuerProbe {
                t.selectAll(nil)
                t.insertText("6")
                pruefe(Einstellungen.tabNameMax == 6, "Max. Länge per Tippen: \(Einstellungen.tabNameMax)")
                t.selectAll(nil)
                t.insertText("0")
                _ = w
            }
        }
        s {
            // Seitenwechsel per Klick in die Liste links.
            guard let w = EinstellungsFenster.gemeinsam.window,
                  let liste = w.contentView.flatMap({ alleAnsichten($0) })?.compactMap({ $0 as? WinListe }).first else { return }
            klick(liste, NSPoint(x: 20, y: 2 + 18 * 0 + 9))
            let f = EinstellungsFenster.gemeinsam.formular("Global")
            pruefe(f?.elemente["IDC_CHECK_HIDESTATUSBAR"]?.isHiddenOrHasHiddenAncestor == false, "Klick auf «Allgemein» zeigt die Seite")
            if let k = f?.elemente["IDC_CHECK_HIDESTATUSBAR"] {
                klick(k, NSPoint(x: 6, y: k.bounds.midY))
                pruefe(h.statusleiste.isHidden, "«Statusleiste ausblenden» wirkt sofort")
                klick(k, NSPoint(x: 6, y: k.bounds.midY))
                pruefe(!h.statusleiste.isHidden, "… und zurück")
            }
        }
        s {
            let seiten = EinstellungsFenster.gemeinsam.seitenKennungen
            bericht("optionen-seiten: \(seiten.count) [\(seiten.joined(separator: ", "))]")
            EinstellungsFenster.gemeinsam.zeigeSeite(kennung: "Toolbar")
        }
        s {
            guard let f = EinstellungsFenster.gemeinsam.formular("Toolbar"), let gross = f.elemente["IDC_RADIO_BIGICON"] else { return }
            klick(gross, NSPoint(x: 6, y: gross.bounds.midY))
            pruefe(Einstellungen.symbolsatz == "fluentGross", "«Fluent UI: groß» gewählt (\(Einstellungen.symbolsatz))")
        }
        s {
            pruefe(h.werkzeugleiste.frame.height == 44, "Grosse Symbole: Leiste 44 pt hoch (jetzt \(Int(h.werkzeugleiste.frame.height)))")
            bildTabs("symbolleiste-gross.png")
            if let f = EinstellungsFenster.gemeinsam.formular("Toolbar"), let std = f.elemente["IDC_RADIO_STANDARD"] {
                klick(std, NSPoint(x: 6, y: std.bounds.midY))
            }
            pruefe(Einstellungen.symbolsatz == "standard", "Zurück auf «Standard-Symbole: klein»")
        }
        for kennung in ["Global", "Toolbar", "Scintillas", "Scintillas2", "DarkMode", "MarginsBorderEdge", "NewDoc", "Indentation",
                        "Highlighting", "Searching", "Backup", "AutoCompletion", "MISC"] {
            s { EinstellungsFenster.gemeinsam.zeigeSeite(kennung: kennung) }
            s {
                if let w = EinstellungsFenster.gemeinsam.window { bild(von: w, nach: ordner.appendingPathComponent("optionen-\(kennung).png")) }
            }
        }
        s {
            if let w = EinstellungsFenster.gemeinsam.window { _ = fensterTaste("\u{1b}", 53, in: w) }
            pruefe(EinstellungsFenster.gemeinsam.window?.isVisible == false, "Esc schliesst «Optionen»")
        }
        // Seitenleisten: Reiter unten wechseln, ✕ schliesst.
        var geschlossen: Seitenleiste?
        s {
            Einstellungen.funktionslisteSichtbar = true
            Einstellungen.miniaturansichtSichtbar = true
        }
        s {
            let dock = h.rechterDock
            pruefe(dock.leisten.count == 2, "Rechts zwei Leisten in einem Dock")
            let vorher = dock.aktiv
            if let reiter = dock.subviews.compactMap({ $0 as? DockReiter }).first {
                let andere = dock.leisten.firstIndex { $0 !== vorher } ?? 0
                let p = reiter.mitteFuerProbe(andere)
                klick(reiter, p)
                pruefe(dock.aktiv !== vorher, "Klick auf den Reiter unten wechselt die Leiste")
            }
            if let a = dock.aktiv, let zu = alleKnoepfe(a).first(where: { $0.title == "✕" }) {
                geschlossen = a
                pruefe(klick(zu, mitte(zu)) === zu, "Klick trifft das ✕ von «\(a.titel)»")
            }
        }
        s {
            // Die Einstellung wirkt über eine Benachrichtigung, also einen Augenblick später.
            if let a = geschlossen { pruefe(!h.rechterDock.enthaelt(a), "✕ schliesst «\(a.titel)»") }
            Einstellungen.funktionslisteSichtbar = false
            Einstellungen.miniaturansichtSichtbar = false
        }
        s {
            bericht(fehlerzahl == 0 ? "ERGEBNIS: alles bestanden" : "ERGEBNIS: \(fehlerzahl) Fehler")
        }
        func fuehreAus(_ i: Int) {
            guard i < schritte.count else { return fertig() }
            notiere("· schritt \(i)")
            schritte[i]()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { fuehreAus(i + 1) }
        }
        fuehreAus(0)
    }

    private static func alleAnsichten(_ v: NSView) -> [NSView] { [v] + v.subviews.flatMap(alleAnsichten) }
    private static func alleKnoepfe(_ v: NSView) -> [NSButton] { alleAnsichten(v).compactMap { $0 as? NSButton } }

    /// JSON Viewer, XML Tools, MIME Tools und Converter am vordersten Dokument.
    private static func plugins(ordner: URL, bericht: @escaping (String) -> Void, fertig: @escaping () -> Void) {
        let h = Hauptfenster.gemeinsam
        guard let fenster = h.window, let e = h.editor else { return fertig() }
        let p = Plugins.gemeinsam
        func text() -> String { String(decoding: e.utf8, as: UTF8.self) }
        func setze(_ t: String) { e.ersetze([(0..<e.laenge, t)]); e.waehleAus(0..<0) }
        var schritte: [() -> Void] = []
        schritte.append {
            setze(#"{"name":"NoteMac++","version":1.20,"plugins":["JSON Viewer","XML Tools"],"frei":true,"leer":{}}"#)
            p.fuehreAus("json.format")
            bericht("json format:\n" + text())
            p.fuehreAus("json.viewer")
        }
        schritte.append {}
        schritte.append {
            bericht("json viewer zeilen: \(JSONAnsicht.gemeinsam.anzahlZeilen), sprache \(e.sprache.name)")
            bild(von: fenster, nach: ordner.appendingPathComponent("json-viewer.png"))
            p.fuehreAus("json.compress")
            bericht("json compress: " + text())
            e.nachricht(SCI_UNDO)
            bericht("rückgängig in einem Schritt: \(text().contains("\n"))")
            setze("{\n  \"a\": 1,\n  \"b\" 2\n}")
            p.fuehreAus("json.validate")
            bericht("json fehler: marke bei \(e.auswahl.lowerBound), zeile \(e.aktuelleZeile)")
        }
        schritte.append {
            fenster.attachedSheet.map { fenster.endSheet($0) }
            setze(#"<?xml version="1.0"?><liste><eintrag id="1">Eins</eintrag><eintrag id="2"/></liste>"#)
            p.fuehreAus("xml.pretty")
            bericht("xml pretty:\n" + text())
            p.fuehreAus("xml.linearize")
            bericht("xml linear: " + text())
            setze("Grüezi Welt")
            e.waehleAus(0..<e.laenge)
            p.fuehreAus("mime.base64"); bericht("base64: " + text())
            e.waehleAus(0..<e.laenge)
            p.fuehreAus("mime.unbase64"); bericht("zurück: " + text())
            e.waehleAus(0..<e.laenge)
            p.fuehreAus("conv.hex"); bericht("hex: " + text())
            e.waehleAus(0..<e.laenge)
            p.fuehreAus("conv.unhex"); bericht("zurück: " + text())
            let plugins = NSApp.mainMenu?.items.first { $0.title == "Plugins" }?.submenu
            bericht("menü plugins: " + (plugins?.items.map { $0.isSeparatorItem ? "—" : $0.title + ($0.submenu.map { " [" + $0.items.map(\.title).joined(separator: ", ") + "]" } ?? "") }.joined(separator: " | ") ?? "fehlt"))
            Einstellungen.jsonViewerSichtbar = false
            setze("")
            h.aktivesDokument?.updateChangeCount(.changeCleared)
        }
        func fuehreAus(_ i: Int) {
            guard i < schritte.count else { return fertig() }
            schritte[i]()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { fuehreAus(i + 1) }
        }
        fuehreAus(0)
    }

    private static func eintrag(_ tag: Int) -> NSMenuItem {
        let eintrag = NSMenuItem()
        eintrag.tag = tag
        return eintrag
    }

    /// Das Fenster samt Titelleiste, von der App selbst gezeichnet (kein Bildschirmfoto).
    private static func bild(von fenster: NSWindow, nach ziel: URL) {
        guard let ansicht = fenster.contentView?.superview ?? fenster.contentView,
            let flaeche = ansicht.bitmapImageRepForCachingDisplay(in: ansicht.bounds)
        else { return }
        ansicht.cacheDisplay(in: ansicht.bounds, to: flaeche)
        try? flaeche.representation(using: .png, properties: [:])?.write(to: ziel)
    }
}
