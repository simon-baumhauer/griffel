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
        let vorne = NSApp.orderedWindows.lazy.compactMap { $0.windowController?.document as? Dokument }.first
        let dokumente = NSDocumentController.shared.documents.compactMap { $0 as? Dokument }
        for (nummer, dokument) in dokumente.enumerated() {
            guard let fenster = dokument.windowControllers.first?.window, let editor = dokument.editor else {
                continue
            }
            let anfang = String(decoding: editor.utf8.prefix(40), as: UTF8.self)
                .replacingOccurrences(of: "\r", with: "\\r").replacingOccurrences(of: "\n", with: "\\n")
            bericht.append(
                "dokument \(nummer): «\(dokument.displayName ?? "?")» \(dokument.datei.kodierung.name), "
                    + "zeilenende \(dokument.datei.zeilenende), geändert \(dokument.isDocumentEdited), "
                    + "tabs im fenster \(fenster.tabbedWindows?.count ?? 1), marke \(editor.position)"
                    + (dokument === vorne ? ", vorne" : "") + ", sprache \(editor.sprache.name)"
                    + (dokument.gewaehlteSprache != nil ? " (gewählt)" : "") + ", text «\(anfang)»")
        }
        for (nummer, dokument) in dokumente.enumerated() {
            if let fenster = dokument.windowControllers.first?.window {
                fenster.makeKeyAndOrderFront(nil)
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
        case "suchen":
            sucheProbe(dokumente: dokumente, ordner: ordner, bericht: { bericht.append($0) }, fertig: schliesse)
            return
        case "tippen":
            for dokument in dokumente {
                dokument.editor?.ansicht.insertText("ungesichert ✓\n")
            }
            if let erstes = dokumente.first { erstes.kodierungUmwandeln(eintrag(Textdatei.Kodierung.utf16LE.rawValue)) }
            if dokumente.count > 1, let letztes = dokumente.last {
                letztes.zeilenendeUmwandeln(eintrag(Textdatei.Zeilenende.crlf.rawValue))
            }
            bericht.append("getippt in \(dokumente.count), geändert: "
                + dokumente.map { String($0.isDocumentEdited) }.joined(separator: " "))
            vorne?.windowControllers.first?.window?.makeKeyAndOrderFront(nil)
            return schliesse()
        case "nichts":
            return schliesse()
        case "darstellung":
            // Jedes Dokument in drei Farbschemata, dann mit Symbolen, markierter
            // Klammer und eingeklappt. Die Einstellungen gehen danach zurück.
            let vorher = (Einstellungen.farbschema, Einstellungen.leerzeichenZeigen, Einstellungen.zeilenendenZeigen)
            var schritte: [() -> Void] = []
            for (nummer, dokument) in dokumente.enumerated() {
                guard let fenster = dokument.windowControllers.first?.window, let editor = dokument.editor else {
                    continue
                }
                for schema in ["Standard", "DarkModeDefault", "Monokai"] {
                    schritte.append { Einstellungen.farbschema = schema; fenster.makeKeyAndOrderFront(nil) }
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
            if let fenster = dokumente.first?.windowControllers.first?.window {
                schritte.append { Einstellungen.farbschema = ""; NSApp.appearance = NSAppearance(named: .darkAqua) }
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
            dokument.kodierungUmwandeln(eintrag(Textdatei.Kodierung.utf16LE.rawValue))
            bericht.append("umgestellt: \(dokument.datei.kodierung.name), geändert \(dokument.isDocumentEdited)")
            dokument.save(to: ziel, ofType: "public.plain-text", for: .saveOperation) { fehler in
                let bytes = (try? Data(contentsOf: ziel)) ?? Data()
                bericht.append(
                    "gesichert: fehler \(fehler?.localizedDescription ?? "keiner"), geändert \(dokument.isDocumentEdited), "
                        + "erste bytes \(bytes.prefix(6).map { String(format: "%02x", $0) }.joined(separator: " "))")
                dokument.neuOeffnenAls(eintrag(Textdatei.Kodierung.windows1252.rawValue))
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
        guard let fensterKontrolle = NSApp.orderedWindows.lazy.compactMap({ $0.windowController as? EditorFenster }).first,
            let fenster = fensterKontrolle.window
        else {
            bericht("suchen: kein Fenster")
            return fertig()
        }
        let editor = fensterKontrolle.editor
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
            fensterKontrolle.oeffneSuche(ersetzen: true)
            setze("bern")
            let antwort = Suchaktion.live(in: editor, ab: 0)
            bericht("live «bern»: \(antwort.text), auswahl \(zeigeAuswahl()), hinterlegt \(editor.anzahlMarkierungen(Editor.indikatorSuche))")
        }
        schritt { bild(von: fenster, nach: ordner.appendingPathComponent("leiste.png")) }
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
            fensterKontrolle.schliesseSuche()
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
            if let w = Suchergebnisse.gemeinsam.window { bild(von: w, nach: ordner.appendingPathComponent("ergebnisse-offen.png")) }
        }
        if let pfad = UserDefaults.standard.string(forKey: "KladdeProbeOrdner") {
            warte { weiter in
                DateiSuche.gemeinsam.zeige(ordnerVon: nil)
                DateiSuche.gemeinsam.setze(ordner: pfad, filter: "*.txt !\\ausgelassen")
                setze("Bern")
                DateiSuche.gemeinsam.starte(ersetzen: false) { satz in
                    bericht("ordner finden: \(satz)")
                    weiter()
                }
            }
            schritt {
                if let w = Suchergebnisse.gemeinsam.window { bild(von: w, nach: ordner.appendingPathComponent("ergebnisse-ordner.png")) }
                if let w = DateiSuche.gemeinsam.window { bild(von: w, nach: ordner.appendingPathComponent("dateisuche.png")) }
            }
            warte { weiter in
                setze("Bern", ersetzung: "Zürich")
                DateiSuche.gemeinsam.starte(ersetzen: true, bestaetigt: true) { satz in
                    bericht("ordner ersetzen: \(satz)")
                    weiter()
                }
            }
        }
        schritt { SuchZustand.gemeinsam.optionen = vorher }

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
        let fensterliste = NSApp.orderedWindows.compactMap { $0.windowController as? EditorFenster }
        let dokumente = Dokumente.inTabfolge()
        guard let python = dokumente.first(where: { $0.editor?.sprache.name == "python" }),
            let pf = python.windowControllers.first as? EditorFenster, let pfenster = pf.window
        else {
            bericht("etappe6: keine Python-Datei offen (\(fensterliste.count) Fenster)")
            return fertig()
        }
        let e = pf.editor
        let vorher = Einstellungen.funktionslisteSichtbar
        var schritte: [() -> Void] = []
        schritte.append {
            pfenster.makeKeyAndOrderFront(nil)
            Einstellungen.funktionslisteSichtbar = true
        }
        schritte.append {}
        schritte.append {}
        schritte.append {
            bericht("funktionsliste: \(pf.funktionslisteNamen)")
            bild(von: pfenster, nach: ordner.appendingPathComponent("funktionsliste.png"))
        }
        schritte.append {
            e.waehleAus(e.laenge..<e.laenge)
            e.ansicht.insertText("\nx = isinst")
        }
        schritte.append {
            bericht("vorschläge nach «isinst»: offen \(e.vorschlagOffen)")
            bild(von: pfenster, nach: ordner.appendingPathComponent("vorschlaege.png"))
            _ = e.ansicht.message(UInt32(SCI_AUTOCCANCEL), wParam: 0, lParam: 0)
            e.ansicht.insertText("\nlen(")
        }
        schritte.append {
            bericht("aufrufhilfe nach «len(»: offen \(e.aufrufhilfeOffen)")
            bild(von: pfenster, nach: ordner.appendingPathComponent("aufrufhilfe.png"))
            _ = e.ansicht.message(UInt32(SCI_CALLTIPCANCEL), wParam: 0, lParam: 0)
        }
        schritte.append {
            let eigene = dokumente.first { $0.editor?.sprache.istBenutzersprache ?? false }
            guard let eigene, let ef = eigene.windowControllers.first as? EditorFenster, let ed = eigene.editor else {
                bericht("udl: kein Dokument erkannt; geladen \(Sprachdaten.gemeinsam.benutzersprachen.keys.sorted()), fehler \(Sprachdaten.gemeinsam.benutzerspracheFehler)")
                return
            }
            ef.window?.makeKeyAndOrderFront(nil)
            let text = String(decoding: ed.utf8, as: UTF8.self)
            let stelle = text.utf8.count - (text.components(separatedBy: "WENN").last?.utf8.count ?? 0) - 4
            bericht("udl: sprache \(ed.sprache.name), stil von «WENN» \(ed.stil(bei: max(0, stelle))) (Keywords1 = 4)")
        }
        schritte.append {
            if let w = NSApp.orderedWindows.first(where: { ($0.windowController as? EditorFenster)?.editor.sprache.istBenutzersprache ?? false }) {
                bild(von: w, nach: ordner.appendingPathComponent("udl.png"))
            }
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
    /// geteilte Ansicht, Statusleiste und Einstellungen am vordersten Dokument.
    private static func etappe5(ordner: URL, bericht: @escaping (String) -> Void, fertig: @escaping () -> Void) {
        guard let f = NSApp.orderedWindows.lazy.compactMap({ $0.windowController as? EditorFenster }).first,
            let fenster = f.window
        else {
            bericht("etappe5: kein Fenster")
            return fertig()
        }
        let e = f.editor
        func text() -> String { String(decoding: e.utf8, as: UTF8.self).replacingOccurrences(of: "\n", with: "⏎") }
        func setze(_ t: String) {
            e.ersetze([(0..<e.laenge, t)])
            e.waehleAus(0..<0)
        }
        func menue(_ tag: Int) -> NSMenuItem { eintrag(tag) }
        func wert(_ w: String) -> NSMenuItem {
            let m = NSMenuItem()
            m.representedObject = w
            return m
        }
        var schritte: [() -> Void] = []

        schritte.append {
            setze("birne\nApfel\n10\napfel\n\n2\nApfel\n")
            f.sortiere(wert("aufsteigend"))
            bericht("sortiert: \(text())")
            f.sortiere(wert("ganzzahlAuf"))
            bericht("als Zahlen: \(text())")
            f.zeilenBefehl(menue(1))
            bericht("ohne Doppelte: \(text())")
            f.zeilenBefehl(menue(3))
            bericht("ohne Leere: \(text())")
            setze("a  \n\tb\t\n")
            f.zeilenBefehl(menue(12))
            bericht("gekürzt: \(text())")
        }
        schritte.append {
            setze("def f():\n    return 1\n")
            (f.document as? Dokument)?.gewaehlteSprache = "python"
            e.setzeSprache(Sprachdaten.gemeinsam.sprache("python")!)
            e.waehleAus(0..<e.laenge)
            f.kommentar(nil)
            bericht("kommentiert (python): \(text())")
            f.kommentar(nil)
            bericht("zurück: \(text())")
            setze("grüezi wohl")
            e.waehleAus(0..<e.laenge)
            f.schreibung(wert("woerterGross"))
            bericht("Wörter gross: \(text())")
            e.waehleAus(0..<0)
            f.dupliziere(nil)
            bericht("dupliziert: \(text())")
        }
        schritte.append {
            setze("eins\nzwei\ndrei\nvier\nfünf")
            e.lesezeichen = [1, 3]
            e.geheZuZeile(1)
            f.naechstesLesezeichen(nil)
            let erste = e.aktuelleZeile
            f.naechstesLesezeichen(nil)
            bericht("lesezeichen \(e.lesezeichen), springt zu Zeile \(erste) und \(e.aktuelleZeile), text «\(e.lesezeichenText().replacingOccurrences(of: "\n", with: "⏎"))»")
            f.zeilenOhneLesezeichenLoeschen(nil)
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
            // Längere letzte Zeile: darf nicht ewig an ihr weiterschreiben.
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
            f.teile(1)
        }
        schritte.append {
            bericht("geteilt: \(f.geteilt), statusleiste sichtbar")
            bild(von: fenster, nach: ordner.appendingPathComponent("geteilt.png"))
            f.teile(0)
            bericht("wieder eine Ansicht: \(f.geteilt)")
        }
        schritte.append {
            EinstellungsFenster.gemeinsam.zeige()
        }
        schritte.append {
            if let w = EinstellungsFenster.gemeinsam.window { bild(von: w, nach: ordner.appendingPathComponent("einstellungen.png")) }
            EinstellungsFenster.gemeinsam.close()
            // Probeinhalt verwerfen, damit die Sitzung ihn nicht aufhebt.
            setze("")
            (f.document as? Dokument)?.updateChangeCount(.changeCleared)
        }
        func fuehreAus(_ i: Int) {
            guard i < schritte.count else { return fertig() }
            schritte[i]()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { fuehreAus(i + 1) }
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
