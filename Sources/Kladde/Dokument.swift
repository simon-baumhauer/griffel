import AppKit
import ScintillaBruecke

/// Eine geöffnete Datei, ein Tab im Hauptfenster. Öffnen, Sichern, «Sichern
/// unter» und die Nachfrage beim Schliessen kommen von NSDocument; ein eigenes
/// Fenster hat das Dokument nicht.
@objc(KladdeDokument)
final class Dokument: NSDocument {
    private(set) var datei = Textdatei()
    private(set) var editor: Editor?

    // Was Notepad++ je Tab führt.
    var angeheftet = false
    /// Tab-Farbe 1–5 (Ansicht → Tabs → Farbe anwenden).
    var tabFarbe: Int?
    /// «Schreibschutz in Notepad++»: nur in NoteMac++, die Datei bleibt, wie sie ist.
    var schreibgeschuetzt = false {
        didSet {
            editor?.nachricht(SCI_SETREADONLY, schreibgeschuetzt ? 1 : 0)
            Hauptfenster.gemeinsam.tabsGeaendert()
        }
    }
    /// Für neue Dateien die Nummer in «neu 1», «neu 2» …: die kleinste freie.
    private lazy var neuNummer: Int = {
        let vergeben = Set(Hauptfenster.gemeinsam.tabs.filter { $0 !== self && $0.fileURL == nil }.map(\.neuNummer))
        return (1...).first { !vergeben.contains($0) }!
    }()

    /// Wie der Tab heisst: der Dateiname, oder «neu 1».
    var tabTitel: String {
        fileURL?.lastPathComponent ?? (Oberflaeche.gemeinsam.texte["tab-untitled-string"] ?? "neu ") + "\(neuNummer)"
    }

    override var displayName: String! {
        get { fileURL == nil ? tabTitel : super.displayName }
        set { super.displayName = newValue }
    }

    /// Name der Sicherung dieses Dokuments im Ordner der Sitzung.
    let sitzungsId = UUID().uuidString

    /// Das Dokument weicht von seiner Datei ab, ohne dass Scintilla es weiss:
    /// aus einer Sitzung ungesichert zurückgeholt, oder der Zeichensatz ist
    /// umgestellt. Solange das gilt, macht «Widerrufen» es nicht sauber.
    private var abweichend = false

    override init() {
        super.init()
        // Widerrufen gehört Scintilla; ein zweites Protokoll von AppKit würde
        // «Widerrufen» im Menü abfangen.
        hasUndoManager = false
    }

    /// Ein neues, leeres Dokument: Zeilenende, Kodierung und Sprache aus «Optionen → Neues Dokument».
    func setzeVorgabenFuerNeu() {
        datei.zeilenende = [Textdatei.Zeilenende.crlf, .lf, .cr][Einstellungen.neuZeilenende]
        datei.kodierung = [Textdatei.Kodierung.windows1252, .utf8, .utf8MitBOM, .utf16BE, .utf16LE][Einstellungen.neuKodierung]
        if !Einstellungen.neuSprache.isEmpty { gewaehlteSprache = Einstellungen.neuSprache }
    }

    override class var autosavesInPlace: Bool { false }

    /// Statt eines Fensters ein Tab im Hauptfenster.
    override func makeWindowControllers() {
        guard editor == nil else { return }
        let editor = Editor()
        editor.lade(datei)
        editor.setzeSprache(sprache())
        editor.geaendert = { [weak self] geaendert in
            guard let self, geaendert || !self.abweichend else { return }
            self.updateChangeCount(geaendert ? .changeDone : .changeCleared)
        }
        self.editor = editor
        _ = neuNummer
        Hauptfenster.gemeinsam.nimmAuf(self)
        if abweichend { updateChangeCount(.changeDone) }
    }

    override func showWindows() {
        Hauptfenster.gemeinsam.nimmAuf(self)
        Hauptfenster.gemeinsam.showWindow(nil)
    }

