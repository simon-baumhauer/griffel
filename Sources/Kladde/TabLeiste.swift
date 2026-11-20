import AppKit

/// Die Tableiste wie in Notepad++ (TabBarPlus::drawItem): aktiver Tab in der
/// Flächenfarbe mit 4 Pixel hohem Balken oben, inaktive Tabs dunkler und
/// 2 Pixel tiefer, je Tab Symbol (gesichert, geändert, schreibgeschützt),
/// Name, Pin- und Schliessknopf. Farben aus dem Farbschema (Active tab …,
/// Inactive tabs, Tab color 1–5).
final class TabLeiste: NSView {
    struct Tab {
        let titel: String
        let geaendert: Bool
        let schreibgeschuetzt: Bool
        let angeheftet: Bool
        let farbe: Int?
        let hilfe: String
    }

    // Was die Leiste von aussen braucht.
    var tabs: () -> [Tab] = { [] }
    var aktiverIndex: () -> Int? = { nil }
    var waehle: (Int) -> Void = { _ in }
    var schliesse: (Int) -> Void = { _ in }
    var heften: (Int) -> Void = { _ in }
    var verschiebe: (Int, Int) -> Void = { _, _ in }
    var neu: () -> Void = {}
    var kontextmenue: (Int) -> NSMenu? = { _ in nil }

