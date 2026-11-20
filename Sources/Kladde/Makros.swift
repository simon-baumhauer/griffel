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

/// Das Menü «Makro». Die gesicherten Makros stehen unten und werden beim
/// Öffnen des Menüs neu eingetragen.
final class MakroMenue: NSObject, NSMenuDelegate, NSMenuItemValidation {
    static let gemeinsam = MakroMenue()

    private let aufnahme = NSMenuItem(title: "Aufnahme starten", action: #selector(EditorFenster.makroAufnahme(_:)), keyEquivalent: "r")
    private var festeEintraege = 0

    func menue() -> NSMenuItem {
        aufnahme.keyEquivalentModifierMask = [.command, .shift]
        let abspielen = NSMenuItem(title: "Abspielen", action: #selector(EditorFenster.makroAbspielen(_:)), keyEquivalent: "p")
        abspielen.keyEquivalentModifierMask = [.command, .shift]
        let menue = NSMenu(title: "Makro")
        menue.delegate = self
        for eintrag in [
            aufnahme, abspielen,
            NSMenuItem(title: "Mehrfach abspielen …", action: #selector(EditorFenster.makroMehrfach(_:)), keyEquivalent: ""),
            NSMenuItem(title: "Aufgenommenes Makro sichern …", action: #selector(EditorFenster.makroSichern(_:)), keyEquivalent: ""),
            .separator(),
        ] {
            menue.addItem(eintrag)
        }
        festeEintraege = menue.items.count
        let kopf = NSMenuItem(title: "Makro", action: nil, keyEquivalent: "")
        kopf.submenu = menue
        return kopf
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        aufnahme.title = Makros.gemeinsam.nimmtAuf ? "Aufnahme beenden" : "Aufnahme starten"
        while menu.items.count > festeEintraege { menu.removeItem(at: festeEintraege) }
        let gesicherte = Makros.gemeinsam.gesicherte
        if gesicherte.isEmpty {
            let leer = NSMenuItem(title: "Keine gesicherten Makros", action: nil, keyEquivalent: "")
            leer.isEnabled = false
            menu.addItem(leer)
            return
        }
        for makro in gesicherte {
            let eintrag = NSMenuItem(title: makro.name, action: #selector(EditorFenster.makroAbspielen(_:)), keyEquivalent: "")
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

    @objc private func loescheMakro(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        let frage = NSAlert()
        frage.messageText = "Makro «\(name)» löschen?"
        frage.addButton(withTitle: "Löschen")
        frage.addButton(withTitle: "Abbrechen")
        if frage.runModal() == .alertFirstButtonReturn { Makros.gemeinsam.loesche(name) }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool { true }
}