    override var windowForSheet: NSWindow? { Hauptfenster.gemeinsam.window }

    override func close() {
        Hauptfenster.gemeinsam.entferne(self)
        super.close()
    }

    /// Ein Dokument aus der letzten Sitzung, das dort nicht gesichert war: Der
    /// Text kommt aus der Sicherung, die Datei (wenn es eine gibt) bleibt, wie
    /// sie ist. Vor makeWindowControllers aufzurufen.
    func stelleUngesichertWiederHer(_ datei: Textdatei, datei url: URL?) {
        self.datei = datei
        fileURL = url
        fileType = "public.plain-text"
        if let url {
            // Sonst hält NSDocument die Datei beim Sichern für fremd verändert.
            fileModificationDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate
        }
        abweichend = true
    }

    // MARK: Lesen und Schreiben

    override func read(from data: Data, ofType typeName: String) throws {
        datei = Textdatei(daten: data)
        abweichend = false
        editor?.lade(datei)  // «Zurück zur gesicherten Fassung» bei offenem Fenster
    }

    override func data(ofType typeName: String) throws -> Data {
        try aktuell().kodiert()
    }

    /// Die Datei mit dem Text, wie er jetzt im Editor steht.
    func aktuell() -> Textdatei {
        if let editor { datei.utf8 = editor.utf8 }
        return datei
    }

    override func updateChangeCount(withToken changeCountToken: Any, for saveOperation: NSDocument.SaveOperationType) {
        super.updateChangeCount(withToken: changeCountToken, for: saveOperation)
        abweichend = false
        editor?.merkeGesichert()
        Hauptfenster.gemeinsam.tabsGeaendert()
    }

    override func updateChangeCount(_ change: NSDocument.ChangeType) {
        super.updateChangeCount(change)
        Hauptfenster.gemeinsam.tabsGeaendert()
    }

    // MARK: Sprache

    /// Von Hand im Menü «Sprache» gewählt (Name wie in langs.model.xml). Ohne
    /// Wahl gilt, was Sprachdaten.erkenne aus Dateiname und Anfang liest.
    var gewaehlteSprache: String?

    func sprache() -> Sprache {
        let daten = Sprachdaten.gemeinsam
        if let name = gewaehlteSprache, let sprache = daten.sprache(name) { return sprache }
        return daten.erkenne(url: fileURL, anfang: aktuell().utf8.prefix(256))
    }

    @objc func spracheWaehlen(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        gewaehlteSprache = name
        editor?.setzeSprache(sprache())
    }

    override var fileURL: URL? {
        didSet {
            // «Sichern unter» mit anderer Endung: neu erkennen, wie Notepad++.
            guard oldValue?.pathExtension.lowercased() != fileURL?.pathExtension.lowercased() else { return }
            if oldValue != nil { gewaehlteSprache = nil }
            editor?.setzeSprache(sprache())
        }
    }

    // MARK: Menü «Kodierung»

    /// Beim nächsten Sichern geht der Text in diesem Zeichensatz auf die Platte
    /// («Konvertiere zu …» in Notepad++).
    func wandleUm(in neu: Textdatei.Kodierung) {
        guard neu != datei.kodierung else { return }
        var probe = aktuell()
        probe.kodierung = neu
        do {
            _ = try probe.kodiert()
        } catch {
            presentError(error)
            return
        }
        datei.kodierung = neu
        abweichend = true
        updateChangeCount(.changeDone)
    }

