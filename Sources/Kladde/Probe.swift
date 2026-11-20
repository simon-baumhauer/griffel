import AppKit
import ScintillaBruecke

/// Selbstprüfung der laufenden App, für den Bau ohne Zuschauer:
///
///     open -n -a build/Kladde.app datei1 datei2 --args -KladdeProbe /pfad/zum/ordner \
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
        case "plugins":
            plugins(ordner: ordner, bericht: { bericht.append($0) }, fertig: schliesse)
            return
        case "oberflaeche":
            oberflaeche(ordner: ordner, bericht: { bericht.append($0) }, fertig: schliesse)
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

    /// JSON Viewer, XML Tools, MIME Tools und Converter am vordersten Dokument.
    private static func plugins(ordner: URL, bericht: @escaping (String) -> Void, fertig: @escaping () -> Void) {
        let h = Hauptfenster.gemeinsam
        guard let fenster = h.window, let e = h.editor else { return fertig() }
        let p = Plugins.gemeinsam
        func text() -> String { String(decoding: e.utf8, as: UTF8.self) }
        func setze(_ t: String) { e.ersetze([(0..<e.laenge, t)]); e.waehleAus(0..<0) }
        var schritte: [() -> Void] = []
        schritte.append {
            setze(#"{"name":"Kladde","version":1.20,"plugins":["JSON Viewer","XML Tools"],"frei":true,"leer":{}}"#)
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
