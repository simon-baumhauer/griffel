import AppKit

/// Die Menüleiste, im Code gebaut (die App hat keine Nib-Datei).
enum Menue {
    static func baue(appName: String) -> NSMenu {
        let leiste = NSMenu()

        leiste.addItem(untermenue(appName, [
            eintrag("Über \(appName)", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
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
        ]))

        leiste.addItem(sprachen())

        // Wie in Notepad++: Ein Haken zeigt den Zeichensatz und das Zeilenende
        // des Dokuments; ein Klick stellt um, wirksam beim nächsten Sichern.
        let zeichensaetze = Textdatei.Kodierung.allCases
        leiste.addItem(untermenue("Kodierung", [
            ueberschrift("Sichern als"),
        ] + zeichensaetze.map {
            mitTag($0.name, #selector(Dokument.kodierungUmwandeln(_:)), $0.rawValue)
        } + [
            untermenue("Neu öffnen als", zeichensaetze.map {
                mitTag($0.name, #selector(Dokument.neuOeffnenAls(_:)), $0.rawValue)
            }),
            .separator(),
            ueberschrift("Zeilenende"),
        ] + [Textdatei.Zeilenende.crlf, .lf, .cr].map {
            mitTag($0.name, #selector(Dokument.zeilenendeUmwandeln(_:)), $0.rawValue)
        }))

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

    private static func untermenue(_ titel: String, _ eintraege: [NSMenuItem]) -> NSMenuItem {
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
    /// Anfangsbuchstaben in Untermenüs.
    private static func sprachen() -> NSMenuItem {
        let alle = Sprachdaten.gemeinsam.sprachen.filter { $0.imMenue && !$0.istNormalerText }
        let gruppen = Dictionary(grouping: alle) { String($0.kurz.prefix(1)).uppercased() }
        var eintraege = [spracheEintrag(Sprachdaten.gemeinsam.normal, titel: "Normaler Text"), .separator()]
        for buchstabe in gruppen.keys.sorted() {
            let sprachen = gruppen[buchstabe]!.sorted { $0.kurz.localizedCaseInsensitiveCompare($1.kurz) == .orderedAscending }
            eintraege.append(untermenue(buchstabe, sprachen.map { spracheEintrag($0, titel: $0.kurz) }))
        }
        return untermenue("Sprache", eintraege)
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
