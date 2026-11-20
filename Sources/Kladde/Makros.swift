import AppKit
import ScintillaBruecke

/// Ein aufgenommener Schritt: eine Nachricht an Scintilla. Text (getippte
/// Zeichen, eingesetzter Text) liegt als String bei, weil der Zeiger aus der
/// Aufnahme nur einen Augenblick gilt.
struct Makroschritt: Codable, Equatable {
    var nachricht: UInt32
    var w: UInt
    var l: Int
    var text: String?
    /// wParam ist die Länge des Textes (SCI_ADDTEXT, SCI_APPENDTEXT).
    var wMitLaenge = false
}

struct Makro: Codable, Equatable {
    var name: String
    var schritte: [Makroschritt]
}

/// Makros wie im Menü «Macro» von Notepad++: aufnehmen, abspielen, mehrfach
/// oder bis zum Ende abspielen, unter einem Namen sichern. Aufgenommen wird,
/// was Scintilla meldet (Tippen, Löschen, Bewegen, Ausschneiden, Einsetzen …);
/// Suchen über die Suchleiste gehört nicht dazu.
final class Makros {
    static let gemeinsam = Makros()

    private(set) weak var aufnehmender: Editor?
    private var aufnahme: [Makroschritt] = []

    /// Das zuletzt aufgenommene Makro («Current recorded macro»), auch nach dem Neustart.
    private(set) var aktuelles: [Makroschritt] {
        didSet { sichere() }
    }

    private(set) var gesicherte: [Makro] {
        didSet { sichere() }
    }

    var nimmtAuf: Bool { aufnehmender != nil }

    private init() {
        let ablage = UserDefaults.standard
        aktuelles = ablage.data(forKey: "MakroAktuell").flatMap { try? JSONDecoder().decode([Makroschritt].self, from: $0) } ?? []
        gesicherte = ablage.data(forKey: "Makros").flatMap { try? JSONDecoder().decode([Makro].self, from: $0) } ?? []
    }

    private func sichere() {
        let ablage = UserDefaults.standard
        ablage.set(try? JSONEncoder().encode(aktuelles), forKey: "MakroAktuell")
        ablage.set(try? JSONEncoder().encode(gesicherte), forKey: "Makros")
    }

    // MARK: Aufnehmen

    /// Nachrichten, deren lParam auf Text zeigt (aus Editor::NotifyMacroRecord in Scintilla).
    private static let mitText: Set<Int32> = [SCI_REPLACESEL, SCI_INSERTTEXT, SCI_SEARCHNEXT, SCI_SEARCHPREV]
    private static let mitTextUndLaenge: Set<Int32> = [SCI_ADDTEXT, SCI_APPENDTEXT]

    func starte(in editor: Editor) {
        beende()
        aufnahme = []
        aufnehmender = editor
        editor.makroSchritt = { [weak self] nachricht, w, l in self?.nimm(nachricht, w, l) }
        editor.starteAufnahme()
    }

    func beende() {
        guard let editor = aufnehmender else { return }
        editor.beendeAufnahme()
        editor.makroSchritt = nil
        aufnehmender = nil
        if !aufnahme.isEmpty { aktuelles = aufnahme }
    }

    private func nimm(_ nachricht: UInt32, _ w: UInt, _ l: Int) {
        let n = Int32(bitPattern: nachricht)
        var schritt = Makroschritt(nachricht: nachricht, w: w, l: l)
        if Self.mitText.contains(n) {
            schritt.text = Editor.text(zeiger: l, laenge: nil)
            schritt.l = 0
        } else if Self.mitTextUndLaenge.contains(n) {
            schritt.text = Editor.text(zeiger: l, laenge: Int(w))
            schritt.l = 0
            schritt.wMitLaenge = true
        }
        aufnahme.append(schritt)
    }

    // MARK: Abspielen

