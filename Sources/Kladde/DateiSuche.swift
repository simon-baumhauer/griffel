import AppKit

/// Das Fenster «In Dateien suchen», wie der Reiter «Find in Files» von
/// Notepad++. Text und Optionen teilt es mit der Suchleiste; Ordner, Filter
/// und die beiden Schalter merkt es sich selbst.
final class DateiSuche: NSWindowController, NSTextFieldDelegate {
    static let gemeinsam = DateiSuche()

    private let suchfeld = NSTextField()
    private let ersetzfeld = NSTextField()
    private let ordnerfeld = NSTextField()
    private let filterfeld = NSTextField()
    private let unterordner = NSButton(checkboxWithTitle: "Unterordner", target: nil, action: nil)
    private let versteckte = NSButton(checkboxWithTitle: "Versteckte Ordner und Dateien", target: nil, action: nil)
    private let modus = NSPopUpButton()
    private let grossKlein = NSButton(checkboxWithTitle: "Gross/klein", target: nil, action: nil)
    private let ganzesWort = NSButton(checkboxWithTitle: "Ganzes Wort", target: nil, action: nil)
    private let punkt = NSButton(checkboxWithTitle: "«.» findet Zeilenende", target: nil, action: nil)
    private let anzeige = NSTextField(wrappingLabelWithString: "")
    private var findenKnopf: NSButton!
    private var ersetzenKnopf: NSButton!
    private var abbrechenKnopf: NSButton!

    /// Gesetzt, solange eine Suche läuft; der Lauf fragt ihn vor jeder Datei.
    private var abbruch: Abbruch?
    private var beobachter: NSObjectProtocol?

    private final class Abbruch {
        private let schloss = NSLock()
        private var gesetzt = false
        func setze() { schloss.lock(); gesetzt = true; schloss.unlock() }
        var istGesetzt: Bool { schloss.lock(); defer { schloss.unlock() }; return gesetzt }
    }

    private let ablage = UserDefaults.standard
    /// Gesetzt, während dieses Fenster den Zustand selbst ändert: Dann bleiben die Felder, wie sie sind.
    private var eigeneAenderung = false

