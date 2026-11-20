import AppKit
import ScintillaBruecke

/// Ein Andockbereich (links, rechts, unten), der Seitenleisten untereinander hält.
final class Dock: NSView {
    private let teilung = NSSplitView()
    var leerGeworden: (() -> Void)?
    var istLeer: Bool { teilung.arrangedSubviews.isEmpty }

    override init(frame: NSRect) {
        super.init(frame: frame)
        teilung.isVertical = false
        teilung.dividerStyle = .thin
        teilung.translatesAutoresizingMaskIntoConstraints = false
        addSubview(teilung)
        NSLayoutConstraint.activate([
            teilung.leadingAnchor.constraint(equalTo: leadingAnchor), teilung.trailingAnchor.constraint(equalTo: trailingAnchor),
            teilung.topAnchor.constraint(equalTo: topAnchor), teilung.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func zeige(_ leiste: Seitenleiste, an: Bool) {
        let drin = teilung.arrangedSubviews.contains(leiste)
        guard an != drin else { return }
        if an { teilung.addArrangedSubview(leiste) } else { teilung.removeArrangedSubview(leiste); leiste.removeFromSuperview() }
        leerGeworden?()
    }

    func enthaelt(_ leiste: Seitenleiste) -> Bool { teilung.arrangedSubviews.contains(leiste) }
}

/// Eine Seitenleiste mit Titelzeile und ✕ wie die Docking-Panels von Notepad++.
final class Seitenleiste: NSView {
    let titel: String
    var schliessen: (() -> Void)?
    private let kopf = NSView()

    init(titel: String, inhalt: NSView) {
        self.titel = titel
        super.init(frame: .zero)
        let beschriftung = NSTextField(labelWithString: titel)
        beschriftung.font = .systemFont(ofSize: 11)
        let zu = NSButton(title: "✕", target: nil, action: nil)
        zu.isBordered = false
        zu.font = .systemFont(ofSize: 10)
        zu.toolTip = Oberflaeche.gemeinsam.texte["close-panel-tip"] ?? "Schließen"
        zu.target = self
        zu.action = #selector(zuGedrueckt)
        let zeile = NSStackView(views: [beschriftung, NSView(), zu])
        zeile.edgeInsets = NSEdgeInsets(top: 0, left: 6, bottom: 0, right: 4)
        zeile.views[1].setContentHuggingPriority(.init(1), for: .horizontal)
        for v in [kopf, zeile, inhalt] { v.translatesAutoresizingMaskIntoConstraints = false }
        kopf.addSubview(zeile)
        addSubview(kopf)
        addSubview(inhalt)
        kopf.wantsLayer = true
        NSLayoutConstraint.activate([
            kopf.topAnchor.constraint(equalTo: topAnchor), kopf.leadingAnchor.constraint(equalTo: leadingAnchor),
            kopf.trailingAnchor.constraint(equalTo: trailingAnchor), kopf.heightAnchor.constraint(equalToConstant: 20),
            zeile.leadingAnchor.constraint(equalTo: kopf.leadingAnchor), zeile.trailingAnchor.constraint(equalTo: kopf.trailingAnchor),
            zeile.topAnchor.constraint(equalTo: kopf.topAnchor), zeile.bottomAnchor.constraint(equalTo: kopf.bottomAnchor),
            inhalt.topAnchor.constraint(equalTo: kopf.bottomAnchor), inhalt.leadingAnchor.constraint(equalTo: leadingAnchor),
            inhalt.trailingAnchor.constraint(equalTo: trailingAnchor), inhalt.bottomAnchor.constraint(equalTo: bottomAnchor),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 120), heightAnchor.constraint(greaterThanOrEqualToConstant: 60),
        ])
        faerbe()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func faerbe() {
        kopf.layer?.backgroundColor = (Hauptfenster.istDunkel ? NSColor(rgb: 0x2B2B2B) : NSColor(rgb: 0xE1E1E1)).cgColor
    }

    @objc private func zuGedrueckt() { schliessen?() }
}

/// Die Seitenleisten von Notepad++ und wann sie zu sehen sind.
final class Panels {
    static let gemeinsam = Panels()
    private var fenster: Hauptfenster { Hauptfenster.gemeinsam }
    private let o = Oberflaeche.gemeinsam

    let funktionsliste = FunktionslistenAnsicht()
    let dokumentenliste = Dokumentenliste()
    let miniatur = Miniaturansicht()
    let arbeitsbereich = Arbeitsbereich()
    private(set) lazy var funktionslisteLeiste = Seitenleiste(titel: o.texte["FunctionList.PanelTitle"] ?? "Funktionsliste", inhalt: funktionsliste)
    private(set) lazy var dokumentenlisteLeiste = Seitenleiste(titel: o.texte["DocList.PanelTitle"] ?? "Dokumentenliste", inhalt: dokumentenliste)
    private(set) lazy var miniaturLeiste = Seitenleiste(titel: o.texte["DocumentMap.PanelTitle"] ?? "Miniaturansicht", inhalt: miniatur)
    private(set) lazy var arbeitsbereichLeiste = Seitenleiste(titel: o.texte["FolderAsWorkspace.PanelTitle"] ?? "Ordner als Arbeitsbereich", inhalt: arbeitsbereich)
    private(set) lazy var jsonLeiste = Seitenleiste(titel: "JSON Viewer", inhalt: JSONAnsicht.gemeinsam)
    private var beobachter: NSObjectProtocol?
    private var geplant = false

    private init() {
        funktionsliste.springe = { [weak self] stelle in
            guard let e = self?.fenster.aktiv else { return }
            e.waehleAus(stelle..<stelle)
            e.nachricht(SCI_VERTICALCENTRECARET)
            e.ansicht.window?.makeFirstResponder(e.ansicht.content())
        }
        funktionslisteLeiste.schliessen = { Einstellungen.funktionslisteSichtbar = false }
        dokumentenlisteLeiste.schliessen = { Einstellungen.dokumentenlisteSichtbar = false }
        miniaturLeiste.schliessen = { Einstellungen.miniaturansichtSichtbar = false }
        arbeitsbereichLeiste.schliessen = { Einstellungen.arbeitsbereichSichtbar = false }
        jsonLeiste.schliessen = { Einstellungen.jsonViewerSichtbar = false }
        beobachter = NotificationCenter.default.addObserver(forName: Einstellungen.geaendert, object: nil, queue: .main) { [weak self] _ in
            self?.anwenden()
        }
    }

    /// Zeigt und verbirgt die Leisten nach den Einstellungen.
    func anwenden() {
        let f = fenster
        f.linkerDock.zeige(arbeitsbereichLeiste, an: Einstellungen.arbeitsbereichSichtbar)
        f.linkerDock.zeige(dokumentenlisteLeiste, an: Einstellungen.dokumentenlisteSichtbar)
        f.rechterDock.zeige(miniaturLeiste, an: Einstellungen.miniaturansichtSichtbar)
        f.rechterDock.zeige(funktionslisteLeiste, an: Einstellungen.funktionslisteSichtbar)
        let jsonVorher = f.rechterDock.enthaelt(jsonLeiste)
        f.rechterDock.zeige(jsonLeiste, an: Einstellungen.jsonViewerSichtbar)
        if Einstellungen.jsonViewerSichtbar, !jsonVorher { JSONAnsicht.gemeinsam.aktualisiere() }
        if Einstellungen.miniaturansichtSichtbar { miniatur.folge(f.editor) } else { miniatur.folge(nil) }
        dokumentGewechselt()
        dokumentenliste.aktualisiere()
        arbeitsbereich.aktualisiere()
    }

    func dokumentGewechselt() {
        if Einstellungen.miniaturansichtSichtbar { miniatur.folge(fenster.editor) }
        dokumentenliste.aktualisiere()
        geplant = false
        werteFunktionslisteAus()
    }

    func textGeaendert() {
        miniatur.zeichneRahmen()
        guard Einstellungen.funktionslisteSichtbar, !geplant else { return }
        geplant = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.geplant = false
            self?.werteFunktionslisteAus()
        }
    }

    private func werteFunktionslisteAus() {
        guard Einstellungen.funktionslisteSichtbar, let e = fenster.editor else { return }
        funktionsliste.aktualisiere(text: e.suchtext, sprache: e.sprache)
    }

    func tabsGeaendert() { dokumentenliste.aktualisiere() }

    func darstellungGeaendert() {
        for l in [funktionslisteLeiste, dokumentenlisteLeiste, miniaturLeiste, arbeitsbereichLeiste, jsonLeiste] { l.faerbe() }
        miniatur.darstellungGeaendert()
        Suchergebnisse.gemeinsam.darstellungGeaendert()
    }

    // MARK: Arbeitsbereich

    func arbeitsbereichHinzu(_ ordner: URL) {
        var liste = Einstellungen.arbeitsbereichOrdner
        if !liste.contains(ordner.path) { liste.append(ordner.path) }
        Einstellungen.arbeitsbereichOrdner = liste
        Einstellungen.arbeitsbereichSichtbar = true
    }

    func arbeitsbereichWaehlen() {
        guard let w = fenster.window else { return }
        let wahl = NSOpenPanel()
        wahl.canChooseDirectories = true
        wahl.canChooseFiles = false
        wahl.message = o.texte["FolderAsWorkspace.SelectFolderFromBrowserString"] ?? ""
        wahl.beginSheetModal(for: w) { [weak self] antwort in
            if antwort == .OK, let u = wahl.url { self?.arbeitsbereichHinzu(u) }
        }
    }
}

// MARK: - Dokumentenliste

/// Die Dokumentenliste von Notepad++ (Doc Switcher): Name und Erweiterung je
/// offenem Dokument, mit dem Symbol des Tabs. Ein Klick wechselt.
final class Dokumentenliste: NSScrollView, NSTableViewDataSource, NSTableViewDelegate {
    private let tabelle = NSTableView()
    private var aktualisiert = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        let o = Oberflaeche.gemeinsam
        for (id, titel, breite) in [("name", o.texte["DocList.ColumnName"] ?? "Name", 150.0), ("erw", o.texte["DocList.ColumnExt"] ?? "Erw.", 50.0)] {
            let spalte = NSTableColumn(identifier: .init(id))
            spalte.title = titel
            spalte.width = breite
            tabelle.addTableColumn(spalte)
        }
        tabelle.rowSizeStyle = .small
        tabelle.dataSource = self
        tabelle.delegate = self
        tabelle.usesAlternatingRowBackgroundColors = false
        tabelle.menu = NSMenu()
        tabelle.menu?.delegate = KontextmenueDelegat.tabmenue
        documentView = tabelle
        hasVerticalScroller = true
        autohidesScrollers = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func aktualisiere() {
        aktualisiert = true
        tabelle.reloadData()
        if let a = Hauptfenster.gemeinsam.aktivesDokument, let i = Hauptfenster.gemeinsam.tabs.firstIndex(where: { $0 === a }) {
            tabelle.selectRowIndexes([i], byExtendingSelection: false)
        }
        aktualisiert = false
    }

    func numberOfRows(in tableView: NSTableView) -> Int { Hauptfenster.gemeinsam.tabs.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let d = Hauptfenster.gemeinsam.tabs[row]
        let zelle = NSTableCellView()
        let text = NSTextField(labelWithString: "")
        text.font = .systemFont(ofSize: 11)
        text.lineBreakMode = .byTruncatingTail
        var ansichten: [NSView] = [text]
        if tableColumn?.identifier.rawValue == "name" {
            let name = d.fileURL?.deletingPathExtension().lastPathComponent ?? d.tabTitel
            text.stringValue = name
            let symbol = NSImageView(image: Symbole.tab(d.schreibgeschuetzt ? "readonly" : d.isDocumentEdited ? "unsaved" : "saved",
                                                         dunkel: Hauptfenster.istDunkel) ?? NSImage())
            symbol.widthAnchor.constraint(equalToConstant: 16).isActive = true
            ansichten.insert(symbol, at: 0)
        } else {
            text.stringValue = d.fileURL.map { $0.pathExtension.isEmpty ? "" : "." + $0.pathExtension } ?? ""
        }
        let zeile = NSStackView(views: ansichten)
        zeile.spacing = 4
        zeile.translatesAutoresizingMaskIntoConstraints = false
        zelle.addSubview(zeile)
        NSLayoutConstraint.activate([
            zeile.leadingAnchor.constraint(equalTo: zelle.leadingAnchor, constant: 2),
            zeile.trailingAnchor.constraint(lessThanOrEqualTo: zelle.trailingAnchor),
            zeile.centerYAnchor.constraint(equalTo: zelle.centerYAnchor),
        ])
        zelle.toolTip = d.fileURL?.path
        return zelle
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !aktualisiert, tabelle.selectedRow >= 0, tabelle.selectedRow < Hauptfenster.gemeinsam.tabs.count else { return }
        Hauptfenster.gemeinsam.aktiviere(Hauptfenster.gemeinsam.tabs[tabelle.selectedRow])
    }
}

/// Baut Kontextmenüs aus den Daten erst beim Öffnen.
final class KontextmenueDelegat: NSObject, NSMenuDelegate {
    static let tabmenue = KontextmenueDelegat()
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        Befehlsmenue.tabmenue().items.forEach { i in
            i.menu?.removeItem(i)
            menu.addItem(i)
        }
    }
}

// MARK: - Miniaturansicht

/// Die Miniaturansicht (Document Map) von Notepad++: derselbe Text, stark
/// verkleinert, mit einem Rahmen um den Teil, den der Editor gerade zeigt.
/// Ein Klick oder Ziehen scrollt den Editor dorthin.
final class Miniaturansicht: NSView {
    private var karte: Editor?
    private weak var vorlage: Editor?
    private let rahmen = Rahmen()

