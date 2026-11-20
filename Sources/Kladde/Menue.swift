import AppKit

/// Die Menüleiste, im Code gebaut (die App hat keine Nib-Datei).
enum Menue {
    static func baue(appName: String) -> NSMenu {
        let leiste = NSMenu()

        leiste.addItem(untermenue(appName, [
            eintrag("Über \(appName)", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            eintrag("Einstellungen …", #selector(AppDelegate.zeigeEinstellungen(_:)), ","),
            .separator(),
            dienste(),
            .separator(),
            eintrag("\(appName) ausblenden", #selector(NSApplication.hide(_:)), "h"),
            eintrag("Andere ausblenden", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            eintrag("Alle einblenden", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            eintrag("\(appName) beenden", #selector(NSApplication.terminate(_:)), "q"),
        ]))

        leiste.addItem(untermenue("Ablage", [
            eintrag("Neu", #selector(NSDocumentController.newDocument(_:)), "n"),
            eintrag("Öffnen …", #selector(NSDocumentController.openDocument(_:)), "o"),
            ZuletztBenutzt.gemeinsam.menue(),
            .separator(),
            eintrag("Schliessen", #selector(NSWindow.performClose(_:)), "w"),
            eintrag("Sichern", #selector(NSDocument.save(_:)), "s"),
            eintrag("Sichern unter …", #selector(NSDocument.saveAs(_:)), "s", [.command, .shift]),
            eintrag("Zurück zur gesicherten Fassung", #selector(NSDocument.revertToSaved(_:))),
        ]))

        leiste.addItem(untermenue("Bearbeiten", [
            eintrag("Widerrufen", Selector(("undo:")), "z"),
            eintrag("Wiederholen", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            eintrag("Ausschneiden", #selector(NSText.cut(_:)), "x"),
            eintrag("Kopieren", #selector(NSText.copy(_:)), "c"),
            eintrag("Einsetzen", #selector(NSText.paste(_:)), "v"),
            eintrag("Alles auswählen", #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            eintrag("Zeile duplizieren", #selector(EditorFenster.dupliziere(_:)), "d"),
            eintrag("Zeilen löschen", #selector(EditorFenster.loescheZeilen(_:)), "k", [.command, .shift]),
            eintrag("Zeilen nach oben", #selector(EditorFenster.zeilenHoch(_:)), taste(NSUpArrowFunctionKey), [.command, .option]),
            eintrag("Zeilen nach unten", #selector(EditorFenster.zeilenRunter(_:)), taste(NSDownArrowFunctionKey), [.command, .option]),
            eintrag("Zeilen verbinden", #selector(EditorFenster.verbindeZeilen(_:)), "j", [.command, .control]),
            untermenue("Zeilen sortieren", Zeilenwerkzeug.Sortierung.allCases.map {
                mitWert($0.name, #selector(EditorFenster.sortiere(_:)), $0.rawValue)
            }),
            untermenue("Zeilen", [
                mitTag("Doppelte Zeilen entfernen", #selector(EditorFenster.zeilenBefehl(_:)), 1),
                mitTag("Aufeinanderfolgende doppelte Zeilen entfernen", #selector(EditorFenster.zeilenBefehl(_:)), 2),
                mitTag("Leere Zeilen entfernen", #selector(EditorFenster.zeilenBefehl(_:)), 3),
                mitTag("Leere Zeilen entfernen (auch mit Leerzeichen)", #selector(EditorFenster.zeilenBefehl(_:)), 4),
            ]),
            untermenue("Leerzeichen", [
                mitTag("Am Zeilenende entfernen", #selector(EditorFenster.zeilenBefehl(_:)), 10),
                mitTag("Am Zeilenanfang entfernen", #selector(EditorFenster.zeilenBefehl(_:)), 11),
                mitTag("An beiden Enden entfernen", #selector(EditorFenster.zeilenBefehl(_:)), 12),
                .separator(),
                mitTag("Tabs in Leerzeichen", #selector(EditorFenster.zeilenBefehl(_:)), 13),
                mitTag("Einrückung: Leerzeichen in Tabs", #selector(EditorFenster.zeilenBefehl(_:)), 14),
            ]),
            untermenue("Gross/klein", Schreibung.allCases.map { art -> NSMenuItem in
                let e = mitWert(art.name, #selector(EditorFenster.schreibung(_:)), art.rawValue)
                if art == .gross { e.keyEquivalent = "u"; e.keyEquivalentModifierMask = [.command, .shift] }
                if art == .klein { e.keyEquivalent = "u"; e.keyEquivalentModifierMask = [.command, .option] }
                return e
            }),
            .separator(),
            eintrag("Kommentar umschalten", #selector(EditorFenster.kommentar(_:)), "/"),
            eintrag("Blockkommentar umschalten", #selector(EditorFenster.blockkommentar(_:)), "/", [.command, .option]),
            eintrag("Spalteneditor …", #selector(EditorFenster.spalteneditor(_:)), "c", [.command, .option]),
            .separator(),
            eintrag("Überschreiben", #selector(EditorFenster.ueberschreiben(_:))),
        ]))

        leiste.addItem(untermenue("Suchen", [
            eintrag("Suchen …", #selector(EditorFenster.zeigeSuche(_:)), "f"),
            eintrag("Ersetzen …", #selector(EditorFenster.zeigeErsetzen(_:)), "f", [.command, .option]),
            eintrag("Weitersuchen", #selector(EditorFenster.weitersuchen(_:)), "g"),
            eintrag("Rückwärts suchen", #selector(EditorFenster.rueckwaertsSuchen(_:)), "g", [.command, .shift]),
            eintrag("Auswahl zum Suchen verwenden", #selector(EditorFenster.auswahlSuchen(_:)), "e"),
            .separator(),
            eintrag("In Dateien suchen …", #selector(AppDelegate.zeigeDateiSuche(_:)), "f", [.command, .shift]),
            eintrag("Suchergebnisse", #selector(AppDelegate.zeigeSuchergebnisse(_:)), "f", [.command, .option, .shift]),
            .separator(),
            eintrag("Markierungen entfernen", #selector(EditorFenster.markierungenEntfernen(_:))),
            .separator(),
            eintrag("Gehe zu Zeile …", #selector(EditorFenster.geheZuZeile(_:)), "l"),
            eintrag("Zur passenden Klammer", #selector(EditorFenster.zurPassendenKlammer(_:)), "b"),
            eintrag("Bis zur passenden Klammer auswählen", #selector(EditorFenster.bisZurPassendenKlammer(_:)), "b", [.command, .shift]),
            .separator(),
            untermenue("Lesezeichen", [
                eintrag("Lesezeichen setzen/entfernen", #selector(EditorFenster.lesezeichenSchalten(_:)), taste(NSF2FunctionKey)),
                eintrag("Nächstes Lesezeichen", #selector(EditorFenster.naechstesLesezeichen(_:)), taste(NSF2FunctionKey), []),
                eintrag("Vorheriges Lesezeichen", #selector(EditorFenster.vorherigesLesezeichen(_:)), taste(NSF2FunctionKey), [.shift]),
                eintrag("Alle Lesezeichen entfernen", #selector(EditorFenster.lesezeichenEntfernen(_:))),
                .separator(),
                eintrag("Zeilen mit Lesezeichen kopieren", #selector(EditorFenster.lesezeichenKopieren(_:))),
                eintrag("Zeilen mit Lesezeichen ausschneiden", #selector(EditorFenster.lesezeichenAusschneiden(_:))),
                eintrag("Zeilen mit Lesezeichen löschen", #selector(EditorFenster.lesezeichenZeilenLoeschen(_:))),
                eintrag("Zeilen ohne Lesezeichen löschen", #selector(EditorFenster.zeilenOhneLesezeichenLoeschen(_:))),
                eintrag("Lesezeichen umkehren", #selector(EditorFenster.lesezeichenUmkehren(_:))),
            ]),
        ]))

        leiste.addItem(untermenue("Darstellung", [
            eintrag("Zeilenumbruch", #selector(EditorFenster.zeilenumbruchUmschalten(_:)), "z", [.command, .option]),
            .separator(),
            eintrag("Schrift grösser", #selector(EditorFenster.schriftGroesser(_:)), "+"),
            eintrag("Schrift kleiner", #selector(EditorFenster.schriftKleiner(_:)), "-"),
            eintrag("Originalgrösse", #selector(EditorFenster.schriftOriginal(_:)), "0"),
            .separator(),
            symbole(),
            farbschemata(),
            .separator(),
            eintrag("Alles einklappen", #selector(EditorFenster.allesEinklappen(_:)), "0", [.command, .option]),
            eintrag("Alles ausklappen", #selector(EditorFenster.allesAusklappen(_:)), "0", [.command, .option, .shift]),
            .separator(),
            untermenue("Geteilte Ansicht", [
                mitTag("Keine", #selector(EditorFenster.geteilteAnsicht(_:)), 0),
                mitTag("Übereinander", #selector(EditorFenster.geteilteAnsicht(_:)), 1),
                mitTag("Nebeneinander", #selector(EditorFenster.geteilteAnsicht(_:)), 2),
            ]),
        ]))

        leiste.addItem(untermenue("Kodierung", kodierungsEintraege() + [.separator(), ueberschrift("Zeilenende")] + zeilenendeEintraege()))
        leiste.addItem(untermenue("Sprache", sprachEintraege()))
        leiste.addItem(MakroMenue.gemeinsam.menue())

        let fenster = untermenue("Fenster", [
            eintrag("Im Dock ablegen", #selector(NSWindow.performMiniaturize(_:)), "m"),
            eintrag("Zoomen", #selector(NSWindow.performZoom(_:))),
            .separator(),
            eintrag("Alle nach vorne bringen", #selector(NSApplication.arrangeInFront(_:))),
        ])
        leiste.addItem(fenster)
        // macOS hängt hier die Befehle für Tabs und die Liste der Fenster an.
        NSApp.windowsMenu = fenster.submenu

        return leiste
    }

    static func untermenue(_ titel: String, _ eintraege: [NSMenuItem]) -> NSMenuItem {
        let menue = NSMenu(title: titel)
        eintraege.forEach(menue.addItem)
        let kopf = NSMenuItem(title: titel, action: nil, keyEquivalent: "")
        kopf.submenu = menue
        return kopf
    }

    private static func eintrag(
        _ titel: String, _ aktion: Selector, _ taste: String = "",
        _ zusatz: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let eintrag = NSMenuItem(title: titel, action: aktion, keyEquivalent: taste)
        eintrag.keyEquivalentModifierMask = zusatz
        return eintrag
    }

    /// Wie in Notepad++: «Normaler Text» oben, darunter die Sprachen nach dem
    /// Anfangsbuchstaben in Untermenüs. Auch für die Statusleiste; jeder Aufruf
    /// baut neue Einträge (ein Eintrag gehört immer nur einem Menü).
    static func sprachEintraege() -> [NSMenuItem] {
        let alle = Sprachdaten.gemeinsam.sprachen.filter { $0.imMenue && !$0.istNormalerText }
        let gruppen = Dictionary(grouping: alle) { String($0.kurz.prefix(1)).uppercased() }
        var eintraege = [spracheEintrag(Sprachdaten.gemeinsam.normal, titel: "Normaler Text"), .separator()]
        for buchstabe in gruppen.keys.sorted() {
            let sprachen = gruppen[buchstabe]!.sorted { $0.kurz.localizedCaseInsensitiveCompare($1.kurz) == .orderedAscending }
            eintraege.append(untermenue(buchstabe, sprachen.map { spracheEintrag($0, titel: $0.kurz) }))
        }
        return eintraege
    }

    /// Wie in Notepad++: Ein Haken zeigt den Zeichensatz des Dokuments; ein
    /// Klick stellt um, wirksam beim nächsten Sichern.
    static func kodierungsEintraege() -> [NSMenuItem] {
        let zeichensaetze = Textdatei.Kodierung.allCases
        return [ueberschrift("Sichern als")]
            + zeichensaetze.map { mitTag($0.name, #selector(Dokument.kodierungUmwandeln(_:)), $0.rawValue) }
            + [untermenue("Neu öffnen als", zeichensaetze.map {
                mitTag($0.name, #selector(Dokument.neuOeffnenAls(_:)), $0.rawValue)
            })]
    }

    static func zeilenendeEintraege() -> [NSMenuItem] {
        [Textdatei.Zeilenende.crlf, .lf, .cr].map { mitTag($0.name, #selector(Dokument.zeilenendeUmwandeln(_:)), $0.rawValue) }
    }

    static func taste(_ funktionstaste: Int) -> String {
        String(Character(Unicode.Scalar(UInt32(funktionstaste))!))
    }

    private static func mitWert(_ titel: String, _ aktion: Selector, _ wert: String) -> NSMenuItem {
        let eintrag = NSMenuItem(title: titel, action: aktion, keyEquivalent: "")
        eintrag.representedObject = wert
        return eintrag
    }

    private static func spracheEintrag(_ sprache: Sprache, titel: String) -> NSMenuItem {
        let eintrag = NSMenuItem(title: titel, action: #selector(Dokument.spracheWaehlen(_:)), keyEquivalent: "")
        eintrag.representedObject = sprache.name
        eintrag.toolTip = sprache.lang
        return eintrag
    }

    private static func farbschemata() -> NSMenuItem {
        let ziel = DarstellungsMenue.gemeinsam
        func wahl(_ titel: String, _ name: String) -> NSMenuItem {
            let eintrag = NSMenuItem(title: titel, action: #selector(DarstellungsMenue.farbschemaWaehlen(_:)), keyEquivalent: "")
            eintrag.target = ziel
            eintrag.representedObject = name
            return eintrag
        }
        let namen = Sprachdaten.gemeinsam.farbschemaNamen
        return untermenue("Farbschema", [wahl("Automatisch (hell und dunkel)", ""), .separator()]
            + namen.map { wahl($0 == "DarkModeDefault" ? "Dark Mode Default" : $0, $0) })
    }

    private static func symbole() -> NSMenuItem {
        let ziel = DarstellungsMenue.gemeinsam
        func schalter(_ titel: String, _ aktion: Selector) -> NSMenuItem {
            let eintrag = NSMenuItem(title: titel, action: aktion, keyEquivalent: "")
            eintrag.target = ziel
            return eintrag
        }
        return untermenue("Symbole anzeigen", [
            schalter("Leerzeichen und Tabs", #selector(DarstellungsMenue.leerzeichenUmschalten(_:))),
            schalter("Zeilenenden", #selector(DarstellungsMenue.zeilenendenUmschalten(_:))),
            schalter("Alle Zeichen", #selector(DarstellungsMenue.alleZeichenUmschalten(_:))),
            .separator(),
            schalter("Einrückungshilfen", #selector(DarstellungsMenue.einrueckungshilfenUmschalten(_:))),
        ])
    }

    private static func mitTag(_ titel: String, _ aktion: Selector, _ tag: Int) -> NSMenuItem {
        let eintrag = NSMenuItem(title: titel, action: aktion, keyEquivalent: "")
        eintrag.tag = tag
        return eintrag
    }

    /// Grauer Zwischentitel (macOS 13 kennt NSMenuItem.sectionHeader noch nicht).
    private static func ueberschrift(_ titel: String) -> NSMenuItem {
        let eintrag = NSMenuItem(title: titel, action: nil, keyEquivalent: "")
        eintrag.isEnabled = false
        return eintrag
    }

    private static func dienste() -> NSMenuItem {
        let eintrag = NSMenuItem(title: "Dienste", action: nil, keyEquivalent: "")
        let menue = NSMenu(title: "Dienste")
        eintrag.submenu = menue
        NSApp.servicesMenu = menue
        return eintrag
    }
}