    /// Ein Schritt für «Widerrufen», egal wie oft.
    func spiele(_ schritte: [Makroschritt], in editor: Editor, mal: Int = 1) {
        guard !schritte.isEmpty else { return NSSound.beep() }
        editor.beginneSchritt()
        for _ in 0..<max(1, mal) { editor.spiele(schritte) }
        editor.beendeSchritt()
    }

    /// Bis zum Ende des Textes, nach der Regel von Notepad++ («Run until the
    /// end of file»): Schluss, sobald die Marke auf der letzten Zeile steht oder
    /// nicht weiterkommt. Die letzte Zeile selbst bleibt darum aus, wie dort.
    /// Antwort: wie oft.
    @discardableResult
    func spieleBisEnde(_ schritte: [Makroschritt], in editor: Editor) -> Int {
        guard !schritte.isEmpty else { NSSound.beep(); return 0 }
        editor.beginneSchritt()
        var mal = 0
        while mal < 100_000, editor.aktuelleZeile < editor.zeilenanzahl {
            let vorher = (editor.aktuelleZeile, editor.zeilenanzahl)
            editor.spiele(schritte)
            mal += 1
            let nachher = (editor.aktuelleZeile, editor.zeilenanzahl)
            // Nicht weiter nach unten gekommen und keine Zeile dazu: Es ginge ewig so.
            if nachher.0 <= vorher.0, nachher.1 <= vorher.1 { break }
        }
        editor.beendeSchritt()
        return mal
    }

    // MARK: Verwalten

    func sichere(_ name: String) {
        guard !aktuelles.isEmpty else { return }
        gesicherte.removeAll { $0.name == name }
        gesicherte.append(Makro(name: name, schritte: aktuelles))
        gesicherte.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func loesche(_ name: String) {
        gesicherte.removeAll { $0.name == name }
    }
}

/// Das Menü «Makros»: oben die Befehle von Notepad++, darunter die
/// gesicherten Makros und «Makro löschen», bei jedem Öffnen neu eingetragen.
final class MakroMenue: NSObject, NSMenuDelegate {
    static let gemeinsam = MakroMenue()
    var festeEintraege = 0

