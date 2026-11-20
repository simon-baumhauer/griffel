import AppKit
import ScintillaBruecke

/// Das eine Fenster von Griffel, aufgebaut wie Notepad++: Werkzeugleiste,
/// Tableiste, Editor mit Seitenleisten links und rechts, unten das
/// Suchergebnis und die inkrementelle Suche, ganz unten die Statusleiste.
///
/// Die Dokumente sind NSDocuments ohne eigenes Fenster; das Hauptfenster zeigt
/// eines davon und setzt sich dessen `document`, damit Sichern & Co. dort ankommen.
final class Hauptfenster: NSWindowController, NSWindowDelegate {
    static let gemeinsam = Hauptfenster()

    private(set) var tabs: [Dokument] = []
    private(set) var aktivesDokument: Dokument?

    /// Die Hauptansicht des aktiven Dokuments.
    var editor: Editor? { aktivesDokument?.editor }
    /// Zweite Ansicht des aktiven Dokuments (geteilte Ansicht), falls offen.
    private var zweite: [ObjectIdentifier: (editor: Editor, nebeneinander: Bool)] = [:]
    var zweiterEditor: Editor? { aktivesDokument.flatMap { zweite[ObjectIdentifier($0)]?.editor } }
    private weak var zuletztAktiv: Editor?
    /// Der Editor, auf den Befehle wirken: der mit dem Fokus.
    var aktiv: Editor? {
        if let z = zuletztAktiv, z === editor || z === zweiterEditor { return z }
        return editor
    }

    let werkzeugleiste = Werkzeugleiste()
    let tableiste = TabLeiste()
    let statusleiste = Statusleiste()
    let inkrementell = InkrementelleSuche()
    let editorBereich = NSView()
    let linkerDock = Dock()
    let rechterDock = Dock()
    let untererDock = Dock()
    private let mitte = NSSplitView()
    private let rumpf = NSSplitView()
    private var erscheinung: NSKeyValueObservation?
    private var einstellungen: NSObjectProtocol?

    static var istDunkel: Bool {
        let name = Einstellungen.schemaName(fuer: NSApp.effectiveAppearance)
        let grund = Sprachdaten.gemeinsam.farbschema(name).global["Default Style"]?.hinten ?? 0xFFFFFF
        let h = 0.299 * Double(grund >> 16 & 0xFF) + 0.587 * Double(grund >> 8 & 0xFF) + 0.114 * Double(grund & 0xFF)
        return h < 128
    }

    // MARK: Aufbau

    private init() {
        let fenster = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        fenster.minSize = NSSize(width: 560, height: 300)
        fenster.tabbingMode = .disallowed
        fenster.isRestorable = false
        fenster.collectionBehavior.insert(.fullScreenPrimary)
        super.init(window: fenster)
        fenster.delegate = self

        mitte.isVertical = true
        mitte.dividerStyle = .thin
        mitte.addArrangedSubview(editorBereich)
        rumpf.isVertical = false
        rumpf.dividerStyle = .thin
        rumpf.addArrangedSubview(mitte)
        for dock in [linkerDock, rechterDock, untererDock] {
            dock.leerGeworden = { [weak self] in self?.ordneDocks() }
        }

        let stapel = NSStackView(views: [werkzeugleiste, tableiste, rumpf, inkrementell, statusleiste])
        stapel.orientation = .vertical
        stapel.spacing = 0
        stapel.alignment = .leading
        stapel.distribution = .fill
        for v in stapel.arrangedSubviews {
            v.translatesAutoresizingMaskIntoConstraints = false
            v.widthAnchor.constraint(equalTo: stapel.widthAnchor).isActive = true
        }
        rumpf.setContentHuggingPriority(.init(1), for: .vertical)
        rumpf.setContentCompressionResistancePriority(.init(1), for: .vertical)
        inkrementell.isHidden = true
        fenster.contentView = stapel
        fenster.setFrameAutosaveName("Hauptfenster")
        if fenster.frame.origin == .zero { fenster.center() }

        verbindeLeisten()
        erscheinung = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async { self?.darstellungGeaendert() }
        }
        einstellungen = NotificationCenter.default.addObserver(
            forName: Einstellungen.geaendert, object: nil, queue: .main
        ) { [weak self] _ in
            self?.wendeModusAn()
            self?.darstellungGeaendert()
            self?.tabsGeaendert()
        }
        // Ausgeblendete Leisten, Tab-Höhe und Modus gleich beim Start. Nicht die ganze
        // Darstellung: Die Seitenleisten fragen nach Hauptfenster.gemeinsam, das hier
        // noch entsteht (rekursives dispatch_once).
        wendeModusAn()
        wendeLeistenAn()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Hauptfenster entsteht nur im Code") }