    static let hoehe: CGFloat = 26
    private let schrift = NSFont.systemFont(ofSize: 11.5)
    private var rechtecke: [NSRect] = []
    private var versatz: CGFloat = 0
    private var ueber: Int?
    private var ueberSchliessen = false
    private var ueberPin = false
    private var gedrueckt: Int?
    private var ziehen: (index: Int, start: NSPoint, verschoben: Bool)?
    private var fokussiert = true

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        heightAnchor.constraint(equalToConstant: Self.hoehe).isActive = true
        setAccessibilityRole(.tabGroup)
        setAccessibilityLabel("Dateireiter")
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(fensterFokus), name: name, object: nil)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("TabLeiste entsteht nur im Code") }

    @objc private func fensterFokus() {
        fokussiert = window?.isKeyWindow ?? true
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self))
    }

    // MARK: Masse

    private static let symbol: CGFloat = 16
    private static let knopf: CGFloat = 13

    private func breite(_ tab: Tab) -> CGFloat {
        let text = (tab.titel as NSString).size(withAttributes: [.font: schrift]).width
        return ceil(6 + Self.symbol + 5 + text + 8 + Self.knopf + 3 + Self.knopf + 6)
    }

    private func berechne() {
        var x: CGFloat = 2 - versatz
        rechtecke = tabs().map { tab in
            let b = breite(tab)
            defer { x += b }
            return NSRect(x: x, y: 2, width: b, height: bounds.height - 2)
        }
    }

    private var ueberlauf: Bool { (rechtecke.last?.maxX ?? 0) + versatz > bounds.width - 2 }

    private func schliessRechteck(_ r: NSRect) -> NSRect {
        NSRect(x: r.maxX - 6 - Self.knopf, y: r.midY - Self.knopf / 2 + 1, width: Self.knopf, height: Self.knopf)
    }

    private func pinRechteck(_ r: NSRect) -> NSRect {
        schliessRechteck(r).offsetBy(dx: -(Self.knopf + 3), dy: 0)
    }

    // MARK: Zeichnen

    private func farbe(_ name: String, _ teil: KeyPath<Stil, Int?>, _ vorgabe: Int) -> NSColor {
        let schema = Sprachdaten.gemeinsam.farbschema(Einstellungen.schemaName(fuer: NSApp.effectiveAppearance))
        return NSColor(rgb: schema.global[name]?[keyPath: teil] ?? vorgabe)
    }

    private var dunkel: Bool { Hauptfenster.istDunkel }

    override func draw(_ dirtyRect: NSRect) {
        berechne()
        let flaeche = dunkel ? NSColor(rgb: 0x2B2B2B) : NSColor(rgb: 0xF0F0F0)
        let aktivFlaeche = dunkel ? NSColor(rgb: 0x383838) : NSColor(rgb: 0xF0F0F0)
        flaeche.setFill()
        bounds.fill()
        let liste = tabs()
        let aktiv = aktiverIndex()
        let inaktivFlaeche = dunkel ? NSColor(rgb: 0x2B2B2B) : farbe("Inactive tabs", \.hinten, 0xC0C0C0)
        let inaktivText = dunkel ? NSColor(rgb: 0xC0C0C0) : farbe("Inactive tabs", \.vorne, 0x808080)
        let aktivText = dunkel ? NSColor(rgb: 0xE0E0E0) : farbe("Active tab text", \.vorne, 0x000000)
        let balken = fokussiert
            ? farbe("Active tab focused indicator", \.vorne, 0xFAAA3C)
            : farbe("Active tab unfocused indicator", \.vorne, 0xFFCAB0)

        for (i, tab) in liste.enumerated() where i < rechtecke.count {
            var r = rechtecke[i]
            guard r.maxX > 0, r.minX < bounds.width else { continue }
            let istAktiv = i == aktiv
            let eigene = tab.farbe.map { tabFarbe($0) }
            if istAktiv {
                aktivFlaeche.setFill()
                r.fill()
                (eigene ?? balken).setFill()
                NSRect(x: r.minX, y: r.minY, width: r.width, height: 4).fill()
            } else {
                r.origin.y += 2
                r.size.height -= 2
                var f = eigene ?? inaktivFlaeche
                if ueber == i, ziehen == nil { f = f.blended(withFraction: 0.25, of: .white) ?? f }
                f.setFill()
                r.insetBy(dx: 1, dy: 0).fill()
            }
            // Trenner zwischen Tabs.
            (dunkel ? NSColor(rgb: 0x505050) : NSColor(rgb: 0xA0A0A0)).setFill()
            NSRect(x: r.maxX - 1, y: r.minY + 2, width: 1, height: r.height - 4).fill()

            // Symbol: gesichert (blau), geändert (rot), schreibgeschützt.
            let name = tab.schreibgeschuetzt ? "readonly" : (tab.geaendert ? "unsaved" : "saved")
            Symbole.tab(name, dunkel: dunkel)?.draw(
                in: NSRect(x: r.minX + 6, y: r.midY - 8, width: 16, height: 16), from: .zero, operation: .sourceOver,
                fraction: 1, respectFlipped: true, hints: nil)

            let attribute: [NSAttributedString.Key: Any] = [.font: schrift, .foregroundColor: istAktiv ? aktivText : inaktivText]
            let text = tab.titel as NSString
            let groesse = text.size(withAttributes: attribute)
            text.draw(at: NSPoint(x: r.minX + 6 + 16 + 5, y: r.midY - groesse.height / 2), withAttributes: attribute)

            // Pin- und Schliessknopf (Bilder von Notepad++).
            let pinName: String
            if tab.angeheftet {
                pinName = ueber == i && ueberPin ? "pinTabButton_pinnedHover" : "pinTabButton_pinned"
            } else {
                pinName = ueber == i && ueberPin ? "pinTabButton_hover" : "pinTabButton"
            }
            Symbole.tab(pinName, dunkel: dunkel)?.draw(
                in: pinRechteck(r), from: .zero, operation: .sourceOver, fraction: istAktiv || ueber == i ? 1 : 0.6,
                respectFlipped: true, hints: nil)
            let schliessName: String
            if ueber == i, ueberSchliessen {
                schliessName = gedrueckt == i ? "closeTabButton_push" : "closeTabButton_hoverIn"
            } else {
                schliessName = ueber == i ? "closeTabButton_hoverOnTab" : "closeTabButton"
            }
            Symbole.tab(schliessName, dunkel: dunkel)?.draw(
                in: schliessRechteck(r), from: .zero, operation: .sourceOver, fraction: istAktiv || ueber == i ? 1 : 0.6,
                respectFlipped: true, hints: nil)
        }

        // Linie unter den Tabs, ausser unter dem aktiven.
        (dunkel ? NSColor(rgb: 0x505050) : NSColor(rgb: 0xA0A0A0)).setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
        if let a = aktiv, a < rechtecke.count {
            aktivFlaeche.setFill()
            NSRect(x: rechtecke[a].minX, y: bounds.height - 1, width: rechtecke[a].width - 1, height: 1).fill()
        }

        // Pfeile bei zu vielen Tabs, wie das Windows-Steuerelement.
        if ueberlauf || versatz > 0 {
            let pfeile = NSRect(x: bounds.width - 36, y: 3, width: 36, height: bounds.height - 4)
            flaeche.setFill()
            pfeile.fill()
            for (j, zeichen) in ["◀", "▶"].enumerated() {
                let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: inaktivText]
                (zeichen as NSString).draw(at: NSPoint(x: pfeile.minX + 4 + CGFloat(j) * 17, y: pfeile.minY + 4), withAttributes: a)
            }
        }
    }

    private func tabFarbe(_ n: Int) -> NSColor {
        farbe(dunkel ? "Tab color dark mode \(n)" : "Tab color \(n)", \.hinten, 0xF3F0CB)
    }

    // MARK: Maus

    private func index(bei p: NSPoint) -> Int? {
        berechne()
        if (ueberlauf || versatz > 0), p.x > bounds.width - 36 { return nil }
        return rechtecke.firstIndex { $0.contains(p) }
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let i = index(bei: p)
        let s = i.map { schliessRechteck(rechtecke[$0]).insetBy(dx: -2, dy: -2).contains(p) } ?? false
        let pin = i.map { pinRechteck(rechtecke[$0]).insetBy(dx: -2, dy: -2).contains(p) } ?? false
        if i != ueber || s != ueberSchliessen || pin != ueberPin {
            ueber = i
            ueberSchliessen = s
            ueberPin = pin
            toolTip = i.map { tabs()[$0].hilfe }
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        ueber = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if ueberlauf || versatz > 0, p.x > bounds.width - 36 {
            rolle(nachRechts: p.x > bounds.width - 18)
            return
        }
        guard let i = index(bei: p) else {
            // Doppelklick auf freie Fläche: neues Dokument, wie in Notepad++.
            if event.clickCount == 2 { neu() }
            return
        }
        if schliessRechteck(rechtecke[i]).insetBy(dx: -2, dy: -2).contains(p) {
            gedrueckt = i
            needsDisplay = true
            return
        }
        if pinRechteck(rechtecke[i]).insetBy(dx: -2, dy: -2).contains(p) {
            heften(i)
            return
        }
        waehle(i)
        ziehen = (i, p, false)
    }

    override func mouseDragged(with event: NSEvent) {
        guard var z = ziehen else { return }
        let p = convert(event.locationInWindow, from: nil)
        if abs(p.x - z.start.x) > 4 { z.verschoben = true }
        ziehen = z
        guard z.verschoben, let ziel = index(bei: NSPoint(x: p.x, y: rechtecke.first?.midY ?? 10)), ziel != z.index else { return }
        verschiebe(z.index, ziel)
        ziehen = (ziel, p, true)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let g = gedrueckt {
            gedrueckt = nil
            if g < rechtecke.count, schliessRechteck(rechtecke[g]).insetBy(dx: -2, dy: -2).contains(p) { schliesse(g) }
            needsDisplay = true
        }
        ziehen = nil
    }

    override func otherMouseUp(with event: NSEvent) {
        // Mittlere Taste schliesst, wie in Notepad++.
        if event.buttonNumber == 2, let i = index(bei: convert(event.locationInWindow, from: nil)) { schliesse(i) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let i = index(bei: convert(event.locationInWindow, from: nil)) else { return nil }
        waehle(i)
        return kontextmenue(i)
    }

    override func scrollWheel(with event: NSEvent) {
        let d = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
        guard d != 0 else { return }
        rolle(um: -d * 3)
    }

    private func rolle(nachRechts: Bool) { rolle(um: nachRechts ? 120 : -120) }

    private func rolle(um d: CGFloat) {
        berechne()
        let gesamt = (rechtecke.last?.maxX ?? 0) + versatz + 40
        versatz = min(max(0, versatz + d), max(0, gesamt - bounds.width))
        needsDisplay = true
    }

    /// Den aktiven Tab ins Bild holen.
    func zeigeAktiven() {
        berechne()
        guard let a = aktiverIndex(), a < rechtecke.count else { needsDisplay = true; return }
        let r = rechtecke[a]
        let rechts = bounds.width - ((ueberlauf || versatz > 0) ? 40 : 4)
        if r.minX < 0 { versatz += r.minX - 2 } else if r.maxX > rechts { versatz += r.maxX - rechts }
        versatz = max(0, versatz)
        needsDisplay = true
    }
}

extension NSColor {
    convenience init(rgb: Int) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}