    private init() {
        let fenster = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 330),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: true)
        fenster.title = "In Dateien suchen"
        fenster.setFrameAutosaveName("DateiSuche")
        fenster.isRestorable = false
        super.init(window: fenster)
        baue()
        uebernehme()
        ordnerfeld.stringValue = ablage.string(forKey: "DateiSucheOrdner") ?? ""
        filterfeld.stringValue = ablage.string(forKey: "DateiSucheFilter") ?? "*.*"
        unterordner.state = ablage.object(forKey: "DateiSucheUnterordner") as? Bool ?? true ? .on : .off
        versteckte.state = ablage.bool(forKey: "DateiSucheVersteckte") ? .on : .off
        beobachter = NotificationCenter.default.addObserver(
            forName: SuchZustand.geaendert, object: nil, queue: .main
        ) { [weak self] _ in self?.uebernehme() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("DateiSuche entsteht nur im Code") }

    // MARK: Aufbau

    private func baue() {
        for feld in [suchfeld, ersetzfeld, ordnerfeld, filterfeld] {
            feld.delegate = self
            feld.lineBreakMode = .byTruncatingMiddle
            feld.cell?.isScrollable = true
        }
        suchfeld.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        ersetzfeld.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        filterfeld.placeholderString = "*.*"
        filterfeld.toolTip = "Muster durch Leerzeichen getrennt, z. B. «*.swift *.md». Mit «!» weglassen: «!*.min.js», Ordner «!\\build»."
        ordnerfeld.placeholderString = "Ordner"

        let waehlen = NSButton(title: "Wählen …", target: self, action: #selector(ordnerWaehlen))
        let ordnerZeile = NSStackView(views: [ordnerfeld, waehlen])
        ordnerZeile.spacing = 6
        ordnerfeld.setContentHuggingPriority(.init(1), for: .horizontal)

        for modusWert in SuchOptionen.Modus.allCases {
            modus.addItem(withTitle: modusWert.name)
            modus.lastItem?.tag = modusWert.rawValue
        }
        for schalter in [modus, grossKlein, ganzesWort, punkt] as [NSControl] {
            schalter.target = self
            schalter.action = #selector(optionGeaendert)
        }
        let optionen = NSStackView(views: [grossKlein, ganzesWort, punkt])
        optionen.spacing = 10
        let ordnerOptionen = NSStackView(views: [unterordner, versteckte])
        ordnerOptionen.spacing = 10

        func beschriftung(_ text: String) -> NSTextField {
            let feld = NSTextField(labelWithString: text)
            feld.alignment = .right
            return feld
        }
        let raster = NSGridView(views: [
            [beschriftung("Suchen:"), suchfeld],
            [beschriftung("Ersetzen durch:"), ersetzfeld],
            [beschriftung("Ordner:"), ordnerZeile],
            [beschriftung("Filter:"), filterfeld],
            [NSGridCell.emptyContentView, ordnerOptionen],
            [beschriftung("Suchmodus:"), modus],
            [NSGridCell.emptyContentView, optionen],
        ])
        raster.rowSpacing = 8
        raster.columnSpacing = 8
        raster.column(at: 0).xPlacement = .trailing
        raster.rowAlignment = .firstBaseline
        raster.column(at: 0).width = 120
        // Das Raster bleibt so hoch wie sein Inhalt; freie Höhe geht an den Platzhalter darunter.
        raster.setContentHuggingPriority(.required, for: .vertical)
        let platzhalter = NSView()
        platzhalter.setContentHuggingPriority(.init(1), for: .vertical)

        findenKnopf = NSButton(title: "Alle finden", target: self, action: #selector(finden))
        findenKnopf.keyEquivalent = "\r"
        ersetzenKnopf = NSButton(title: "In Dateien ersetzen …", target: self, action: #selector(ersetzen))
        abbrechenKnopf = NSButton(title: "Abbrechen", target: self, action: #selector(abbrechen))
        abbrechenKnopf.isEnabled = false
        anzeige.textColor = .secondaryLabelColor
        anzeige.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        anzeige.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let knoepfe = NSStackView(views: [anzeige, NSView(), abbrechenKnopf, ersetzenKnopf, findenKnopf])
        knoepfe.spacing = 8
        knoepfe.views[1].setContentHuggingPriority(.init(1), for: .horizontal)

        let stapel = NSStackView(views: [raster, platzhalter, knoepfe])
        stapel.orientation = .vertical
        stapel.alignment = .leading
        stapel.spacing = 12
        stapel.edgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        raster.trailingAnchor.constraint(equalTo: stapel.trailingAnchor, constant: -18).isActive = true
        knoepfe.trailingAnchor.constraint(equalTo: stapel.trailingAnchor, constant: -18).isActive = true
        window?.contentView = stapel
    }

    /// Öffnet das Fenster; der Ordner ist der des vorderen Dokuments, wenn noch keiner gesetzt ist.
    func zeige(ordnerVon dokument: Dokument?) {
        if ordnerfeld.stringValue.isEmpty {
            ordnerfeld.stringValue = dokument?.fileURL?.deletingLastPathComponent().path
                ?? FileManager.default.homeDirectoryForCurrentUser.path
        }
        if window?.isVisible != true { window?.center() }
        showWindow(nil)
        window?.makeFirstResponder(suchfeld)
    }

    private func uebernehme() {
        let o = SuchZustand.gemeinsam.optionen
        if !eigeneAenderung {
            if suchfeld.stringValue != o.text { suchfeld.stringValue = o.text }
            if ersetzfeld.stringValue != o.ersetzung { ersetzfeld.stringValue = o.ersetzung }
        }
        modus.selectItem(withTag: o.modus.rawValue)
        grossKlein.state = o.grossKlein ? .on : .off
        ganzesWort.state = o.ganzesWort ? .on : .off
        punkt.state = o.punktFindetZeilenende ? .on : .off
        punkt.isEnabled = o.modus == .regulaer
    }

    @objc private func optionGeaendert() {
        var o = SuchZustand.gemeinsam.optionen
        o.modus = SuchOptionen.Modus(rawValue: modus.selectedTag()) ?? .normal
        o.grossKlein = grossKlein.state == .on
        o.ganzesWort = ganzesWort.state == .on
        o.punktFindetZeilenende = punkt.state == .on
        SuchZustand.gemeinsam.optionen = o
    }

    func controlTextDidChange(_ meldung: Notification) {
        var o = SuchZustand.gemeinsam.optionen
        switch meldung.object as? NSTextField {
        case suchfeld: o.text = suchfeld.stringValue
        case ersetzfeld: o.ersetzung = ersetzfeld.stringValue
        default: return
        }
        eigeneAenderung = true
        SuchZustand.gemeinsam.optionen = o
        eigeneAenderung = false
    }

    @objc private func ordnerWaehlen() {
        let wahl = NSOpenPanel()
        wahl.canChooseDirectories = true
        wahl.canChooseFiles = false
        wahl.prompt = "Wählen"
        if !ordnerfeld.stringValue.isEmpty { wahl.directoryURL = URL(fileURLWithPath: ordnerfeld.stringValue) }
        guard let fenster = window else { return }
        wahl.beginSheetModal(for: fenster) { [weak self] antwort in
            if antwort == .OK, let url = wahl.url { self?.ordnerfeld.stringValue = url.path }
        }
    }

    // MARK: Laufen

    private func melde(_ text: String, fehler: Bool = false) {
        anzeige.stringValue = text
        anzeige.textColor = fehler ? .systemRed : .secondaryLabelColor
    }

    @objc private func finden() { starte(ersetzen: false) }
    @objc private func ersetzen() { starte(ersetzen: true) }
    @objc private func abbrechen() { abbruch?.setze() }

    /// Sucht im Hintergrund und füllt «Suchergebnisse». Mit `ersetzen` fragt es
    /// danach nach (ausser `bestaetigt`) und ersetzt. `fertig` bekommt den Satz
    /// für die Anzeige (für die Selbstprüfung).
    func starte(ersetzen: Bool, bestaetigt: Bool = false, fertig: ((String) -> Void)? = nil) {
        guard abbruch == nil else { return }
        let muster: Suchmuster
        do { muster = try SuchZustand.gemeinsam.muster() } catch {
            return melde((error as? Suchfehler)?.meldung ?? error.localizedDescription, fehler: true)
        }
        let pfad = (ordnerfeld.stringValue as NSString).expandingTildeInPath
        var istOrdner: ObjCBool = false
        guard !pfad.isEmpty, FileManager.default.fileExists(atPath: pfad, isDirectory: &istOrdner), istOrdner.boolValue
        else { return melde("Ordner nicht gefunden", fehler: true) }

        ablage.set(pfad, forKey: "DateiSucheOrdner")
        ablage.set(filterfeld.stringValue, forKey: "DateiSucheFilter")
        ablage.set(unterordner.state == .on, forKey: "DateiSucheUnterordner")
        ablage.set(versteckte.state == .on, forKey: "DateiSucheVersteckte")

        let suche = Ordnersuche(
            ordner: URL(fileURLWithPath: pfad, isDirectory: true), filter: Dateifilter(filterfeld.stringValue),
            unterordner: unterordner.state == .on, versteckte: versteckte.state == .on)
        let abbruch = Abbruch()
        self.abbruch = abbruch
        setzeLaufend(true)
        melde("Suche läuft …")

        let ergebnisse = Suchergebnisse.gemeinsam
        let liste = ergebnisse.beginne(
            Suchergebnisse.titel(muster.optionen), ort: "in \((pfad as NSString).abbreviatingWithTildeInPath)")
        liste.laeuft = true
        DispatchQueue.global(qos: .userInitiated).async {
            var gefunden: [URL] = []
            let stand = suche.durchsuche(muster, abbrechen: { abbruch.istGesetzt }) { fund in
                gefunden.append(fund.url)
                let funde = Fundzeilen.aus(fund.treffer, in: fund.text)
                DispatchQueue.main.async {
                    let name = suche.relativerPfad(fund.url)
                    ergebnisse.fuegeHinzu(
                        Suchergebnisse.Datei(name: name, url: fund.url, dokument: nil, funde: funde), zu: liste)
                }
            }
            DispatchQueue.main.async {
                ergebnisse.beende(liste)
                self.abbruch = nil
                self.setzeLaufend(false)
                var satz = "\(stand.treffer) Treffer in \(stand.dateienMitTreffern) von \(stand.geprueft) Dateien"
                if stand.uebersprungen > 0 { satz += ", \(stand.uebersprungen) übersprungen (binär oder zu gross)" }
                if stand.abgebrochen { satz += " – abgebrochen" }
                self.melde(satz)
                guard ersetzen, !stand.abgebrochen, stand.treffer > 0 else { fertig?(satz); return }
                self.frageUndErsetze(gefunden, treffer: stand.treffer, muster: muster, bestaetigt: bestaetigt, fertig: fertig)
            }
        }
    }

    private func frageUndErsetze(
        _ dateien: [URL], treffer: Int, muster: Suchmuster, bestaetigt: Bool, fertig: ((String) -> Void)?
    ) {
        let los = { self.ersetze(dateien, muster: muster, fertig: fertig) }
        guard !bestaetigt, let fenster = window else { return los() }
        let frage = NSAlert()
        frage.messageText = "\(treffer) Treffer in \(dateien.count) \(dateien.count == 1 ? "Datei" : "Dateien") ersetzen?"
        frage.informativeText = """
            Dateien, die in Kladde offen sind, ändert Kladde dort und sichert sie nicht. \
            Alle anderen schreibt Kladde sofort auf die Platte; das lässt sich nicht widerrufen.
            """
        frage.alertStyle = .warning
        frage.addButton(withTitle: "Ersetzen")
        frage.addButton(withTitle: "Abbrechen")
        frage.beginSheetModal(for: fenster) { antwort in
            if antwort == .alertFirstButtonReturn { los() } else { fertig?("nicht ersetzt") }
        }
    }

    private func ersetze(_ dateien: [URL], muster: Suchmuster, fertig: ((String) -> Void)?) {
        var offen: [Dokument] = []
        var aufPlatte: [URL] = []
        for url in dateien {
            if let dokument = NSDocumentController.shared.document(for: url) as? Dokument, dokument.editor != nil {
                offen.append(dokument)
            } else {
                aufPlatte.append(url)
            }
        }
        var anzahl = 0
        for dokument in offen {
            guard let editor = dokument.editor else { continue }
            let liste = muster.ersetzungen(in: editor.suchtext)
            editor.ersetze(liste)
            anzahl += liste.count
        }
        setzeLaufend(true)
        DispatchQueue.global(qos: .userInitiated).async {
            var fehler: [String] = []
            var geschrieben = 0
            for url in aufPlatte {
                do {
                    let n = try Ordnersuche.ersetze(in: url, mit: muster)
                    anzahl += n
                    if n > 0 { geschrieben += 1 }
                } catch {
                    fehler.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            DispatchQueue.main.async {
                self.setzeLaufend(false)
                var satz = "\(anzahl) ersetzt: \(geschrieben) Dateien geschrieben, \(offen.count) offene geändert"
                if !fehler.isEmpty { satz += ", \(fehler.count) nicht geändert" }
                self.melde(satz, fehler: !fehler.isEmpty)
                if !fehler.isEmpty, let fenster = self.window {
                    let meldung = NSAlert()
                    meldung.messageText = "\(fehler.count) \(fehler.count == 1 ? "Datei blieb" : "Dateien blieben") unverändert"
                    meldung.informativeText = fehler.prefix(12).joined(separator: "\n")
                    meldung.beginSheetModal(for: fenster)
                }
                fertig?(satz)
            }
        }
    }

    private func setzeLaufend(_ laeuft: Bool) {
        findenKnopf.isEnabled = !laeuft
        ersetzenKnopf.isEnabled = !laeuft
        abbrechenKnopf.isEnabled = laeuft && abbruch != nil
    }

    // MARK: Für die Selbstprüfung

    func setze(ordner: String, filter: String) {
        ordnerfeld.stringValue = ordner
        filterfeld.stringValue = filter
    }
}