    private func verbindeLeisten() {
        werkzeugleiste.ausfuehren = { [weak self] id in self?.fuehreAus(id) }
        werkzeugleiste.zustand = { [weak self] id in self?.zustand(id) ?? (false, false) }
        tableiste.tabs = { [weak self] in
            self?.tabs.map {
                TabLeiste.Tab(
                    titel: $0.tabTitel, geaendert: $0.isDocumentEdited, schreibgeschuetzt: $0.schreibgeschuetzt,
                    angeheftet: $0.angeheftet, farbe: $0.tabFarbe, hilfe: $0.fileURL?.path ?? $0.tabTitel)
            } ?? []
        }
        tableiste.aktiverIndex = { [weak self] in
            guard let self, let a = self.aktivesDokument else { return nil }
            return self.tabs.firstIndex { $0 === a }
        }
        tableiste.waehle = { [weak self] i in
            guard let self, i < self.tabs.count else { return }
            self.aktiviere(self.tabs[i])
        }
        tableiste.schliesse = { [weak self] i in
            guard let self, i < self.tabs.count else { return }
            self.schliesse([self.tabs[i]])
        }
        tableiste.heften = { [weak self] i in
            guard let self, i < self.tabs.count else { return }
            self.heften(self.tabs[i])
        }
        tableiste.verschiebe = { [weak self] von, nach in
            guard let self else { return }
            let d = self.tabs.remove(at: von)
            self.tabs.insert(d, at: nach)
            self.ordneAngeheftete()
            self.tabsGeaendert()
        }
        tableiste.neu = { NSDocumentController.shared.newDocument(nil) }
        tableiste.kontextmenue = { _ in Befehlsmenue.tabmenue() }
        statusleiste.quelle = { [weak self] in
            guard let self, let e = self.aktiv else { return nil }
            return (e, self.aktivesDokument)
        }
    }

    // MARK: Dokumente

    /// Ein neues oder geöffnetes Dokument bekommt einen Tab und wird aktiv.
    func nimmAuf(_ dokument: Dokument) {
        guard !tabs.contains(where: { $0 === dokument }) else { return aktiviere(dokument) }
        // Ein einzelnes, leeres, unverändertes «neu 1» ersetzt Notepad++ durch die geöffnete Datei.
        if dokument.fileURL != nil, tabs.count == 1, let erster = tabs.first, erster.fileURL == nil,
            !erster.isDocumentEdited, erster.editor?.laenge == 0
        {
            tabs = [dokument]
            erster.close()
        } else {
            tabs.append(dokument)
        }
        if let e = dokument.editor { melde(e) }
        aktiviere(dokument)
        showWindow(nil)
    }

    func aktiviere(_ dokument: Dokument) {
        guard let e = dokument.editor else { return }
        aktivesDokument = dokument
        document = dokument
        zuletztAktiv = e
        zeigeEditor()
        window?.makeFirstResponder(e.ansicht.content())
        Panels.gemeinsam.dokumentGewechselt()
        tabsGeaendert()
        tableiste.zeigeAktiven()
    }

