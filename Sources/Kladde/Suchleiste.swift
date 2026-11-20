import AppKit

/// Die Leiste zum Suchen und Ersetzen oben im Fenster. Sie ersetzt den Dialog
/// «Suchen» von Notepad++: dieselben Modi und Optionen, aber im Fenster statt
/// darüber. Text und Optionen teilen sich alle Fenster (SuchZustand).
final class Suchleiste: NSView, NSTextFieldDelegate {
    private let editor: Editor
    /// Schliessen gedrückt: Das Fenster blendet die Leiste aus.
    var schliessen: (() -> Void)?

    private let suchfeld = NSTextField()
    private let ersetzfeld = NSTextField()
    private let anzeige = NSTextField(labelWithString: "")
    private let modus = NSPopUpButton()
    private let grossKlein = NSButton(checkboxWithTitle: "Gross/klein", target: nil, action: nil)
    private let ganzesWort = NSButton(checkboxWithTitle: "Ganzes Wort", target: nil, action: nil)
    private let punkt = NSButton(checkboxWithTitle: "«.» findet Zeilenende", target: nil, action: nil)
    private let umbruch = NSButton(checkboxWithTitle: "Am Ende vorne weiter", target: nil, action: nil)
    private let nurAuswahl = NSButton(checkboxWithTitle: "Nur in Auswahl", target: nil, action: nil)
    private var ersetzZeile: NSStackView!

    private var eigeneAenderung = false
    /// Wo die Suche beim Tippen beginnt: die Auswahl beim Öffnen der Leiste.
    private var liveAb = 0
    private var beobachter: NSObjectProtocol?

