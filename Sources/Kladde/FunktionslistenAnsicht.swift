import AppKit

/// Die Funktionsliste rechts im Fenster, wie das Panel «Function List» in
/// Notepad++: Klassen mit ihren Funktionen und freie Funktionen, in der
/// Reihenfolge des Textes oder alphabetisch. Ein Klick springt hin.
final class FunktionslistenAnsicht: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate {
    /// Wohin ein Klick springt (Bytes im Text).
    var springe: ((Int) -> Void)?

    private let liste = NSOutlineView()
    private let titel = NSTextField(labelWithString: "Funktionsliste")
    private let hinweis = NSTextField(wrappingLabelWithString: "")
    private let sortieren = NSButton()
    private var eintraege: [Knoten] = []
    private var alphabetisch: Bool {
        get { UserDefaults.standard.bool(forKey: "FunktionslisteAlphabetisch") }
        set { UserDefaults.standard.set(newValue, forKey: "FunktionslisteAlphabetisch") }
    }

    /// Für NSOutlineView braucht es Objekte, keine Werte.
    final class Knoten {
        let eintrag: Funktionseintrag
        let kinder: [Knoten]
        init(_ e: Funktionseintrag, alphabetisch: Bool) {
            eintrag = e
            let k = e.kinder.map { Knoten($0, alphabetisch: alphabetisch) }
            kinder = alphabetisch ? k.sorted { $0.eintrag.name.localizedCaseInsensitiveCompare($1.eintrag.name) == .orderedAscending } : k
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        titel.font = .boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        titel.textColor = .secondaryLabelColor
        sortieren.image = NSImage(systemSymbolName: "textformat.abc", accessibilityDescription: "Alphabetisch")
        sortieren.bezelStyle = .texturedRounded
        sortieren.isBordered = false
        sortieren.setButtonType(.pushOnPushOff)
        sortieren.state = alphabetisch ? .on : .off
        sortieren.toolTip = "Alphabetisch sortieren"
        sortieren.target = self
        sortieren.action = #selector(sortierenGedrueckt)
        hinweis.textColor = .secondaryLabelColor
        hinweis.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        let spalte = NSTableColumn(identifier: .init("name"))
        liste.addTableColumn(spalte)
        liste.outlineTableColumn = spalte
        liste.headerView = nil
        liste.rowSizeStyle = .small
        liste.style = .plain
        liste.dataSource = self
        liste.delegate = self
        liste.target = self
        liste.action = #selector(geklickt)
        liste.setAccessibilityLabel("Funktionsliste")

        let rollen = NSScrollView()
        rollen.documentView = liste
        rollen.hasVerticalScroller = true
        rollen.autohidesScrollers = true
        rollen.drawsBackground = true

        // Den Titel trägt die Seitenleiste; hier nur die Knöpfe, wie die Werkzeugzeile in Notepad++.
        sortieren.toolTip = Oberflaeche.gemeinsam.texte["FunctionList.SortTip"] ?? "Sortieren"
        let neu = NSButton(image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil) ?? NSImage(),
                           target: self, action: #selector(neuAuswerten))
        neu.isBordered = false
        neu.toolTip = Oberflaeche.gemeinsam.texte["FunctionList.ReloadTip"] ?? "Aktualisieren"
        let kopf = NSStackView(views: [sortieren, neu, NSView()])
        kopf.views[2].setContentHuggingPriority(.init(1), for: .horizontal)
        _ = titel
        let stapel = NSStackView(views: [kopf, hinweis, rollen])
        stapel.orientation = .vertical
        stapel.alignment = .leading
        stapel.spacing = 4
        stapel.edgeInsets = NSEdgeInsets(top: 6, left: 6, bottom: 0, right: 6)
        stapel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stapel)
        for v in [kopf, rollen, hinweis] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            v.widthAnchor.constraint(equalTo: stapel.widthAnchor, constant: -12).isActive = true
        }
        rollen.setContentHuggingPriority(.init(1), for: .vertical)
        NSLayoutConstraint.activate([
            stapel.topAnchor.constraint(equalTo: topAnchor),
            stapel.bottomAnchor.constraint(equalTo: bottomAnchor),
            stapel.leadingAnchor.constraint(equalTo: leadingAnchor),
            stapel.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("FunktionslistenAnsicht entsteht nur im Code") }

    // MARK: Füllen

    private var stand = 0

    /// Wertet im Hintergrund aus und zeigt dann. Ältere Läufe, die später fertig werden, gelten nicht.
    func aktualisiere(text: Suchtext, sprache: Sprache) {
        stand += 1
        let meiner = stand
        guard let parser = Sprachdaten.gemeinsam.funktionsliste(fuer: sprache) else {
            zeige([], hinweis: sprache.istNormalerText
                ? "Für normalen Text gibt es keine Funktionsliste."
                : "Für \(sprache.kurz) gibt es keine Funktionsliste.")
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let ergebnis = parser.eintraege(in: text)
            DispatchQueue.main.async { [weak self] in
                guard let self, meiner == self.stand else { return }
                self.zeige(ergebnis, hinweis: ergebnis.isEmpty ? "Keine Funktionen gefunden." : nil)
            }
        }
    }

    private var roh: [Funktionseintrag] = []

    private func zeige(_ neu: [Funktionseintrag], hinweis text: String?) {
        roh = neu
        hinweis.stringValue = text ?? ""
        hinweis.isHidden = text == nil
        let knoten = neu.map { Knoten($0, alphabetisch: alphabetisch) }
        eintraege = alphabetisch
            ? knoten.sorted { $0.eintrag.name.localizedCaseInsensitiveCompare($1.eintrag.name) == .orderedAscending } : knoten
        liste.reloadData()
        liste.expandItem(nil, expandChildren: true)
    }

    var anzahl: Int { roh.reduce(0) { $0 + 1 + $1.kinder.count } }
    var namen: [String] { roh.flatMap { [$0.name] + $0.kinder.map { "  " + $0.name } } }

    @objc private func neuAuswerten() { Panels.gemeinsam.dokumentGewechselt() }

    @objc private func sortierenGedrueckt() {
        alphabetisch = sortieren.state == .on
        zeige(roh, hinweis: hinweis.isHidden ? nil : hinweis.stringValue)
    }

    @objc private func geklickt() {
        guard let k = liste.item(atRow: liste.clickedRow) as? Knoten else { return }
        springe?(k.eintrag.stelle)
    }

    // MARK: NSOutlineView

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? Knoten)?.kinder.count ?? eintraege.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? Knoten)?.kinder[index] ?? eintraege[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        !((item as? Knoten)?.kinder.isEmpty ?? true)
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let k = item as? Knoten else { return nil }
        let zelle = NSTableCellView()
        let symbol = NSImageView(image: NSImage(
            systemSymbolName: k.kinder.isEmpty ? "f.cursive" : "cube", accessibilityDescription: nil) ?? NSImage())
        symbol.contentTintColor = k.kinder.isEmpty ? .systemBlue : .systemPurple
        let name = NSTextField(labelWithString: k.eintrag.name)
        name.font = .monospacedSystemFont(ofSize: 11, weight: k.kinder.isEmpty ? .regular : .semibold)
        name.lineBreakMode = .byTruncatingTail
        let zeile = NSStackView(views: [symbol, name])
        zeile.spacing = 4
        zeile.translatesAutoresizingMaskIntoConstraints = false
        zelle.addSubview(zeile)
        zelle.textField = name
        NSLayoutConstraint.activate([
            zeile.leadingAnchor.constraint(equalTo: zelle.leadingAnchor),
            zeile.trailingAnchor.constraint(lessThanOrEqualTo: zelle.trailingAnchor),
            zeile.centerYAnchor.constraint(equalTo: zelle.centerYAnchor),
            symbol.widthAnchor.constraint(equalToConstant: 14),
        ])
        return zelle
    }
}