    /// Setzt Hauptansicht (und ggf. zweite Ansicht) des aktiven Dokuments in den Editorbereich.
    private func zeigeEditor() {
        editorBereich.subviews.forEach { $0.removeFromSuperview() }
        guard let dok = aktivesDokument, let e = dok.editor else { return }
        let inhalt: NSView
        if let z = zweite[ObjectIdentifier(dok)] {
            let split = NSSplitView()
            split.isVertical = z.nebeneinander
            split.dividerStyle = .thin
            e.ansicht.translatesAutoresizingMaskIntoConstraints = true
            z.editor.ansicht.translatesAutoresizingMaskIntoConstraints = true
            split.addArrangedSubview(e.ansicht)
            split.addArrangedSubview(z.editor.ansicht)
            inhalt = split
        } else {
            inhalt = e.ansicht
        }
        inhalt.translatesAutoresizingMaskIntoConstraints = false
        editorBereich.addSubview(inhalt)
        NSLayoutConstraint.activate([
            inhalt.leadingAnchor.constraint(equalTo: editorBereich.leadingAnchor),
            inhalt.trailingAnchor.constraint(equalTo: editorBereich.trailingAnchor),
            inhalt.topAnchor.constraint(equalTo: editorBereich.topAnchor),
            inhalt.bottomAnchor.constraint(equalTo: editorBereich.bottomAnchor),
        ])
        if let split = inhalt as? NSSplitView {
            split.layoutSubtreeIfNeeded()
            split.setPosition((split.isVertical ? split.bounds.width : split.bounds.height) / 2, ofDividerAt: 0)
        }
    }

    /// Geteilte Ansicht des aktiven Dokuments: nil schliesst sie.
    func teile(nebeneinander: Bool?) {
        guard let dok = aktivesDokument, let e = dok.editor else { return }
        let schluessel = ObjectIdentifier(dok)
        if let n = nebeneinander {
            let z = zweite[schluessel]?.editor ?? {
                let neu = Editor(teiltMit: e)
                melde(neu)
                neu.position = e.position
                neu.ersteZeile = e.ersteZeile
                return neu
            }()
            zweite[schluessel] = (z, n)
        } else {
            zweite[schluessel] = nil
            zuletztAktiv = e
        }
        zeigeEditor()
    }

    var geteilt: Bool { zweiterEditor != nil }

    /// Rückmeldungen eines Editors an Statusleiste, Werkzeugleiste und Seitenleisten.
    func melde(_ e: Editor) {
        e.zustandGeaendert = { [weak self, weak e] in
            guard let self else { return }
            self.statusleiste.aktualisiere()
            self.werkzeugleiste.aktualisiere()
            if let e, e === self.editor { Panels.gemeinsam.textGeaendert() }
            self.synchronisiereScrollen(von: e)
        }
        e.fokussiert = { [weak self, weak e] in
            self?.zuletztAktiv = e
            self?.statusleiste.aktualisiere()
        }
        e.spracheGewechselt = { [weak self] sprache in
            self?.zweiterEditor?.uebernimmSprache(sprache)
            Panels.gemeinsam.dokumentGewechselt()
            self?.statusleiste.aktualisiere()
        }
        e.kontextmenue = { Befehlsmenue.editormenue() }
    }

    /// Titel wie in Notepad++: «*/pfad/datei.txt - Griffel».
    func tabsGeaendert() {
        if let d = aktivesDokument {
            let name = Einstellungen.kurzerTitel ? (d.fileURL?.lastPathComponent ?? d.tabTitel) : (d.fileURL?.path ?? d.tabTitel)
            window?.title = (d.isDocumentEdited ? "*" : "") + name + " - Griffel"
        } else {
            window?.title = "Griffel"
        }
        window?.isDocumentEdited = false
        tableiste.needsDisplay = true
        statusleiste.aktualisiere()
        werkzeugleiste.aktualisiere()
        Panels.gemeinsam.tabsGeaendert()
    }

    func heften(_ dokument: Dokument) {
        dokument.angeheftet.toggle()
        ordneAngeheftete()
        tabsGeaendert()
    }

    /// Angeheftete Tabs stehen links, wie in Notepad++.
    private func ordneAngeheftete() {
        let angeheftet = tabs.filter(\.angeheftet)
        let rest = tabs.filter { !$0.angeheftet }
        tabs = angeheftet + rest
    }

