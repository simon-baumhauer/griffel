import AppKit

/// Eine geöffnete Datei. Öffnen, Sichern, «Sichern unter», der Punkt im
/// Schliessknopf und die Nachfrage beim Schliessen kommen von NSDocument.
@objc(KladdeDokument)
final class Dokument: NSDocument {
    private(set) var datei = Textdatei()
    private(set) var editor: Editor?

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

    override class var autosavesInPlace: Bool { false }

    override func makeWindowControllers() {
        let editor = Editor()
        editor.lade(datei)
        editor.setzeSprache(sprache())
        editor.geaendert = { [weak self] geaendert in
            guard let self, geaendert || !self.abweichend else { return }
            self.updateChangeCount(geaendert ? .changeDone : .changeCleared)
        }
        self.editor = editor
        addWindowController(EditorFenster(editor: editor))
        if abweichend { updateChangeCount(.changeDone) }
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

    /// Beim nächsten Sichern geht der Text in diesem Zeichensatz auf die Platte.
    @objc func kodierungUmwandeln(_ sender: NSMenuItem) {
        guard let neu = Textdatei.Kodierung(rawValue: sender.tag), neu != datei.kodierung else { return }
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
    /// Zeichensatz — für den Fall, dass die Erkennung danebenlag.
    @objc func neuOeffnenAls(_ sender: NSMenuItem) {
        guard let neu = Textdatei.Kodierung(rawValue: sender.tag), let url = fileURL else { return }
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
        guard isDocumentEdited, let fenster = windowControllers.first?.window else { return lies() }
        let frage = NSAlert()
        frage.messageText = "«\(displayName ?? "")» neu öffnen als \(neu.name)?"
        frage.informativeText = "Die Änderungen seit dem letzten Sichern gehen dabei verloren."
        frage.addButton(withTitle: "Neu öffnen")
        frage.addButton(withTitle: "Abbrechen")
        frage.beginSheetModal(for: fenster) { antwort in
            if antwort == .alertFirstButtonReturn { lies() }
        }
    }

    @objc func zeilenendeUmwandeln(_ sender: NSMenuItem) {
        guard let neu = Textdatei.Zeilenende(rawValue: sender.tag), neu != datei.zeilenende else { return }
        datei.zeilenende = neu
        editor?.wandleZeilenendenUm(in: neu)
        // Ein Text ohne Zeilenende ändert sich nicht; gesichert werden soll trotzdem.
        abweichend = true
        updateChangeCount(.changeDone)
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        guard let eintrag = item as? NSMenuItem else { return super.validateUserInterfaceItem(item) }
        switch eintrag.action {
        case #selector(kodierungUmwandeln(_:)):
            eintrag.state = eintrag.tag == datei.kodierung.rawValue ? .on : .off
            return true
        case #selector(zeilenendeUmwandeln(_:)):
            eintrag.state = eintrag.tag == datei.zeilenende.rawValue ? .on : .off
            return true
        case #selector(neuOeffnenAls(_:)):
            return fileURL != nil
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

/// Kladde öffnet jede Datei als Text, was auch immer das System für ihren Typ hält.
final class Dokumente: NSDocumentController {
    /// Die offenen Dokumente in der Reihenfolge ihrer Tabs, Fenster um Fenster.
    static func inTabfolge() -> [Dokument] {
        var folge: [Dokument] = []
        for dokument in shared.documents.compactMap({ $0 as? Dokument })
        where !folge.contains(where: { $0 === dokument }) {
            guard let fenster = dokument.windowControllers.first?.window else { continue }
            for tab in fenster.tabbedWindows ?? [fenster] {
                if let nachbar = tab.windowController?.document as? Dokument,
                    !folge.contains(where: { $0 === nachbar })
                {
                    folge.append(nachbar)
                }
            }
        }
        return folge
    }

    override func documentClass(forType typeName: String) -> AnyClass? { Dokument.self }
    override var defaultType: String? { "public.plain-text" }
    override func typeForContents(of url: URL) throws -> String { "public.plain-text" }

    /// Beim Beenden fragt Kladde nicht nach ungesicherten Dokumenten: Die
    /// Sitzung hebt sie auf, und beim nächsten Start sind sie wieder da.
    /// (Beim Schliessen eines einzelnen Tabs fragt die App weiter.)
    override func reviewUnsavedDocuments(
        withAlertTitle title: String?, cancellable: Bool, delegate: Any?,
        didReviewAllSelector: Selector?, contextInfo: UnsafeMutableRawPointer?
    ) {
        Sitzung.sichere()
        guard let ziel = delegate as AnyObject?, let auswahl = didReviewAllSelector,
            let methode = ziel.method(for: auswahl)
        else { return }
        typealias Rueckruf = @convention(c) (AnyObject, Selector, AnyObject, Bool, UnsafeMutableRawPointer?) -> Void
        unsafeBitCast(methode, to: Rueckruf.self)(ziel, auswahl, self, true, contextInfo)
    }
}