    init(editor: Editor) {
        self.editor = editor
        super.init(frame: .zero)
        baue()
        uebernehme()
        beobachter = NotificationCenter.default.addObserver(
            forName: SuchZustand.geaendert, object: nil, queue: .main
        ) { [weak self] _ in self?.uebernehme() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Suchleiste entsteht nur im Code") }

    deinit {
        if let beobachter { NotificationCenter.default.removeObserver(beobachter) }
    }

    // MARK: Aufbau

    private func baue() {
        for feld in [suchfeld, ersetzfeld] {
            feld.delegate = self
            feld.bezelStyle = .roundedBezel
            feld.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            feld.lineBreakMode = .byClipping
            feld.cell?.isScrollable = true
            feld.widthAnchor.constraint(greaterThanOrEqualToConstant: 240).isActive = true
            feld.widthAnchor.constraint(lessThanOrEqualToConstant: 460).isActive = true
        }
        suchfeld.placeholderString = "Suchen"
        ersetzfeld.placeholderString = "Ersetzen durch"
        suchfeld.setAccessibilityLabel("Suchen")
        ersetzfeld.setAccessibilityLabel("Ersetzen durch")

        anzeige.textColor = .secondaryLabelColor
        anzeige.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        anzeige.lineBreakMode = .byTruncatingTail
        anzeige.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let zurueck = symbolKnopf("chevron.left", "Rückwärts suchen (⇧⌘G)", #selector(zurueckDruecken))
        let weiter = symbolKnopf("chevron.right", "Weitersuchen (⌘G)", #selector(weiterDruecken))
        let suchZeile = zeile([
            suchfeld, zurueck, weiter, anzeige, NSView(),
            knopf("Alle markieren", #selector(alleMarkieren)),
            alleFindenKnopf(),
            knopf("Fertig", #selector(fertig)),
        ])

        ersetzZeile = zeile([
            ersetzfeld,
            knopf("Ersetzen", #selector(ersetzen)),
            knopf("Alle ersetzen", #selector(alleErsetzen)),
            knopf("In allen offenen Dateien", #selector(alleErsetzenInOffenen)),
            NSView(),
        ])

        for modusWert in SuchOptionen.Modus.allCases {
            modus.addItem(withTitle: modusWert.name)
            modus.lastItem?.tag = modusWert.rawValue
        }
        modus.controlSize = .small
        modus.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        modus.target = self
        modus.action = #selector(optionGeaendert)
        for schalter in [grossKlein, ganzesWort, punkt, umbruch, nurAuswahl] {
            schalter.controlSize = .small
            schalter.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            schalter.target = self
            schalter.action = #selector(optionGeaendert)
        }
        nurAuswahl.action = nil
        nurAuswahl.toolTip = "«Alle ersetzen» und «Alle markieren» nur in der Auswahl"
        punkt.toolTip = "Nur bei «Regulärer Ausdruck»"
        let optionenZeile = zeile([modus, grossKlein, ganzesWort, umbruch, punkt, nurAuswahl, NSView()])

        let stapel = NSStackView(views: [suchZeile, ersetzZeile, optionenZeile])
        stapel.orientation = .vertical
        stapel.alignment = .leading
        stapel.spacing = 6
        stapel.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        stapel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stapel)

        let linie = NSBox()
        linie.boxType = .separator
        linie.translatesAutoresizingMaskIntoConstraints = false
        addSubview(linie)

        NSLayoutConstraint.activate([
            stapel.leadingAnchor.constraint(equalTo: leadingAnchor),
            stapel.trailingAnchor.constraint(equalTo: trailingAnchor),
            stapel.topAnchor.constraint(equalTo: topAnchor),
            stapel.bottomAnchor.constraint(equalTo: linie.topAnchor),
            linie.leadingAnchor.constraint(equalTo: leadingAnchor),
            linie.trailingAnchor.constraint(equalTo: trailingAnchor),
            linie.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        for z in [suchZeile, ersetzZeile!, optionenZeile] {
            z.trailingAnchor.constraint(equalTo: stapel.trailingAnchor, constant: -10).isActive = true
        }
    }

    private func zeile(_ ansichten: [NSView]) -> NSStackView {
        let z = NSStackView(views: ansichten)
        z.orientation = .horizontal
        z.spacing = 6
        z.alignment = .centerY
        // Der leere Platzhalter dehnt sich, damit die Knöpfe rechts stehen.
        ansichten.last(where: { type(of: $0) == NSView.self })?.setContentHuggingPriority(.init(1), for: .horizontal)
        return z
    }

    private func knopf(_ titel: String, _ aktion: Selector) -> NSButton {
        let k = NSButton(title: titel, target: self, action: aktion)
        k.controlSize = .small
        k.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        return k
    }

    private func symbolKnopf(_ symbol: String, _ hilfe: String, _ aktion: Selector) -> NSButton {
        let bild = NSImage(systemSymbolName: symbol, accessibilityDescription: hilfe) ?? NSImage()
        let k = NSButton(image: bild, target: self, action: aktion)
        k.controlSize = .small
        k.bezelStyle = .texturedRounded
        k.toolTip = hilfe
        return k
    }

    /// «Alle finden»: im Dokument oder in allen offenen Dateien, ins Fenster «Suchergebnisse».
    private func alleFindenKnopf() -> NSPopUpButton {
        let k = NSPopUpButton(frame: .zero, pullsDown: true)
        k.controlSize = .small
        k.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        k.addItem(withTitle: "Alle finden")
        let hier = NSMenuItem(title: "Im Dokument", action: #selector(alleFindenHier), keyEquivalent: "")
        let offen = NSMenuItem(title: "In allen offenen Dateien", action: #selector(alleFindenInOffenen), keyEquivalent: "")
        for eintrag in [hier, offen] {
            eintrag.target = self
            k.menu?.addItem(eintrag)
        }
        return k
    }

    // MARK: Zustand

    var ersetzenSichtbar: Bool {
        get { !ersetzZeile.isHidden }
        set { ersetzZeile.isHidden = !newValue }
    }

    /// Fokus ins Suchfeld, Text markiert; die Suche beim Tippen beginnt an der Auswahl.
    func fokussiere() {
        liveAb = editor.auswahl.lowerBound
        window?.makeFirstResponder(suchfeld)
        suchfeld.currentEditor()?.selectAll(nil)
    }

    func zeige(_ antwort: Suchaktion.Antwort) {
        anzeige.stringValue = antwort.text
        anzeige.textColor = antwort.fehler ? .systemRed : .secondaryLabelColor
    }

    /// Text und Optionen aus dem gemeinsamen Zustand (ausser in dem Feld, in dem gerade getippt wird).
    private func uebernehme() {
        let o = SuchZustand.gemeinsam.optionen
        // Ändert die Leiste den Zustand beim Tippen selbst, bleiben die Felder stehen
        // (sonst spränge die Einfügemarke). Kommt er von aussen (⌘E, andere Leiste), gilt er.
        if !eigeneAenderung {
            if suchfeld.stringValue != o.text { suchfeld.stringValue = o.text }
            if ersetzfeld.stringValue != o.ersetzung { ersetzfeld.stringValue = o.ersetzung }
        }
        modus.selectItem(withTag: o.modus.rawValue)
        grossKlein.state = o.grossKlein ? .on : .off
        ganzesWort.state = o.ganzesWort ? .on : .off
        punkt.state = o.punktFindetZeilenende ? .on : .off
        punkt.isEnabled = o.modus == .regulaer
        umbruch.state = o.umbruch ? .on : .off
    }

    @objc private func optionGeaendert() {
        var o = SuchZustand.gemeinsam.optionen
        o.modus = SuchOptionen.Modus(rawValue: modus.selectedTag()) ?? .normal
        o.grossKlein = grossKlein.state == .on
        o.ganzesWort = ganzesWort.state == .on
        o.punktFindetZeilenende = punkt.state == .on
        o.umbruch = umbruch.state == .on
        SuchZustand.gemeinsam.optionen = o
        if !o.text.isEmpty { zeige(Suchaktion.live(in: editor, ab: liveAb)) }
    }

    // MARK: Aktionen

    @objc func weiterDruecken() { zeige(Suchaktion.weiter(in: editor)) }
    @objc func zurueckDruecken() { zeige(Suchaktion.weiter(in: editor, rueckwaerts: true)) }
    @objc private func ersetzen() { zeige(Suchaktion.ersetzen(in: editor)) }
    @objc private func alleErsetzen() { zeige(Suchaktion.alleErsetzen(in: editor, nurAuswahl: nurAuswahl.state == .on)) }
    @objc private func alleErsetzenInOffenen() { zeige(Suchaktion.alleErsetzenInOffenen()) }
    @objc private func alleMarkieren() { zeige(Suchaktion.alleMarkieren(in: editor, nurAuswahl: nurAuswahl.state == .on)) }

    @objc private func alleFindenHier() {
        guard let dokument = window?.windowController?.document as? Dokument else { return }
        zeige(Suchergebnisse.gemeinsam.findeAlle(in: [dokument]))
    }

    @objc private func alleFindenInOffenen() {
        zeige(Suchergebnisse.gemeinsam.findeAlle(in: Dokumente.inTabfolge()))
    }

    @objc private func fertig() { schliessen?() }

    // MARK: NSTextFieldDelegate

    func controlTextDidChange(_ meldung: Notification) {
        var o = SuchZustand.gemeinsam.optionen
        if meldung.object as? NSTextField === suchfeld {
            o.text = suchfeld.stringValue
        } else {
            o.ersetzung = ersetzfeld.stringValue
        }
        eigeneAenderung = true
        SuchZustand.gemeinsam.optionen = o
        eigeneAenderung = false
        if meldung.object as? NSTextField === suchfeld { zeige(Suchaktion.live(in: editor, ab: liveAb)) }
    }

    /// Zeilenschalter sucht weiter (mit Umschalt rückwärts), im Ersetzfeld
    /// ersetzt er; Esc schliesst die Leiste.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy befehl: Selector) -> Bool {
        switch befehl {
        case #selector(NSResponder.insertNewline(_:)):
            let umschalt = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
            if control === ersetzfeld {
                ersetzen()
            } else if umschalt {
                zurueckDruecken()
            } else {
                weiterDruecken()
            }
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            fertig()
            return true
        default:
            return false
        }
    }
}