    func verschiebeAktiven(nach index: Int) {
        guard let a = aktivesDokument, let i = tabs.firstIndex(where: { $0 === a }) else { return }
        tabs.remove(at: i)
        tabs.insert(a, at: min(max(0, index), tabs.count))
        ordneAngeheftete()
        tabsGeaendert()
    }

    func sortiereTabs(_ vorher: (Dokument, Dokument) -> Bool) {
        tabs.sort(by: vorher)
        ordneAngeheftete()
        tabsGeaendert()
    }

    // MARK: Schliessen

    /// Schliesst Dokumente nacheinander. Bei ungesicherten fragt Griffel wie
    /// Notepad++ mit «Speichern» (Ja, Nein, Abbruch, Ja/Nein für alle). Bleibt
    /// keines, entsteht ein leeres «neu 1» (oder Griffel endet, wenn eingestellt).
    func schliesse(_ liste: [Dokument], dann: (() -> Void)? = nil) {
        var rest = liste
        var alleJa = false, alleNein = false
        let mehrere = liste.filter(\.isDocumentEdited).count > 1
        func zu(_ d: Dokument) {
            entferne(d)
            d.close()
        }
        func weiter() {
            guard !rest.isEmpty else {
                if tabs.isEmpty {
                    if Einstellungen.letzterTabBeendet { NSApp.terminate(nil); return }
                    NSDocumentController.shared.newDocument(nil)
                }
                dann?()
                return
            }
            let d = rest.removeFirst()
            guard d.isDocumentEdited, !alleNein else { zu(d); return weiter() }
            if alleJa { return Speicherhelfer.speichere(d) { ok in if ok { zu(d); weiter() } } }
            aktiviere(d)
            switch Dialoge.speichernFrage(d, mehrere: mehrere) {
            case "IDYES": Speicherhelfer.speichere(d) { ok in if ok { zu(d); weiter() } }
            case "IDNO": zu(d); weiter()
            case "IDRETRY": alleJa = true; Speicherhelfer.speichere(d) { ok in if ok { zu(d); weiter() } }
            case "IDIGNORE": alleNein = true; zu(d); weiter()
            default: return  // Abbruch beendet die ganze Reihe
            }
        }
        weiter()
    }

    /// Nimmt einen Tab weg, ohne zu fragen (nach dem Schliessen des Dokuments).
    func entferne(_ dokument: Dokument) {
        guard let i = tabs.firstIndex(where: { $0 === dokument }) else { return }
        tabs.remove(at: i)
        zweite[ObjectIdentifier(dokument)] = nil
        if aktivesDokument === dokument {
            aktivesDokument = nil
            document = nil
            if !tabs.isEmpty { aktiviere(tabs[min(i, tabs.count - 1)]) }
        }
        tabsGeaendert()
    }

