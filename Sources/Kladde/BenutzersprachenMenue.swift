import AppKit
import UniformTypeIdentifiers

/// «Sprache → Benutzerdefiniert»: die importierten Sprachen (UDL von Notepad++),
/// «Importieren …» und der Ordner im Finder. Der Inhalt entsteht beim Öffnen.
final class BenutzersprachenMenue: NSObject, NSMenuDelegate {
    static let gemeinsam = BenutzersprachenMenue()

    func menue() -> NSMenuItem {
        let menue = NSMenu(title: "Benutzerdefiniert")
        menue.delegate = self
        let kopf = NSMenuItem(title: "Benutzerdefiniert", action: nil, keyEquivalent: "")
        kopf.submenu = menue
        return kopf
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let daten = Sprachdaten.gemeinsam
        let sprachen = daten.benutzersprachen.values.map(\.sprache).sorted {
            $0.kurz.localizedCaseInsensitiveCompare($1.kurz) == .orderedAscending
        }
        for sprache in sprachen {
            let eintrag = NSMenuItem(title: sprache.kurz, action: #selector(Dokument.spracheWaehlen(_:)), keyEquivalent: "")
            eintrag.representedObject = sprache.name
            eintrag.toolTip = sprache.endungen.isEmpty ? nil : "Endungen: " + sprache.endungen.joined(separator: " ")
            menu.addItem(eintrag)
        }
        if sprachen.isEmpty {
            let leer = NSMenuItem(title: "Noch keine", action: nil, keyEquivalent: "")
            leer.isEnabled = false
            menu.addItem(leer)
        }
        if !daten.benutzerspracheFehler.isEmpty {
            let fehler = NSMenuItem(
                title: "\(daten.benutzerspracheFehler.count) Dateien nicht lesbar …", action: #selector(zeigeFehler), keyEquivalent: "")
            fehler.target = self
            menu.addItem(fehler)
        }
        menu.addItem(.separator())
        for (titel, aktion) in [("Importieren …", #selector(importiere)), ("Ordner im Finder zeigen", #selector(zeigeOrdner))] {
            let e = NSMenuItem(title: titel, action: aktion, keyEquivalent: "")
            e.target = self
            menu.addItem(e)
        }
    }

    @objc private func zeigeFehler() {
        let meldung = NSAlert()
        meldung.messageText = "Nicht lesbare Dateien"
        meldung.informativeText = Sprachdaten.gemeinsam.benutzerspracheFehler.joined(separator: "\n")
        meldung.runModal()
    }

    func zeigeOrdnerOeffentlich() { zeigeOrdner() }

    @objc private func zeigeOrdner() {
        let ordner = Sprachdaten.benutzersprachenOrdner
        try? FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([ordner])
    }

    /// Kopiert UDL-Dateien (XML aus Notepad++, «Export…» oder userDefineLangs) in
    /// den Ordner von NoteMac++ und liest sie ein. Was sich nicht lesen lässt, bleibt draussen.
    @objc func importiere() {
        let wahl = NSOpenPanel()
        wahl.allowedContentTypes = [.xml]
        wahl.allowsMultipleSelection = true
        wahl.message = "Benutzerdefinierte Sprachen von Notepad++ (XML) wählen"
        wahl.prompt = "Importieren"
        guard wahl.runModal() == .OK else { return }

        let ordner = Sprachdaten.benutzersprachenOrdner
        var neu: [String] = []
        var fehler: [String] = []
        do {
            try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        } catch {
            NSApp.presentError(error)
            return
        }
        for datei in wahl.urls {
            do {
                let sprachen = try Benutzersprache.lade(datei)
                guard !sprachen.isEmpty else { throw Suchfehler(meldung: "keine <UserLang> darin") }
                let ziel = ordner.appendingPathComponent(datei.lastPathComponent)
                if FileManager.default.fileExists(atPath: ziel.path) { try FileManager.default.removeItem(at: ziel) }
                try FileManager.default.copyItem(at: datei, to: ziel)
                neu += sprachen.map(\.name)
            } catch {
                fehler.append("\(datei.lastPathComponent): \(error.localizedDescription)")
            }
        }
        Sprachdaten.gemeinsam.ladeBenutzersprachen()

        let meldung = NSAlert()
        meldung.messageText = neu.isEmpty ? "Nichts importiert" : "Importiert: " + neu.joined(separator: ", ")
        var info = neu.isEmpty ? "" : "Die Sprachen stehen unter «Sprache → Benutzerdefiniert»; Dateien mit ihren Endungen erkennt NoteMac++ beim Öffnen."
        if !fehler.isEmpty { info += (info.isEmpty ? "" : "\n\n") + fehler.joined(separator: "\n") }
        meldung.informativeText = info
        meldung.runModal()
    }
}
