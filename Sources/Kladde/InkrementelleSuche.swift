import AppKit

/// Die Leiste «Inkrementelle Suche» von Notepad++ (IDD_INCREMENT_FIND) über der
/// Statusleiste: ✕, «Suchen:», Feld, ‹ ›, Groß-/Kleinschreibung, Alle markieren,
/// Zählen und die Meldung. Sucht beim Tippen ab der Stelle, an der die Leiste aufging.
final class InkrementelleSuche: NSView, NSTextFieldDelegate {
    private var editorQuelle: () -> Editor? = { nil }
    private var editor: Editor? { editorQuelle() }
    private let feld = NSTextField()
    private let grossKlein = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let alleMarkieren = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let zaehlen = NSButton(checkboxWithTitle: "", target: nil, action: nil)
    private let meldung = NSTextField(labelWithString: "")
    private var ab = 0

    override init(frame: NSRect) {
        super.init(frame: frame)
        let o = Oberflaeche.gemeinsam
        let t = { (id: String, vorgabe: String) in o.texte["IncrementalFind.\(id)"] ?? vorgabe }
        grossKlein.title = t("1685", "Groß-/Kleinschreibung")
        alleMarkieren.title = t("1690", "Alle markieren")
        zaehlen.title = t("1691", "Zählen")
        let schliessen = NSButton(title: "✕", target: self, action: #selector(schliesse))
        let zurueck = NSButton(title: "<", target: self, action: #selector(rueckwaerts))
        let weiter = NSButton(title: ">", target: self, action: #selector(vorwaerts))
        for k in [schliessen, zurueck, weiter] {
            k.bezelStyle = .smallSquare
            k.controlSize = .small
            k.widthAnchor.constraint(equalToConstant: 24).isActive = true
        }
        for k in [grossKlein, alleMarkieren, zaehlen] {
            k.controlSize = .small
            k.target = self
            k.action = #selector(geaendert)
        }
        feld.delegate = self
        feld.controlSize = .small
        feld.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        feld.widthAnchor.constraint(equalToConstant: 260).isActive = true
        meldung.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        meldung.textColor = .secondaryLabelColor
        let beschriftung = NSTextField(labelWithString: t("1681", "Suchen:"))
        beschriftung.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        let zeile = NSStackView(views: [schliessen, beschriftung, feld, zurueck, weiter, grossKlein, alleMarkieren, zaehlen, meldung])
        zeile.spacing = 6
        zeile.edgeInsets = NSEdgeInsets(top: 3, left: 4, bottom: 3, right: 6)
        zeile.translatesAutoresizingMaskIntoConstraints = false
        addSubview(zeile)
        NSLayoutConstraint.activate([
            zeile.leadingAnchor.constraint(equalTo: leadingAnchor),
            zeile.topAnchor.constraint(equalTo: topAnchor),
            zeile.bottomAnchor.constraint(equalTo: bottomAnchor),
            zeile.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("InkrementelleSuche entsteht nur im Code") }

    override func draw(_ dirtyRect: NSRect) {
        (Hauptfenster.istDunkel ? NSColor(rgb: 0x2B2B2B) : NSColor(rgb: 0xF0F0F0)).setFill()
        bounds.fill()
        (Hauptfenster.istDunkel ? NSColor(rgb: 0x404040) : NSColor(rgb: 0xD9D9D9)).setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }

    func zeige(editor: @escaping () -> Editor?) {
        editorQuelle = editor
        isHidden = false
        ab = editor()?.auswahl.lowerBound ?? 0
        if let e = editor(), let wort = e.text(e.auswahl), !wort.isEmpty, !wort.contains("\n") { feld.stringValue = wort }
        window?.makeFirstResponder(feld)
        feld.currentEditor()?.selectAll(nil)
    }

    @objc private func schliesse() {
        isHidden = true
        editor?.loescheMarkierungen(Editor.indikatorSuche)
        if let e = editor { window?.makeFirstResponder(e.ansicht.content()) }
    }

    private func setzeOptionen() {
        var o = SuchOptionen()
        o.text = feld.stringValue
        o.grossKlein = grossKlein.state == .on
        o.umbruch = true
        SuchZustand.gemeinsam.optionen = o
    }

    @objc private func geaendert() { suche() }

    private func suche() {
        guard let e = editor else { return }
        setzeOptionen()
        let antwort = Suchaktion.live(in: e, ab: ab)
        if alleMarkieren.state == .off { e.loescheMarkierungen(Editor.indikatorSuche) }
        zeige(antwort)
    }

    private func zeige(_ antwort: Suchaktion.Antwort) {
        let o = Oberflaeche.gemeinsam
        if antwort.fehler {
            meldung.stringValue = o.texte["IncrementalFind-FSNotFound"] ?? antwort.text
            feld.backgroundColor = NSColor(rgb: 0xFF6666)
        } else {
            meldung.stringValue = zaehlen.state == .on ? antwort.text : ""
            feld.backgroundColor = .textBackgroundColor
        }
    }

    @objc private func vorwaerts() { springe(rueckwaerts: false) }
    @objc private func rueckwaerts() { springe(rueckwaerts: true) }

    private func springe(rueckwaerts: Bool) {
        guard let e = editor else { return }
        setzeOptionen()
        let antwort = Suchaktion.weiter(in: e, rueckwaerts: rueckwaerts)
        ab = e.auswahl.lowerBound
        zeige(antwort)
    }

    func controlTextDidChange(_ obj: Notification) { suche() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy befehl: Selector) -> Bool {
        switch befehl {
        case #selector(NSResponder.insertNewline(_:)):
            springe(rueckwaerts: NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            schliesse()
            return true
        default:
            return false
        }
    }
}
