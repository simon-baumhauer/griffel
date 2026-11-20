import AppKit

/// Das Fenster «Einstellungen» (⌘,). Jede Änderung gilt sofort für alle Fenster.
final class EinstellungsFenster: NSWindowController {
    static let gemeinsam = EinstellungsFenster()

    private let schrift = NSPopUpButton()
    private let groesse = NSTextField()
    private let groesseStufen = NSStepper()
    private let farbschema = NSPopUpButton()
    private let tabbreite = NSTextField()
    private let tabbreiteStufen = NSStepper()
    private let vorschlaege = NSPopUpButton()
    private var schalter: [(NSButton, ReferenceWritableKeyPath<EinstellungsFenster, Bool>)] = []

    private init() {
        let fenster = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
            styleMask: [.titled, .closable], backing: .buffered, defer: true)
        fenster.title = "Einstellungen"
        fenster.isRestorable = false
        super.init(window: fenster)
        baue()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("EinstellungsFenster entsteht nur im Code") }

    // Brücken zu den statischen Einstellungen, damit die Schalter einheitlich gehen.
    @objc dynamic var tabsAlsLeerzeichen: Bool {
        get { Einstellungen.tabsAlsLeerzeichen } set { Einstellungen.tabsAlsLeerzeichen = newValue }
    }
    @objc dynamic var zeilennummern: Bool {
        get { Einstellungen.zeilennummern } set { Einstellungen.zeilennummern = newValue }
    }
    @objc dynamic var einrueckungshilfen: Bool {
        get { Einstellungen.einrueckungshilfen } set { Einstellungen.einrueckungshilfen = newValue }
    }
    @objc dynamic var leerzeichenZeigen: Bool {
        get { Einstellungen.leerzeichenZeigen } set { Einstellungen.leerzeichenZeigen = newValue }
    }
    @objc dynamic var zeilenendenZeigen: Bool {
        get { Einstellungen.zeilenendenZeigen } set { Einstellungen.zeilenendenZeigen = newValue }
    }
    @objc dynamic var autoEinzug: Bool {
        get { Einstellungen.autoEinzug } set { Einstellungen.autoEinzug = newValue }
    }
    @objc dynamic var klammernSchliessen: Bool {
        get { Einstellungen.klammernSchliessen } set { Einstellungen.klammernSchliessen = newValue }
    }
    @objc dynamic var smartHighlighting: Bool {
        get { Einstellungen.smartHighlighting } set { Einstellungen.smartHighlighting = newValue }
    }
    @objc dynamic var sitzungMerken: Bool {
        get { Einstellungen.sitzungMerken } set { Einstellungen.sitzungMerken = newValue }
    }

    private func baue() {
        // Schriften mit fester Breite; die gewählte steht oben, falls sie fehlt.
        var namen = NSFontManager.shared.availableFontFamilies.filter { familie in
            NSFont(name: familie, size: 12)?.isFixedPitch ?? false
        }
        if !namen.contains(Einstellungen.schriftName) { namen.insert(Einstellungen.schriftName, at: 0) }
        schrift.addItems(withTitles: namen)
        schrift.selectItem(withTitle: Einstellungen.schriftName)
        schrift.target = self
        schrift.action = #selector(schriftGewaehlt)

        groesse.integerValue = Einstellungen.schriftGroesse
        groesse.widthAnchor.constraint(equalToConstant: 44).isActive = true
        groesse.target = self
        groesse.action = #selector(groesseGetippt)
        groesseStufen.minValue = 6
        groesseStufen.maxValue = 72
        groesseStufen.integerValue = Einstellungen.schriftGroesse
        groesseStufen.target = self
        groesseStufen.action = #selector(groesseGestuft)
        let groesseZeile = NSStackView(views: [groesse, groesseStufen, NSTextField(labelWithString: "Punkt")])

        farbschema.addItem(withTitle: "Automatisch (hell und dunkel)")
        farbschema.lastItem?.representedObject = ""
        farbschema.menu?.addItem(.separator())
        for name in Sprachdaten.gemeinsam.farbschemaNamen {
            farbschema.addItem(withTitle: name == "DarkModeDefault" ? "Dark Mode Default" : name)
            farbschema.lastItem?.representedObject = name
        }
        if let eintrag = farbschema.itemArray.first(where: { ($0.representedObject as? String) == Einstellungen.farbschema }) {
            farbschema.select(eintrag)
        }
        farbschema.target = self
        farbschema.action = #selector(farbschemaGewaehlt)

        tabbreite.integerValue = Einstellungen.tabbreite
        tabbreite.widthAnchor.constraint(equalToConstant: 44).isActive = true
        tabbreite.target = self
        tabbreite.action = #selector(tabbreiteGetippt)
        tabbreiteStufen.minValue = 1
        tabbreiteStufen.maxValue = 16
        tabbreiteStufen.integerValue = Einstellungen.tabbreite
        tabbreiteStufen.target = self
        tabbreiteStufen.action = #selector(tabbreiteGestuft)
        let tabZeile = NSStackView(views: [tabbreite, tabbreiteStufen, haken("Tab-Taste fügt Leerzeichen ein", \.tabsAlsLeerzeichen)])

        vorschlaege.addItem(withTitle: "Aus")
        for n in 1...5 { vorschlaege.addItem(withTitle: "ab \(n) \(n == 1 ? "Zeichen" : "Zeichen")") }
        vorschlaege.selectItem(at: Einstellungen.vervollstaendigenAb)
        vorschlaege.target = self
        vorschlaege.action = #selector(vorschlaegeGewaehlt)

        func spalte(_ titel: String) -> NSTextField {
            let f = NSTextField(labelWithString: titel)
            f.alignment = .right
            return f
        }
        let raster = NSGridView(views: [
            [spalte("Schrift:"), schrift],
            [spalte("Grösse:"), groesseZeile],
            [spalte("Farbschema:"), farbschema],
            [spalte("Tabbreite:"), tabZeile],
            [spalte("Anzeigen:"), haken("Zeilennummern", \.zeilennummern)],
            [NSGridCell.emptyContentView, haken("Einrückungshilfen", \.einrueckungshilfen)],
            [NSGridCell.emptyContentView, haken("Leerzeichen und Tabs", \.leerzeichenZeigen)],
            [NSGridCell.emptyContentView, haken("Zeilenenden", \.zeilenendenZeigen)],
            [spalte("Tippen:"), haken("Neue Zeile übernimmt die Einrückung", \.autoEinzug)],
            [NSGridCell.emptyContentView, haken("Klammern und Anführungszeichen schliessen", \.klammernSchliessen)],
            [NSGridCell.emptyContentView, haken("Ausgewähltes Wort überall hervorheben", \.smartHighlighting)],
            [spalte("Vorschläge:"), vorschlaege],
            [spalte("Beim Beenden:"), haken("Tabs merken und beim Start wieder öffnen", \.sitzungMerken)],
            [spalte("Terminal:"), terminalZeile()],
        ])
        raster.rowSpacing = 8
        raster.columnSpacing = 10
        raster.rowAlignment = .firstBaseline
        raster.column(at: 0).xPlacement = .trailing
        raster.translatesAutoresizingMaskIntoConstraints = false

        let inhalt = NSView()
        inhalt.addSubview(raster)
        NSLayoutConstraint.activate([
            raster.topAnchor.constraint(equalTo: inhalt.topAnchor, constant: 20),
            raster.leadingAnchor.constraint(equalTo: inhalt.leadingAnchor, constant: 20),
            raster.trailingAnchor.constraint(lessThanOrEqualTo: inhalt.trailingAnchor, constant: -20),
            raster.bottomAnchor.constraint(equalTo: inhalt.bottomAnchor, constant: -20),
        ])
        window?.contentView = inhalt
        // So gross wie der Inhalt, sonst verteilt das Raster die übrige Höhe auf eine Zeile.
        window?.setContentSize(inhalt.fittingSize)
    }

    private func haken(_ titel: String, _ pfad: ReferenceWritableKeyPath<EinstellungsFenster, Bool>) -> NSButton {
        let k = NSButton(checkboxWithTitle: titel, target: self, action: #selector(hakenGeaendert(_:)))
        k.state = self[keyPath: pfad] ? .on : .off
        schalter.append((k, pfad))
        return k
    }

    private func terminalZeile() -> NSView {
        let knopf = NSButton(title: "Befehl «kladde» installieren …", target: NSApp.delegate, action: #selector(AppDelegate.installiereBefehl(_:)))
        return knopf
    }

    /// Öffnet das Fenster mit den aktuellen Werten (sie können sich übers Menü geändert haben).
    func zeige() {
        for (k, pfad) in schalter { k.state = self[keyPath: pfad] ? .on : .off }
        if window?.isVisible != true { window?.center() }
        showWindow(nil)
    }

    // MARK: Aktionen

    @objc private func hakenGeaendert(_ sender: NSButton) {
        guard let (_, pfad) = schalter.first(where: { $0.0 === sender }) else { return }
        self[keyPath: pfad] = sender.state == .on
    }

    @objc private func schriftGewaehlt() {
        if let name = schrift.titleOfSelectedItem { Einstellungen.schriftName = name }
    }

    @objc private func groesseGetippt() {
        Einstellungen.schriftGroesse = groesse.integerValue
        groesse.integerValue = Einstellungen.schriftGroesse
        groesseStufen.integerValue = Einstellungen.schriftGroesse
    }

    @objc private func groesseGestuft() {
        Einstellungen.schriftGroesse = groesseStufen.integerValue
        groesse.integerValue = Einstellungen.schriftGroesse
    }

    @objc private func farbschemaGewaehlt() {
        Einstellungen.farbschema = farbschema.selectedItem?.representedObject as? String ?? ""
    }

    @objc private func tabbreiteGetippt() {
        Einstellungen.tabbreite = tabbreite.integerValue
        tabbreite.integerValue = Einstellungen.tabbreite
        tabbreiteStufen.integerValue = Einstellungen.tabbreite
    }

    @objc private func tabbreiteGestuft() {
        Einstellungen.tabbreite = tabbreiteStufen.integerValue
        tabbreite.integerValue = Einstellungen.tabbreite
    }

    @objc private func vorschlaegeGewaehlt() {
        Einstellungen.vervollstaendigenAb = vorschlaege.indexOfSelectedItem
    }
}