    /// Liest die Datei noch einmal und deutet ihre Bytes im genannten
    /// Zeichensatz («Kodieren in …» in Notepad++). Ohne Datei: wie Umwandeln.
    func oeffneNeu(als neu: Textdatei.Kodierung) {
        guard let url = fileURL else { return wandleUm(in: neu) }
        let lies = { [self] in
            do {
                datei = Textdatei(daten: try Data(contentsOf: url), als: neu)
                abweichend = false
                editor?.lade(datei)
                updateChangeCount(.changeCleared)
            } catch {
                presentError(error)
            }
        }
        guard isDocumentEdited, let fenster = windowForSheet else { return lies() }
        let frage = NSAlert()
        frage.messageText = "«\(displayName ?? "")» neu öffnen als \(neu.name)?"
        frage.informativeText = "Die Änderungen seit dem letzten Sichern gehen dabei verloren."
        frage.addButton(withTitle: "Neu öffnen")
        frage.addButton(withTitle: "Abbrechen")
        frage.beginSheetModal(for: fenster) { antwort in
            if antwort == .alertFirstButtonReturn { lies() }
        }
    }

    func setzeZeilenende(_ neu: Textdatei.Zeilenende) {
        guard neu != datei.zeilenende else { return }
        datei.zeilenende = neu
        editor?.wandleZeilenendenUm(in: neu)
        // Ein Text ohne Zeilenende ändert sich nicht; gesichert werden soll trotzdem.
        abweichend = true
        updateChangeCount(.changeDone)
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        guard let eintrag = item as? NSMenuItem else { return super.validateUserInterfaceItem(item) }
        switch eintrag.action {
        case #selector(spracheWaehlen(_:)):
            eintrag.state = (eintrag.representedObject as? String) == editor?.sprache.name ? .on : .off
            return true
        default:
            return super.validateUserInterfaceItem(item)
        }
    }

    // MARK: Sichern-Dialog

    /// Jeder Name und jede Endung sind erlaubt; der Dialog hängt nichts an.
    override func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
        savePanel.allowedContentTypes = []
        savePanel.allowsOtherFileTypes = true
        savePanel.isExtensionHidden = false
        return true
    }

    override var shouldRunSavePanelWithAccessoryView: Bool { false }

    override func fileNameExtension(forType typeName: String, saveOperation: NSDocument.SaveOperationType) -> String? {
        nil
    }
}

/// NoteMac++ öffnet jede Datei als Text, was auch immer das System für ihren Typ hält.
final class Dokumente: NSDocumentController {
    /// Die offenen Dokumente in der Reihenfolge ihrer Tabs.
    static func inTabfolge() -> [Dokument] { Hauptfenster.gemeinsam.tabs }

    override func documentClass(forType typeName: String) -> AnyClass? { Dokument.self }

    /// Neue, leere Dokumente bekommen die Vorgaben aus «Optionen → Neues Dokument».
    override func makeUntitledDocument(ofType typeName: String) throws -> NSDocument {
        let d = try super.makeUntitledDocument(ofType: typeName)
        (d as? Dokument)?.setzeVorgabenFuerNeu()
        return d
    }
    override var defaultType: String? { "public.plain-text" }
    override func typeForContents(of url: URL) throws -> String { "public.plain-text" }

    /// Beim Beenden fragt NoteMac++ nicht nach ungesicherten Dokumenten: Die
    /// Sitzung hebt sie auf, und beim nächsten Start sind sie wieder da.
    /// (Beim Schliessen eines einzelnen Tabs fragt die App weiter.)
    override func reviewUnsavedDocuments(
        withAlertTitle title: String?, cancellable: Bool, delegate: Any?,
        didReviewAllSelector: Selector?, contextInfo: UnsafeMutableRawPointer?
    ) {
        guard Einstellungen.sitzungMerken else {
            return super.reviewUnsavedDocuments(
                withAlertTitle: title, cancellable: cancellable, delegate: delegate,
                didReviewAllSelector: didReviewAllSelector, contextInfo: contextInfo)
        }
        Sitzung.sichereZumBeenden()
        guard let ziel = delegate as AnyObject?, let auswahl = didReviewAllSelector,
            let methode = ziel.method(for: auswahl)
        else { return }
        typealias Rueckruf = @convention(c) (AnyObject, Selector, AnyObject, Bool, UnsafeMutableRawPointer?) -> Void
        unsafeBitCast(methode, to: Rueckruf.self)(ziel, auswahl, self, true, contextInfo)
    }
}