    func menuNeedsUpdate(_ menu: NSMenu) {
        while menu.items.count > festeEintraege { menu.removeItem(at: festeEintraege) }
        let gesicherte = Makros.gemeinsam.gesicherte
        guard !gesicherte.isEmpty else { return }
        menu.addItem(.separator())
        for makro in gesicherte {
            let eintrag = NSMenuItem(title: makro.name, action: #selector(spiele(_:)), keyEquivalent: "")
            eintrag.target = self
            eintrag.representedObject = makro.name
            menu.addItem(eintrag)
        }
        let loeschen = NSMenu(title: "Makro löschen")
        for makro in gesicherte {
            let eintrag = NSMenuItem(title: makro.name, action: #selector(loescheMakro(_:)), keyEquivalent: "")
            eintrag.target = self
            eintrag.representedObject = makro.name
            loeschen.addItem(eintrag)
        }
        let kopf = NSMenuItem(title: "Makro löschen", action: nil, keyEquivalent: "")
        kopf.submenu = loeschen
        menu.addItem(.separator())
        menu.addItem(kopf)
    }

    @objc func spiele(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String, let e = Hauptfenster.gemeinsam.aktiv,
            let makro = Makros.gemeinsam.gesicherte.first(where: { $0.name == name })
        else { return }
        Makros.gemeinsam.spiele(makro.schritte, in: e)
    }

    @objc private func loescheMakro(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        let frage = NSAlert()
        frage.messageText = "Makro «\(name)» löschen?"
        frage.addButton(withTitle: "Löschen")
        frage.addButton(withTitle: "Abbrechen")
        if frage.runModal() == .alertFirstButtonReturn { Makros.gemeinsam.loesche(name) }
    }
}

/// Die Dialoge «Aufgenommenes Makro speichern» und «Makro mehrfach ausführen».
enum MakroDialoge {
    static func sichern(fenster: NSWindow?) {
        let makros = Makros.gemeinsam
        if makros.nimmtAuf { makros.beende() }
        guard let fenster, !makros.aktuelles.isEmpty else { return NSSound.beep() }
        let frage = NSAlert()
        frage.messageText = Oberflaeche.gemeinsam.titel("IDM_MACRO_SAVECURRENTMACRO").replacingOccurrences(of: " …", with: "")
        frage.informativeText = "\(makros.aktuelles.count) Schritte. Unter diesem Namen steht es im Menü «Makros»."
        let feld = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        feld.placeholderString = "Name"
        frage.accessoryView = feld
        frage.addButton(withTitle: "OK")
        frage.addButton(withTitle: "Abbrechen")
        frage.window.initialFirstResponder = feld
        frage.beginSheetModal(for: fenster) { antwort in
            let name = feld.stringValue.trimmingCharacters(in: .whitespaces)
            guard antwort == .alertFirstButtonReturn, !name.isEmpty else { return }
            makros.sichere(name)
        }
    }

    /// Wie «Run a Macro Multiple Times» in Notepad++: n-mal oder bis zum Ende der Datei.
    static func mehrfach(fenster: NSWindow?, editor e: Editor) {
        let makros = Makros.gemeinsam
        if makros.nimmtAuf { makros.beende() }
        guard let fenster else { return }
        let auswahl = NSPopUpButton()
        auswahl.addItem(withTitle: "Aktuell aufgenommenes Makro")
        for makro in makros.gesicherte { auswahl.addItem(withTitle: makro.name) }
        let nMal = NSButton(radioButtonWithTitle: "Ausführen:", target: nil, action: nil)
        let bisEnde = NSButton(radioButtonWithTitle: "Bis zum Dateiende ausführen", target: nil, action: nil)
        nMal.state = .on
        let anzahl = NSTextField(string: "1")
        anzahl.widthAnchor.constraint(equalToConstant: 60).isActive = true
        let zeileN = NSStackView(views: [nMal, anzahl, NSTextField(labelWithString: "mal")])
        let stapel = NSStackView(views: [auswahl, zeileN, bisEnde])
        stapel.orientation = .vertical
        stapel.alignment = .leading
        stapel.frame = NSRect(x: 0, y: 0, width: 320, height: 90)
        let gruppe = RadioGruppe([nMal, bisEnde])
        for k in [nMal, bisEnde] {
            k.target = gruppe
            k.action = #selector(RadioGruppe.gewaehlt(_:))
        }
        let frage = NSAlert()
        frage.messageText = Oberflaeche.gemeinsam.titel("IDM_MACRO_RUNMULTIMACRODLG").replacingOccurrences(of: " …", with: "")
        frage.accessoryView = stapel
        frage.addButton(withTitle: "Ausführen")
        frage.addButton(withTitle: "Abbrechen")
        frage.beginSheetModal(for: fenster) { antwort in
            _ = gruppe
            guard antwort == .alertFirstButtonReturn else { return }
            let schritte = auswahl.indexOfSelectedItem == 0
                ? makros.aktuelles : makros.gesicherte[auswahl.indexOfSelectedItem - 1].schritte
            if bisEnde.state == .on {
                makros.spieleBisEnde(schritte, in: e)
            } else {
                makros.spiele(schritte, in: e, mal: max(1, min(anzahl.integerValue, 100_000)))
            }
        }
    }
}

/// Radioknöpfe, die nicht im selben Elternelement liegen, schliessen sich nicht
/// selbst aus; diese Gruppe tut es.
final class RadioGruppe: NSObject {
    private let knoepfe: [NSButton]
    init(_ knoepfe: [NSButton]) { self.knoepfe = knoepfe }
    @objc func gewaehlt(_ sender: NSButton) {
        for k in knoepfe { k.state = k === sender ? .on : .off }
    }
}
