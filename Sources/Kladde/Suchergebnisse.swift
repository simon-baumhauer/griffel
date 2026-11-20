import AppKit

/// Das Fenster «Suchergebnisse», wie das Ergebnisfeld von Notepad++: oben die
/// neueste Suche, darunter die älteren zugeklappt; je Suche die Dateien, je
/// Datei die Zeilen mit Treffern. Doppelklick oder Zeilenschalter springt hin.
final class Suchergebnisse: NSWindowController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    static let gemeinsam = Suchergebnisse()

    // MARK: Inhalt

    final class Suche {
        let titel: String
        let ort: String
        var dateien: [Datei] = []
        var laeuft = false
        var trefferzahl: Int { dateien.reduce(0) { $0 + $1.trefferzahl } }
        init(titel: String, ort: String) {
            self.titel = titel
            self.ort = ort
        }
    }

    final class Datei {
        let name: String
        let url: URL?
        weak var dokument: Dokument?
        private(set) var zeilen: [Zeile] = []
        var trefferzahl: Int { zeilen.reduce(0) { $0 + $1.fund.bereiche.count } }

        init(name: String, url: URL?, dokument: Dokument?, funde: [Fundzeile]) {
            self.name = name
            self.url = url
            self.dokument = dokument
            zeilen = funde.map { Zeile(fund: $0, datei: self) }
        }
    }

    final class Zeile {
        let fund: Fundzeile
        /// Die Datei hält ihre Zeilen; umgekehrt nur schwach, sonst hielten sie sich gegenseitig.
        unowned let datei: Datei
        init(fund: Fundzeile, datei: Datei) {
            self.fund = fund
            self.datei = datei
        }
    }

    private(set) var suchen: [Suche] = []
    private static let hoechstensSuchen = 10

    private let liste = NSOutlineView()

    // MARK: Fenster

    private init() {
        let fenster = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 320),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .utilityWindow],
            backing: .buffered, defer: true)
        fenster.title = "Suchergebnisse"
        fenster.setFrameAutosaveName("Suchergebnisse")
        fenster.isRestorable = false
        super.init(window: fenster)

        let spalte = NSTableColumn(identifier: .init("ergebnis"))
        spalte.resizingMask = .autoresizingMask
        liste.addTableColumn(spalte)
        liste.outlineTableColumn = spalte
        liste.headerView = nil
        liste.rowSizeStyle = .small
        liste.style = .plain
        liste.usesAlternatingRowBackgroundColors = false
        liste.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        liste.dataSource = self
        liste.delegate = self
        liste.target = self
        liste.doubleAction = #selector(springe)
        liste.setAccessibilityLabel("Suchergebnisse")

        let menue = NSMenu()
        menue.addItem(withTitle: "Alle zuklappen", action: #selector(alleZuklappen), keyEquivalent: "").target = self
        menue.addItem(withTitle: "Alle aufklappen", action: #selector(alleAufklappen), keyEquivalent: "").target = self
        menue.addItem(.separator())
        menue.addItem(withTitle: "Leeren", action: #selector(leeren), keyEquivalent: "").target = self
        liste.menu = menue

        let rollen = NSScrollView()
        rollen.documentView = liste
        rollen.hasVerticalScroller = true
        rollen.hasHorizontalScroller = true
        rollen.autohidesScrollers = true
        fenster.contentView = rollen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Suchergebnisse entsteht nur im Code") }

    // MARK: Füllen

    /// Neue Suche oben, ältere zugeklappt. Das Fenster kommt nach vorne.
    @discardableResult
    func beginne(_ titel: String, ort: String) -> Suche {
        let suche = Suche(titel: titel, ort: ort)
        suchen.insert(suche, at: 0)
        if suchen.count > Self.hoechstensSuchen { suchen.removeLast() }
        liste.reloadData()
        for alte in suchen.dropFirst() { liste.collapseItem(alte, collapseChildren: true) }
        liste.expandItem(suche)
        if window?.isVisible != true { window?.center() }
        showWindow(nil)
        return suche
    }

    func fuegeHinzu(_ datei: Datei, zu suche: Suche) {
        suche.dateien.append(datei)
        liste.reloadItem(suche, reloadChildren: true)
        if suche === suchen.first { liste.expandItem(datei) }
    }

    func beende(_ suche: Suche) {
        suche.laeuft = false
        liste.reloadItem(suche)
    }

    /// «Alle finden» in offenen Dokumenten.
    func findeAlle(in dokumente: [Dokument]) -> Suchaktion.Antwort {
        let muster: Suchmuster
        do { muster = try SuchZustand.gemeinsam.muster() } catch {
            return Suchaktion.Antwort(text: (error as? Suchfehler)?.meldung ?? "", fehler: true)
        }
        let suche = beginne(
            Self.titel(muster.optionen), ort: dokumente.count == 1 ? "im Dokument" : "in offenen Dateien")
        for dokument in dokumente {
            guard let editor = dokument.editor else { continue }
            let text = editor.suchtext
            let treffer = muster.alle(in: text)
            guard !treffer.isEmpty else { continue }
            let datei = Datei(
                name: dokument.fileURL?.path ?? dokument.displayName ?? "Ohne Titel",
                url: dokument.fileURL, dokument: dokument, funde: Fundzeilen.aus(treffer, in: text))
            fuegeHinzu(datei, zu: suche)
        }
        beende(suche)
        let anzahl = suche.trefferzahl
        return Suchaktion.Antwort(text: anzahl == 0 ? "Nicht gefunden" : "\(anzahl) Treffer gefunden", fehler: anzahl == 0)
    }

    static func titel(_ o: SuchOptionen) -> String {
        var zusatz: [String] = []
        if o.modus == .regulaer { zusatz.append("Ausdruck") }
        if o.modus == .erweitert { zusatz.append("erweitert") }
        if o.grossKlein { zusatz.append("Gross/klein") }
        if o.ganzesWort { zusatz.append("ganzes Wort") }
        return "«\(o.text)»" + (zusatz.isEmpty ? "" : " (\(zusatz.joined(separator: ", ")))")
    }

    // MARK: Springen

    @objc private func springe() {
        guard let zeile = liste.item(atRow: liste.clickedRow >= 0 ? liste.clickedRow : liste.selectedRow) as? Zeile
        else {
            if let eintrag = liste.item(atRow: liste.clickedRow) {
                liste.isItemExpanded(eintrag) ? liste.collapseItem(eintrag) : liste.expandItem(eintrag)
            }
            return
        }
        Self.oeffne(zeile.datei, bereich: zeile.fund.bereiche[0])
    }

    override func keyDown(with ereignis: NSEvent) {
        if ereignis.keyCode == 36 || ereignis.keyCode == 76 { springe() } else { super.keyDown(with: ereignis) }
    }

    /// Ins Dokument, wenn es offen ist; sonst die Datei öffnen. Dann auswählen.
    static func oeffne(_ datei: Datei, bereich: Range<Int>) {
        func zeige(_ dokument: Dokument) {
            dokument.showWindows()
            guard let fenster = dokument.windowControllers.first as? EditorFenster else { return }
            fenster.editor.waehleAus(bereich)
            fenster.window?.makeFirstResponder(fenster.editor.ansicht.content())
        }
        if let dokument = datei.dokument ?? datei.url.flatMap({ NSDocumentController.shared.document(for: $0) as? Dokument }) {
            return zeige(dokument)
        }
        guard let url = datei.url else { return NSSound.beep() }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { dokument, _, fehler in
            if let dokument = dokument as? Dokument {
                zeige(dokument)
            } else if let fehler {
                NSApp.presentError(fehler)
            }
        }
    }

    // MARK: Menü

    @objc private func alleZuklappen() { liste.collapseItem(nil, collapseChildren: true) }
    @objc private func alleAufklappen() { liste.expandItem(nil, expandChildren: true) }

    @objc private func leeren() {
        suchen.removeAll()
        liste.reloadData()
    }

    // MARK: NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        switch item {
        case nil: return suchen.count
        case let suche as Suche: return suche.dateien.count
        case let datei as Datei: return datei.zeilen.count
        default: return 0
        }
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        switch item {
        case let suche as Suche: return suche.dateien[index]
        case let datei as Datei: return datei.zeilen[index]
        default: return suchen[index]
        }
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        !(item is Zeile)
    }

    // MARK: NSOutlineViewDelegate

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let zelle = outlineView.makeView(withIdentifier: .init("zelle"), owner: self) as? NSTableCellView ?? {
            let neu = NSTableCellView()
            neu.identifier = .init("zelle")
            let feld = NSTextField(labelWithString: "")
            feld.lineBreakMode = .byTruncatingMiddle
            feld.usesSingleLineMode = true
            feld.cell?.wraps = false
            feld.maximumNumberOfLines = 1
            feld.translatesAutoresizingMaskIntoConstraints = false
            neu.addSubview(feld)
            neu.textField = feld
            NSLayoutConstraint.activate([
                feld.leadingAnchor.constraint(equalTo: neu.leadingAnchor, constant: 2),
                feld.trailingAnchor.constraint(equalTo: neu.trailingAnchor, constant: -2),
                feld.centerYAnchor.constraint(equalTo: neu.centerYAnchor),
            ])
            return neu
        }()
        zelle.textField?.attributedStringValue = text(fuer: item)
        return zelle
    }

    private func text(fuer item: Any) -> NSAttributedString {
        let klein = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let fett = NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        switch item {
        case let suche as Suche:
            // Wie Notepad++: zuerst was und wie viel, dann wo; ein langer Ort wird gekürzt.
            let dateien = suche.dateien.count
            let stand = suche.laeuft
                ? " – läuft …"
                : " – \(suche.trefferzahl) Treffer in \(dateien) \(dateien == 1 ? "Datei" : "Dateien")"
            let absatz = NSMutableParagraphStyle()
            absatz.lineBreakMode = .byTruncatingMiddle
            let s = NSMutableAttributedString(
                string: "Suche nach " + suche.titel + stand, attributes: [.font: fett, .paragraphStyle: absatz])
            s.append(NSAttributedString(
                string: "  " + suche.ort,
                attributes: [.font: klein, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: absatz]))
            return s
        case let datei as Datei:
            let s = NSMutableAttributedString(string: datei.name, attributes: [.font: fett, .foregroundColor: NSColor.labelColor])
            s.append(NSAttributedString(
                string: "  (\(datei.trefferzahl))", attributes: [.font: klein, .foregroundColor: NSColor.secondaryLabelColor]))
            return s
        case let zeile as Zeile:
            let schrift = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            let s = NSMutableAttributedString(
                string: String(format: "%6d: ", zeile.fund.nummer),
                attributes: [.font: schrift, .foregroundColor: NSColor.secondaryLabelColor])
            let inhalt = NSMutableAttributedString(
                string: zeile.fund.text, attributes: [.font: schrift, .foregroundColor: NSColor.labelColor])
            for bereich in zeile.fund.hervorhebungen {
                inhalt.addAttributes(
                    [
                        .backgroundColor: NSColor.systemYellow.withAlphaComponent(0.45),
                        .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold),
                    ], range: bereich)
            }
            s.append(inhalt)
            return s
        default:
            return NSAttributedString()
        }
    }
}