    // MARK: Fenster

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Wie Notepad++: Das Fenster schliessen heisst die App beenden.
        NSApp.terminate(nil)
        return false
    }

    func windowDidBecomeKey(_ notification: Notification) {
        tableiste.needsDisplay = true
    }

    private var angewandterModus: Int?

    /// «Dunkler Modus»: hell, dunkel oder wie macOS. Nur wenn die Einstellung wechselt,
    /// damit ein von aussen gesetztes Aussehen (Selbstprüfung) bleibt.
    private func wendeModusAn() {
        let modus = Einstellungen.modus
        guard modus != angewandterModus else { return }
        angewandterModus = modus
        NSApp.appearance = [NSAppearance(named: .aqua), NSAppearance(named: .darkAqua), nil][modus]
    }

    /// Symbol-, Tab- und Statusleiste nach «Optionen» ein- oder ausblenden.
    private func wendeLeistenAn() {
        werkzeugleiste.isHidden = Einstellungen.symbolleisteAusblenden || postIt
        statusleiste.isHidden = Einstellungen.statusleisteAusblenden || postIt
        tableiste.einstellungenGeaendert()
        tableiste.isHidden = Einstellungen.tabsAusblenden || postIt
    }

    private func darstellungGeaendert() {
        werkzeugleiste.aktualisiere()
        wendeLeistenAn()
        statusleiste.aktualisiere()
        statusleiste.needsDisplay = true
        window?.appearance = NSAppearance(named: Self.istDunkel ? .darkAqua : .aqua)
        for d in tabs { d.editor?.wendeDarstellungAn() }
        for z in zweite.values { z.editor.wendeDarstellungAn() }
        Panels.gemeinsam.darstellungGeaendert()
    }

    // MARK: Docks

    /// Docks ohne Seitenleiste fallen aus dem Fenster, Docks mit kommen hinein.
    func ordneDocks() {
        let links = !linkerDock.istLeer
        let rechts = !rechterDock.istLeer
        let unten = !untererDock.istLeer
        for v in mitte.arrangedSubviews where v !== editorBereich { mitte.removeArrangedSubview(v); v.removeFromSuperview() }
        if links { mitte.insertArrangedSubview(linkerDock, at: 0) }
        if rechts { mitte.addArrangedSubview(rechterDock) }
        for v in rumpf.arrangedSubviews where v !== mitte { rumpf.removeArrangedSubview(v); v.removeFromSuperview() }
        if unten { rumpf.addArrangedSubview(untererDock) }
        mitte.layoutSubtreeIfNeeded()
        rumpf.layoutSubtreeIfNeeded()
        let breite = mitte.bounds.width
        if links { mitte.setPosition(min(240, breite / 4), ofDividerAt: 0) }
        if rechts { mitte.setPosition(max(breite - 260, breite * 3 / 4), ofDividerAt: links ? 1 : 0) }
        if unten { rumpf.setPosition(max(rumpf.bounds.height - 200, rumpf.bounds.height * 0.6), ofDividerAt: 0) }
        for (i, v) in mitte.arrangedSubviews.enumerated() {
            mitte.setHoldingPriority(v === editorBereich ? .init(200) : .init(260), forSubviewAt: i)
        }
        if unten { rumpf.setHoldingPriority(.init(260), forSubviewAt: 1) }
    }

    // MARK: Synchrones Scrollen

    var synchronVertikal = false
    var synchronHorizontal = false
    private var synchronisiere = false
    private var letzteLage: [ObjectIdentifier: (zeile: Int, x: Int)] = [:]

    /// Wie in Notepad++: Bei geteilter Ansicht scrollt die andere Ansicht um gleich viel mit.
    private func synchronisiereScrollen(von e: Editor?) {
        guard !synchronisiere, synchronVertikal || synchronHorizontal, let e, let z = zweiterEditor,
            let a = editor
        else { return }
        let andere = e === z ? a : z
        let schluessel = ObjectIdentifier(e)
        let jetzt = (zeile: e.ersteZeile, x: e.waagrechteLage)
        defer { letzteLage[schluessel] = jetzt }
        guard let vorher = letzteLage[schluessel] else { return }
        synchronisiere = true
        if synchronVertikal, jetzt.zeile != vorher.zeile { andere.ersteZeile += jetzt.zeile - vorher.zeile }
        if synchronHorizontal, jetzt.x != vorher.x { andere.waagrechteLage += jetzt.x - vorher.x }
        letzteLage[ObjectIdentifier(andere)] = (andere.ersteZeile, andere.waagrechteLage)
        synchronisiere = false
    }
}

/// Sichert ein Dokument und meldet, ob es geklappt hat (bei neuen Dokumenten mit Sichern-Dialog).
private final class Speicherhelfer: NSObject {
    private let fertig: (Bool) -> Void
    private static var offen: [Speicherhelfer] = []

    private init(_ fertig: @escaping (Bool) -> Void) { self.fertig = fertig }

    static func speichere(_ d: Dokument, fertig: @escaping (Bool) -> Void) {
        let h = Speicherhelfer(fertig)
        offen.append(h)
        d.save(withDelegate: h, didSave: #selector(dokument(_:gesichert:kontext:)), contextInfo: nil)
    }

    @objc func dokument(_ d: NSDocument, gesichert: Bool, kontext: UnsafeMutableRawPointer?) {
        Self.offen.removeAll { $0 === self }
        fertig(gesichert)
    }
}
