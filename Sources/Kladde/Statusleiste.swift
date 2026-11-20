import AppKit

/// Die Statusleiste unten im Fenster, wie in Notepad++:
///
///     Python Datei │ Länge: 1’234  Zeilen: 56 │ Z: 12  S: 5  Ausw: 3 | 1 │ Windows (CRLF) │ UTF-8 │ EINF
///
/// Sprache, Zeilenende und Zeichensatz öffnen per Klick ein Menü zum Umstellen;
/// EINF/ÜB schaltet zwischen Einfügen und Überschreiben.
final class Statusleiste: NSView {
    private let sprache = Statusleiste.knopf()
    private let umfang = Statusleiste.text()
    private let position = Statusleiste.text()
    private let zeilenende = Statusleiste.knopf()
    private let kodierung = Statusleiste.knopf()
    private let modus = Statusleiste.knopf()

    /// Woher die Zahlen kommen: der Editor mit dem Fokus und sein Dokument.
    var quelle: (() -> (Editor, Dokument?)?)?

    private static let zahl: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "de_CH")
        return f
    }()

    override init(frame: NSRect) {
        super.init(frame: frame)
        sprache.action = #selector(zeigeSprachen)
        zeilenende.action = #selector(zeigeZeilenenden)
        kodierung.action = #selector(zeigeKodierungen)
        modus.action = #selector(schalteModus)
        for k in [sprache, zeilenende, kodierung, modus] { k.target = self }
        sprache.toolTip = "Sprache wählen"
        zeilenende.toolTip = "Zeilenende umstellen"
        kodierung.toolTip = "Zeichensatz umstellen"
        modus.toolTip = "Einfügen oder Überschreiben"

        let teile: [NSView] = [sprache, NSView(), umfang, trenner(), position, trenner(), zeilenende, trenner(), kodierung, trenner(), modus]
        let stapel = NSStackView(views: teile)
        stapel.spacing = 8
        stapel.edgeInsets = NSEdgeInsets(top: 2, left: 8, bottom: 2, right: 8)
        stapel.translatesAutoresizingMaskIntoConstraints = false
        teile[1].setContentHuggingPriority(.init(1), for: .horizontal)
        sprache.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        addSubview(stapel)

        let linie = NSBox()
        linie.boxType = .separator
        linie.translatesAutoresizingMaskIntoConstraints = false
        addSubview(linie)
        NSLayoutConstraint.activate([
            linie.topAnchor.constraint(equalTo: topAnchor),
            linie.leadingAnchor.constraint(equalTo: leadingAnchor),
            linie.trailingAnchor.constraint(equalTo: trailingAnchor),
            stapel.topAnchor.constraint(equalTo: linie.bottomAnchor),
            stapel.leadingAnchor.constraint(equalTo: leadingAnchor),
            stapel.trailingAnchor.constraint(equalTo: trailingAnchor),
            stapel.bottomAnchor.constraint(equalTo: bottomAnchor),
            heightAnchor.constraint(equalToConstant: 22),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Statusleiste entsteht nur im Code") }

    private static func text() -> NSTextField {
        let feld = NSTextField(labelWithString: "")
        feld.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        feld.textColor = .secondaryLabelColor
        feld.lineBreakMode = .byTruncatingTail
        return feld
    }

    private static func knopf() -> NSButton {
        let k = NSButton(title: "", target: nil, action: nil)
        k.isBordered = false
        k.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        k.contentTintColor = .secondaryLabelColor
        k.setButtonType(.momentaryChange)
        return k
    }

    private func trenner() -> NSView {
        let linie = NSBox()
        linie.boxType = .separator
        linie.heightAnchor.constraint(equalToConstant: 12).isActive = true
        return linie
    }

    // MARK: Anzeigen

    func aktualisiere() {
        guard let (editor, dokument) = quelle?() else { return }
        let s = editor.stand
        let z = { (n: Int) in Self.zahl.string(from: NSNumber(value: n)) ?? "\(n)" }
        sprache.title = editor.sprache.lang
        umfang.stringValue = "Länge: \(z(s.laenge))  Zeilen: \(z(s.zeilen))"
        var ort = "Z: \(z(s.zeile))  S: \(z(s.spalte))  Ausw: \(z(s.ausgewaehlteZeichen)) | \(z(s.ausgewaehlteZeilen))"
        if s.auswahlen > 1 { ort += "  (\(s.auswahlen) Auswahlen)" }
        position.stringValue = ort
        if let datei = dokument?.datei {
            zeilenende.title = datei.zeilenende.name
            kodierung.title = datei.kodierung.name
        }
        modus.title = s.ueberschreiben ? "ÜB" : "EINF"
    }

    // MARK: Menüs

    private func zeige(_ eintraege: [NSMenuItem], bei knopf: NSButton) {
        let menue = NSMenu()
        eintraege.forEach(menue.addItem)
        menue.popUp(positioning: nil, at: NSPoint(x: 0, y: knopf.bounds.height + 2), in: knopf)
        aktualisiere()
    }

    @objc private func zeigeSprachen() {
        zeige(Menue.sprachEintraege() + [.separator(), BenutzersprachenMenue.gemeinsam.menue()], bei: sprache)
    }
    @objc private func zeigeZeilenenden() { zeige(Menue.zeilenendeEintraege(), bei: zeilenende) }
    @objc private func zeigeKodierungen() { zeige(Menue.kodierungsEintraege(), bei: kodierung) }

    @objc private func schalteModus() {
        quelle?()?.0.schalteUeberschreiben()
        aktualisiere()
    }
}
