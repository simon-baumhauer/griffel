import AppKit

/// Die Statusleiste von Notepad++, mit den Texten der deutschen Fassung:
///
///     Python file │ Länge: 1.234    Zeilen: 56 │ Zei: 12    Spa: 5    Pos: 34 │ Windows (CR LF) │ UTF-8 │ INS
///
/// Ein Klick auf Sprache, Zeilenende oder Kodierung öffnet das Menü dazu, auf INS/OVR schaltet um.
final class Statusleiste: NSView {
    /// Woher die Zahlen kommen: der Editor mit dem Fokus und sein Dokument.
    var quelle: (() -> (Editor, Dokument?)?)?

    private var teile: [(text: String, breite: CGFloat, klick: (() -> Void)?)] = []
    private var meldungText: String?
    /// Die Texte der Felder (für die Selbstprüfung).
    var texte: [String] { teile.map(\.text) }
    private let schrift = NSFont.systemFont(ofSize: 11)
    static let hoehe: CGFloat = 22

    private static let zahl: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "de_DE")
        return f
    }()

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        heightAnchor.constraint(equalToConstant: Self.hoehe).isActive = true
        setAccessibilityRole(.group)
        setAccessibilityLabel("Statusleiste")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Statusleiste entsteht nur im Code") }

    /// Ein kurzer Satz links (etwa «Ausdruck nicht gefunden»), bis zur nächsten Bewegung.
    func meldung(_ text: String) {
        meldungText = text.isEmpty ? nil : text
        needsDisplay = true
    }

    func aktualisiere() {
        guard let (e, d) = quelle?() else { return }
        let o = Oberflaeche.gemeinsam
        let s = e.stand
        let z = { (n: Int) in Self.zahl.string(from: NSNumber(value: n)) ?? "\(n)" }
        var ort = o.text("statusbar-Ln-Col", z(s.zeile), z(s.spalte)) + "    "
        if s.ausgewaehlteZeichen > 0 {
            ort += (o.texte["statusbar-Sel"] ?? "Asw: ") + "\(z(s.ausgewaehlteZeichen)) | \(z(s.ausgewaehlteZeilen))"
        } else {
            ort += (o.texte["statusbar-Pos"] ?? "Pos: ") + z(e.marke + 1)
        }
        let datei = d?.datei ?? Textdatei()
        let ende: String
        switch datei.zeilenende {
        case .crlf: ende = "Windows (CR LF)"
        case .lf: ende = "Unix (LF)"
        case .cr: ende = "Macintosh (CR)"
        }
        let kodierung: String
        switch datei.kodierung {
        case .utf8: kodierung = "UTF-8"
        case .utf8MitBOM: kodierung = "UTF-8-BOM"
        case .utf16BE: kodierung = "UTF-16 BE BOM"
        case .utf16LE: kodierung = "UTF-16 LE BOM"
        case .windows1252: kodierung = "ANSI"
        }
        teile = [
            (e.sprache.lang, 0, { [weak self] in self?.zeigeMenue("language", bei: 0) }),
            (o.text("statusbar-length-lines", z(s.laenge), z(s.zeilen)), 220, nil),
            (ort, 250, nil),
            (ende, 120, { [weak self] in self?.zeigeZeilenenden(bei: 3) }),
            (kodierung, 110, { [weak self] in self?.zeigeMenue("encoding", bei: 4) }),
            (s.ueberschreiben ? "OVR" : "INS", 40, { [weak self] in
                self?.quelle?()?.0.schalteUeberschreiben()
                self?.aktualisiere()
            }),
        ]
        meldungText = nil
        needsDisplay = true
    }

    private func rechtecke() -> [NSRect] {
        let fest = teile.dropFirst().reduce(0) { $0 + $1.breite }
        var x = bounds.width
        var r = [NSRect](repeating: .zero, count: teile.count)
        for i in stride(from: teile.count - 1, through: 1, by: -1) {
            x -= teile[i].breite
            r[i] = NSRect(x: x, y: 0, width: teile[i].breite, height: bounds.height)
        }
        if !teile.isEmpty { r[0] = NSRect(x: 0, y: 0, width: max(0, bounds.width - fest), height: bounds.height) }
        return r
    }

    override func draw(_ dirtyRect: NSRect) {
        let dunkel = Hauptfenster.istDunkel
        (dunkel ? NSColor(rgb: 0x202020) : NSColor(rgb: 0xF0F0F0)).setFill()
        bounds.fill()
        (dunkel ? NSColor(rgb: 0x404040) : NSColor(rgb: 0xD9D9D9)).setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
        let farbe = dunkel ? NSColor(rgb: 0xE0E0E0) : NSColor.black
        let a: [NSAttributedString.Key: Any] = [.font: schrift, .foregroundColor: farbe]
        for (i, r) in rechtecke().enumerated() {
            var text = teile[i].text
            if i == 0, let m = meldungText { text = m }
            let s = text as NSString
            let h = s.size(withAttributes: a).height
            s.draw(
                with: NSRect(x: r.minX + 6, y: (bounds.height - h) / 2 + 1, width: r.width - 10, height: h),
                options: [.truncatesLastVisibleLine, .usesLineFragmentOrigin], attributes: a)
            if i > 0 {
                (dunkel ? NSColor(rgb: 0x505050) : NSColor(rgb: 0xC0C0C0)).setFill()
                NSRect(x: r.minX, y: 4, width: 1, height: bounds.height - 7).fill()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        for (i, r) in rechtecke().enumerated() where r.contains(p) { teile[i].klick?() }
    }

    private func zeigeMenue(_ kennung: String, bei teil: Int) {
        guard let m = Oberflaeche.gemeinsam.menues.first(where: { $0.kennung == kennung }) else { return }
        let menue = NSMenu()
        if kennung == "language" {
            Menue.sprachEintraege().forEach(menue.addItem)
            menue.addItem(.separator())
            menue.addItem(BenutzersprachenMenue.gemeinsam.menue())
        } else {
            Befehlsmenue.eintraege(m.eintraege).forEach(menue.addItem)
        }
        zeige(menue, bei: teil)
    }

    private func zeigeZeilenenden(bei teil: Int) {
        let menue = NSMenu()
        for id in ["IDM_FORMAT_TODOS", "IDM_FORMAT_TOUNIX", "IDM_FORMAT_TOMAC"] {
            menue.addItem(Befehlsmenue.eintrag(id: id, titel: Oberflaeche.gemeinsam.titel(id), kuerzel: nil))
        }
        zeige(menue, bei: teil)
    }

    private func zeige(_ menue: NSMenu, bei teil: Int) {
        let r = rechtecke()[teil]
        menue.popUp(positioning: nil, at: NSPoint(x: r.minX, y: 0), in: self)
        aktualisiere()
    }
}