    final class Rahmen: NSView {
        var bereich = NSRect.zero
        var klick: ((CGFloat) -> Void)?
        override var isFlipped: Bool { true }
        override func draw(_ dirtyRect: NSRect) {
            NSColor(rgb: Hauptfenster.istDunkel ? 0xFFFFFF : 0xFF8000).withAlphaComponent(0.18).setFill()
            bereich.fill()
            NSColor(rgb: Hauptfenster.istDunkel ? 0xFFFFFF : 0xFF8000).withAlphaComponent(0.5).setStroke()
            NSBezierPath(rect: bereich.insetBy(dx: 0.5, dy: 0.5)).stroke()
        }
        override func mouseDown(with event: NSEvent) { klick?(convert(event.locationInWindow, from: nil).y) }
        override func mouseDragged(with event: NSEvent) { klick?(convert(event.locationInWindow, from: nil).y) }
        override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        rahmen.translatesAutoresizingMaskIntoConstraints = false
        rahmen.klick = { [weak self] y in self?.springe(zu: y) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Zeigt den Text dieses Editors (nil: nichts).
    func folge(_ e: Editor?) {
        guard e !== vorlage || karte == nil else { return zeichneRahmen() }
        karte?.ansicht.removeFromSuperview()
        rahmen.removeFromSuperview()
        karte = nil
        vorlage = e
        guard let e else { return }
        let k = Editor(teiltMit: e)
        k.istKarte = true
        k.wendeDarstellungAn()
        karte = k
        k.ansicht.translatesAutoresizingMaskIntoConstraints = false
        addSubview(k.ansicht)
        addSubview(rahmen)
        NSLayoutConstraint.activate([
            k.ansicht.leadingAnchor.constraint(equalTo: leadingAnchor), k.ansicht.trailingAnchor.constraint(equalTo: trailingAnchor),
            k.ansicht.topAnchor.constraint(equalTo: topAnchor), k.ansicht.bottomAnchor.constraint(equalTo: bottomAnchor),
            rahmen.leadingAnchor.constraint(equalTo: leadingAnchor), rahmen.trailingAnchor.constraint(equalTo: trailingAnchor),
            rahmen.topAnchor.constraint(equalTo: topAnchor), rahmen.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        DispatchQueue.main.async { [weak self] in self?.zeichneRahmen() }
    }

    func darstellungGeaendert() {
        karte?.wendeDarstellungAn()
        zeichneRahmen()
    }

    /// Der Rahmen um den sichtbaren Teil; die Karte scrollt so, dass er sichtbar bleibt.
    func zeichneRahmen() {
        guard let k = karte, let v = vorlage else { return }
        let oben = v.nachricht(SCI_GETFIRSTVISIBLELINE)
        let anzahl = v.nachricht(SCI_LINESONSCREEN)
        let hoehe = CGFloat(max(1, k.nachricht(SCI_TEXTHEIGHT, 0)))
        let kartenZeilen = k.nachricht(SCI_LINESONSCREEN)
        var kartenOben = k.nachricht(SCI_GETFIRSTVISIBLELINE)
        if oben < kartenOben || oben + anzahl > kartenOben + kartenZeilen {
            kartenOben = max(0, oben + anzahl / 2 - kartenZeilen / 2)
            k.nachricht(SCI_SETFIRSTVISIBLELINE, kartenOben)
        }
        rahmen.bereich = NSRect(x: 0, y: CGFloat(oben - kartenOben) * hoehe, width: bounds.width - 15, height: CGFloat(anzahl) * hoehe)
        rahmen.needsDisplay = true
    }

    private func springe(zu y: CGFloat) {
        guard let k = karte, let v = vorlage else { return }
        let hoehe = CGFloat(max(1, k.nachricht(SCI_TEXTHEIGHT, 0)))
        let zeile = k.nachricht(SCI_GETFIRSTVISIBLELINE) + Int(y / hoehe)
        v.nachricht(SCI_SETFIRSTVISIBLELINE, max(0, zeile - v.nachricht(SCI_LINESONSCREEN) / 2))
        zeichneRahmen()
    }
}

// MARK: - Ordner als Arbeitsbereich

/// «Ordner als Arbeitsbereich»: ein Baum der gewählten Ordner. Doppelklick öffnet.
final class Arbeitsbereich: NSScrollView, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
    final class Eintrag {
        let url: URL
        let istOrdner: Bool
        lazy var kinder: [Eintrag] = {
            let inhalt = (try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
            return inhalt.map { u in Eintrag(u, (try? u.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false) }
                .sorted { ($0.istOrdner ? 0 : 1, $0.url.lastPathComponent.lowercased()) < ($1.istOrdner ? 0 : 1, $1.url.lastPathComponent.lowercased()) }
        }()
        init(_ url: URL, _ ordner: Bool) {
            self.url = url
            istOrdner = ordner
        }
    }

    private let baum = NSOutlineView()
    private var wurzeln: [Eintrag] = []

    override init(frame: NSRect) {
        super.init(frame: frame)
        let spalte = NSTableColumn(identifier: .init("name"))
        baum.addTableColumn(spalte)
        baum.outlineTableColumn = spalte
        baum.headerView = nil
        baum.rowSizeStyle = .small
        baum.dataSource = self
        baum.delegate = self
        baum.target = self
        baum.doubleAction = #selector(oeffne)
        baum.menu = NSMenu()
        baum.menu?.delegate = self
        documentView = baum
        hasVerticalScroller = true
        autohidesScrollers = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func aktualisiere() {
        let pfade = Einstellungen.arbeitsbereichOrdner
        guard pfade != wurzeln.map(\.url.path) else { return }
        wurzeln = pfade.map { Eintrag(URL(fileURLWithPath: $0), true) }
        baum.reloadData()
        for w in wurzeln { baum.expandItem(w) }
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? Eintrag)?.kinder.count ?? wurzeln.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? Eintrag)?.kinder[index] ?? wurzeln[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { (item as? Eintrag)?.istOrdner ?? false }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let e = item as? Eintrag else { return nil }
        let zelle = NSTableCellView()
        let bild = NSImageView(image: NSWorkspace.shared.icon(forFile: e.url.path))
        bild.image?.size = NSSize(width: 16, height: 16)
        bild.widthAnchor.constraint(equalToConstant: 16).isActive = true
        let text = NSTextField(labelWithString: e.url.lastPathComponent)
        text.font = .systemFont(ofSize: 11)
        text.lineBreakMode = .byTruncatingMiddle
        let zeile = NSStackView(views: [bild, text])
        zeile.spacing = 4
        zeile.translatesAutoresizingMaskIntoConstraints = false
        zelle.addSubview(zeile)
        NSLayoutConstraint.activate([
            zeile.leadingAnchor.constraint(equalTo: zelle.leadingAnchor),
            zeile.trailingAnchor.constraint(lessThanOrEqualTo: zelle.trailingAnchor),
            zeile.centerYAnchor.constraint(equalTo: zelle.centerYAnchor),
        ])
        zelle.toolTip = e.url.path
        return zelle
    }

    private var gewaehlt: Eintrag? { baum.item(atRow: baum.clickedRow >= 0 ? baum.clickedRow : baum.selectedRow) as? Eintrag }

    @objc private func oeffne() {
        guard let e = gewaehlt, !e.istOrdner else { return }
        NSDocumentController.shared.openDocument(withContentsOf: e.url, display: true) { _, _, f in if let f { NSApp.presentError(f) } }
    }

    // Kontextmenü mit den Texten von Notepad++.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let t = { (id: Int, v: String) in Mac.text(Oberflaeche.gemeinsam.texte["FolderAsWorkspace.\(id)"] ?? v) }
        func e(_ titel: String, _ a: Selector) {
            let i = NSMenuItem(title: titel, action: a, keyEquivalent: "")
            i.target = self
            menu.addItem(i)
        }
        guard let g = gewaehlt else {
            e(t(3513, "Hinzufügen …"), #selector(hinzu))
            e(t(3512, "Alle entfernen"), #selector(alleEntfernen))
            return
        }
        if wurzeln.contains(where: { $0 === g }) { e(t(3511, "Entfernen"), #selector(entfernen)) }
        if !g.istOrdner { e(t(3515, "Öffnen"), #selector(oeffne)) }
        e(t(3514, "Durch System starten"), #selector(systemOeffnen))
        menu.addItem(.separator())
        e(t(3516, "Pfad kopieren"), #selector(pfadKopieren))
        e(t(3520, "Dateinamen kopieren"), #selector(nameKopieren))
        menu.addItem(.separator())
        e(t(3518, "Finder hier öffnen"), #selector(finder))
        e(t(3519, "Terminal hier öffnen"), #selector(terminal))
        if g.istOrdner { e(t(3517, "In Dateien suchen …"), #selector(suchen)) }
        menu.addItem(.separator())
        e(t(3513, "Hinzufügen …"), #selector(hinzu))
        e(t(3512, "Alle entfernen"), #selector(alleEntfernen))
    }

    @objc private func hinzu() { Panels.gemeinsam.arbeitsbereichWaehlen() }
    @objc private func alleEntfernen() { Einstellungen.arbeitsbereichOrdner = [] }
    @objc private func entfernen() {
        guard let g = gewaehlt else { return }
        Einstellungen.arbeitsbereichOrdner.removeAll { $0 == g.url.path }
    }
    @objc private func systemOeffnen() { if let g = gewaehlt { NSWorkspace.shared.open(g.url) } }
    @objc private func pfadKopieren() { if let g = gewaehlt { Werkzeuge.zwischenablage(g.url.path) } }
    @objc private func nameKopieren() { if let g = gewaehlt { Werkzeuge.zwischenablage(g.url.lastPathComponent) } }
    @objc private func finder() { if let g = gewaehlt { NSWorkspace.shared.activateFileViewerSelecting([g.url]) } }
    @objc private func terminal() {
        if let g = gewaehlt { Werkzeuge.terminal(in: g.istOrdner ? g.url : g.url.deletingLastPathComponent()) }
    }
    @objc private func suchen() {
        guard let g = gewaehlt else { return }
        SuchenDialog.gemeinsam.zeige(.inDateien, ordner: g.url.path)
    }
}
