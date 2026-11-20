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

    /// Höhe der Leiste: Tabs 22 Pixel («Verkleinern», Vorgabe) oder 25, dazu Rand.
    static var hoehe: CGFloat { Einstellungen.tabsVerkleinert ? 26 : 29 }
    private var schrift: NSFont { .systemFont(ofSize: Einstellungen.tabsVerkleinert ? 11.5 : 12.5) }
    private var rechtecke: [NSRect] = []
    private var versatz: CGFloat = 0
    private var ueber: Int?
    private var ueberSchliessen = false
    private var ueberPin = false
    private var gedrueckt: Int?
    private var pinGedrueckt: Int?
    private var ziehen: (index: Int, start: NSPoint, verschoben: Bool)?
    private var fokussiert = true
    private var hoehenBedingung: NSLayoutConstraint!

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        hoehenBedingung = heightAnchor.constraint(equalToConstant: Self.hoehe)
        hoehenBedingung.isActive = true
        setAccessibilityRole(.tabGroup)
        setAccessibilityLabel("Dateireiter")
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(fensterFokus), name: name, object: nil)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("TabLeiste entsteht nur im Code") }

    /// Nach einer Änderung in «Optionen → Dateireiter».
    func einstellungenGeaendert() {
        hoehenBedingung.constant = Self.hoehe
        isHidden = Einstellungen.tabsAusblenden
        needsDisplay = true
        zeigeAktiven()
    }

    @objc private func fensterFokus() {
        fokussiert = window?.isKeyWindow ?? true
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        // Auch wenn ein Dialog vorne ist, reagiert die Leiste auf die Maus (wie unter Windows).
        addTrackingArea(NSTrackingArea(
            rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self))
    }

    // MARK: Masse (TabButtonZone::getButtonRectFrom)

    private static let symbol: CGFloat = 16
    /// Knöpfe: hell 11, dunkel 16 Pixel (g_TabCloseBtnSize, g_TabCloseBtnSize_DM).
    private var knopf: CGFloat { dunkel ? 16 : 11 }
    /// Abstand zwischen Pin und Kreuz: hell 8, dunkel 4.
    private var zwischen: CGFloat { dunkel ? 4 : 8 }
    private var tabHoehe: CGFloat { Einstellungen.tabsVerkleinert ? 22 : 25 }
    private var knopfZone: CGFloat {
        let anzahl = (Einstellungen.tabSchliessen ? 1 : 0) + (Einstellungen.tabPin ? 1 : 0)
        let rand = (tabHoehe - knopf + 1) / 2
        return anzahl == 0 ? 6 : rand + CGFloat(anzahl) * knopf + CGFloat(anzahl - 1) * zwischen + 2
    }

    /// Der Name im Tab, gekürzt auf «Max. Länge von Tab-Namen».
    private func beschriftung(_ tab: Tab) -> String {
        let n = Einstellungen.tabNameMax
        guard n > 0, tab.titel.count > n else { return tab.titel }
        return String(tab.titel.prefix(n)) + "…"
    }

    private func breite(_ tab: Tab) -> CGFloat {
        let text = (beschriftung(tab) as NSString).size(withAttributes: [.font: schrift]).width
        let rand = (tabHoehe - Self.symbol + 1) / 2
        return ceil(rand + Self.symbol + 5 + text + 8 + knopfZone)
    }

    private func berechne() {
        var x: CGFloat = 2 - versatz
        let h = tabHoehe
        rechtecke = tabs().map { tab in
            let b = breite(tab)
            defer { x += b }
            return NSRect(x: x, y: bounds.height - h - 1, width: b, height: h)
        }
    }

    private var ueberlauf: Bool { (rechtecke.last?.maxX ?? 0) + versatz > bounds.width - 2 }

    private func schliessRechteck(_ r: NSRect) -> NSRect {
        let rand = (r.height - knopf + 1) / 2
        return NSRect(x: r.maxX - rand - knopf, y: r.minY + rand, width: knopf, height: knopf)
    }

    private func pinRechteck(_ r: NSRect) -> NSRect {
        // Ohne Kreuz rückt der Pin an seine Stelle (Reihenfolge 0).
        Einstellungen.tabSchliessen ? schliessRechteck(r).offsetBy(dx: -(knopf + zwischen), dy: 0) : schliessRechteck(r)
    }

    private func trifftSchliessen(_ i: Int, _ p: NSPoint) -> Bool {
        Einstellungen.tabSchliessen && schliessRechteck(rechtecke[i]).insetBy(dx: -2, dy: -2).contains(p)
    }

    private func trifftPin(_ i: Int, _ p: NSPoint) -> Bool {
        Einstellungen.tabPin && pinRechteck(rechtecke[i]).insetBy(dx: -2, dy: -2).contains(p)
    }

    // MARK: Zeichnen

    private func farbe(_ name: String, _ teil: KeyPath<Stil, Int?>, _ vorgabe: Int) -> NSColor {
        let schema = Sprachdaten.gemeinsam.farbschema(Einstellungen.schemaName(fuer: NSApp.effectiveAppearance))
        return NSColor(rgb: schema.global[name]?[keyPath: teil] ?? vorgabe)
    }

    private var dunkel: Bool { Hauptfenster.istDunkel }

    override func draw(_ dirtyRect: NSRect) {
        berechne()
        // Farben wie TabBarPlus::drawItem: hell COLOR_BTNFACE, dunkel die Töne von NppDarkMode.
        let flaeche = dunkel ? NSColor(rgb: 0x202020) : NSColor(rgb: 0xF0F0F0)
        let aktivFlaeche = dunkel ? NSColor(rgb: 0x383838) : NSColor(rgb: 0xF0F0F0)
        flaeche.setFill()
        bounds.fill()
        let liste = tabs()
        let aktiv = aktiverIndex()
        let inaktivFlaeche = !Einstellungen.tabInaktivFarbe ? aktivFlaeche
            : dunkel ? NSColor(rgb: 0x202020) : farbe("Inactive tabs", \.hinten, 0xC0C0C0)
        let inaktivText = dunkel ? NSColor(rgb: 0xC0C0C0) : farbe("Inactive tabs", \.vorne, 0x808080)
        let aktivText = dunkel ? NSColor(rgb: 0xE0E0E0) : farbe("Active tab text", \.vorne, 0x000000)
        let balken = fokussiert
            ? farbe("Active tab focused indicator", \.vorne, 0xFAAA3C)
            : farbe("Active tab unfocused indicator", \.vorne, 0xFAD296)
        let linie = dunkel ? NSColor(rgb: 0x505050) : NSColor(rgb: 0xA0A0A0)

        // Linie unter den Tabs; der aktive Tab überdeckt sie.
        linie.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()

        for (i, tab) in liste.enumerated() where i < rechtecke.count {
            var r = rechtecke[i]
            guard r.maxX > 0, r.minX < bounds.width else { continue }
            let istAktiv = i == aktiv
            let istUeber = ueber == i && ziehen == nil
            let eigene = tab.farbe.map { tabFarbe($0) }
            if istAktiv {
                // Der aktive Tab ist 2 Pixel höher und deckt die Linie darunter.
                r = NSRect(x: r.minX, y: r.minY - 2, width: r.width, height: r.height + 3)
                aktivFlaeche.setFill()
                r.fill()
                if Einstellungen.tabBalken {
                    (eigene ?? balken).setFill()
                    NSRect(x: r.minX, y: r.minY, width: r.width, height: 4).fill()
                }
                linie.setFill()
                NSRect(x: r.minX, y: r.minY, width: 1, height: r.height - 1).fill()
                NSRect(x: r.maxX - 1, y: r.minY, width: 1, height: r.height - 1).fill()
            } else {
                var f = eigene ?? inaktivFlaeche
                // Überfahren hellt einen dunkleren inaktiven Tab etwas auf.
                if istUeber { f = f.blended(withFraction: 0.3, of: dunkel ? .white : NSColor(rgb: 0xFFFFFF)) ?? f }
                f.setFill()
                r.fill()
                linie.setFill()
                NSRect(x: r.maxX - 1, y: r.minY + 3, width: 1, height: r.height - 6).fill()
            }
            r.size.height = istAktiv ? r.height - 1 : r.height

            // Symbol: gesichert, geändert, schreibgeschützt; inaktive Tabs leicht abgeblendet (ILD_SELECTED).
            let alt = Einstellungen.tabAlternativeSymbole && !dunkel ? "_alt" : ""
            let name = (tab.schreibgeschuetzt ? "readonly" : (tab.geaendert ? "unsaved" : "saved")) + alt
            let rand = (rechtecke[i].height - Self.symbol + 1) / 2
            let symbolRechteck = NSRect(x: r.minX + rand, y: rechtecke[i].minY + rand + (istAktiv ? -1 : 0), width: 16, height: 16)
            if let bild = Symbole.tab(name, dunkel: dunkel) ?? Symbole.tab(String(name.dropLast(alt.count)), dunkel: dunkel) {
                bild.draw(in: symbolRechteck, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                if !istAktiv {
                    Symbole.abgeblendet(bild).draw(in: symbolRechteck, from: .zero, operation: .sourceOver, fraction: 0.5,
                                                   respectFlipped: true, hints: nil)
                }
            }

            let attribute: [NSAttributedString.Key: Any] = [.font: schrift, .foregroundColor: istAktiv ? aktivText : inaktivText]
            let text = beschriftung(tab) as NSString
            let groesse = text.size(withAttributes: attribute)
            let textY = rechtecke[i].midY - groesse.height / 2 + (istAktiv && Einstellungen.tabBalken ? 0 : 0) + (istAktiv ? -1 : 0)
            text.draw(at: NSPoint(x: symbolRechteck.maxX + 5, y: textY), withAttributes: attribute)

            // Kreuz und Pin nach TabBarPlus::drawItem: auf dem aktiven Tab immer, auf
            // inaktiven nur beim Überfahren (oder mit «Schaltflächen auf inaktiven Tabs»).
            let zone = rechtecke[i].offsetBy(dx: 0, dy: istAktiv ? -1 : 0)
            if Einstellungen.tabSchliessen, let n = schliessName(i, istAktiv: istAktiv, istUeber: istUeber) {
                Symbole.tab(n, dunkel: dunkel)?.draw(in: schliessRechteck(zone), from: .zero, operation: .sourceOver,
                                                    fraction: 1, respectFlipped: true, hints: nil)
            }
            if Einstellungen.tabPin, let n = pinName(i, tab: tab, istAktiv: istAktiv, istUeber: istUeber) {
                Symbole.tab(n, dunkel: dunkel)?.draw(in: pinRechteck(zone), from: .zero, operation: .sourceOver,
                                                    fraction: 1, respectFlipped: true, hints: nil)
            }
        }

        // Pfeile bei zu vielen Tabs, wie das Windows-Steuerelement.
        if ueberlauf || versatz > 0 {
            let pfeile = NSRect(x: bounds.width - 36, y: 3, width: 36, height: bounds.height - 4)
            flaeche.setFill()
            pfeile.fill()
            for (j, zeichen) in ["◀", "▶"].enumerated() {
                let a: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: inaktivText]
                (zeichen as NSString).draw(at: NSPoint(x: pfeile.minX + 4 + CGFloat(j) * 17, y: pfeile.minY + 6), withAttributes: a)
            }
        }
    }

    /// Welches Kreuz (Notepad_plus.rc: IDR_CLOSETAB …): nil heisst keines.
    private func schliessName(_ i: Int, istAktiv: Bool, istUeber: Bool) -> String? {
        if istUeber, ueberSchliessen { return gedrueckt == i ? "closeTabButton_push" : "closeTabButton_hoverIn" }
        if istAktiv { return "closeTabButton" }
        if istUeber { return "closeTabButton_hoverOnTab" }
        // IDR_CLOSETAB_INACT: hell das blasse, dunkel das normale Kreuz.
        return Einstellungen.tabKnoepfeInaktiv ? (dunkel ? "closeTabButton" : "closeTabButton_hoverOnTab") : nil
    }

    /// Welcher Pin (IDR_PINTAB …): Überfahren zeigt, was ein Klick bewirkt.
    private func pinName(_ i: Int, tab: Tab, istAktiv: Bool, istUeber: Bool) -> String? {
        let aufPin = istUeber && ueberPin
        if tab.angeheftet { return aufPin ? "pinTabButton" : "pinTabButton_pinned" }
        if Einstellungen.tabNurAngeheftete && !aufPin { return nil }
        if aufPin { return "pinTabButton_pinned" }
        if istAktiv || istUeber || Einstellungen.tabKnoepfeInaktiv { return "pinTabButton" }
        return nil
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
        let s = i.map { trifftSchliessen($0, p) } ?? false
        let pin = i.map { trifftPin($0, p) } ?? false
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
        ueberSchliessen = false
        ueberPin = false
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
        if trifftSchliessen(i, p) {
            gedrueckt = i
            needsDisplay = true
            return
        }
        if trifftPin(i, p) {
            pinGedrueckt = i
            return
        }
        // «Tabs per Doppelklick schließen».
        if event.clickCount == 2, Einstellungen.tabDoppelklickSchliesst {
            schliesse(i)
            return
        }
        waehle(i)
        if !Einstellungen.tabsSperren { ziehen = (i, p, false) }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if gedrueckt != nil {
            // Über dem Kreuz bleibt es gedrückt, daneben nicht (wie ein Windows-Knopf).
            let vorher = ueberSchliessen
            ueberSchliessen = gedrueckt.map { $0 < rechtecke.count && trifftSchliessen($0, p) } ?? false
            if vorher != ueberSchliessen { needsDisplay = true }
            return
        }
        guard var z = ziehen else { return }
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
            needsDisplay = true
            // Geschlossen wird erst beim Loslassen über dem Kreuz.
            if g < rechtecke.count, trifftSchliessen(g, p) { schliesse(g) }
        }
        if let g = pinGedrueckt {
            pinGedrueckt = nil
            if g < rechtecke.count, trifftPin(g, p) { heften(g) }
            needsDisplay = true
        }
        ziehen = nil
    }

    override func otherMouseUp(with event: NSEvent) {
        // Mittlere Taste schliesst, wie in Notepad++.
        // Ein Ereignis ohne Fenster trägt Bildschirmkoordinaten.
        let p = event.window != nil || window == nil ? convert(event.locationInWindow, from: nil)
            : convert(window!.convertPoint(fromScreen: event.locationInWindow), from: nil)
        if event.buttonNumber == 2, let i = index(bei: p) { schliesse(i) }
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

    /// Wo jeder Tab ohne Verschiebung beginnt; verschoben wird immer um ganze Tabs,
    /// wie im Tab-Control von Windows, damit links nie ein halber Tab steht.
    private var anfaenge: [CGFloat] {
        var x: CGFloat = 0
        return tabs().map { t in defer { x += breite(t) }; return x }
    }

    private var gesamtbreite: CGFloat { tabs().reduce(0) { $0 + breite($1) } + 4 }

    /// Der grösste sinnvolle Versatz: der kleinste Tab-Anfang, ab dem der Rest ganz passt.
    private var groessterVersatz: CGFloat {
        let platz = bounds.width - 40
        guard gesamtbreite > bounds.width - 4 else { return 0 }
        return anfaenge.first { gesamtbreite - $0 <= platz } ?? (anfaenge.last ?? 0)
    }

    private func rolle(nachRechts: Bool) {
        let a = anfaenge
        let i = a.lastIndex { $0 <= versatz + 0.5 } ?? 0
        let ziel = nachRechts ? a[min(i + 1, a.count - 1)] : a[max(i - 1, 0)]
        versatz = min(ziel, groessterVersatz)
        needsDisplay = true
    }

    private func rolle(um d: CGFloat) {
        // Mausrad: weich mitzählen, dann auf den nächsten Tab einrasten.
        rad += d
        guard abs(rad) >= 40 else { return }
        rolle(nachRechts: rad > 0)
        rad = 0
    }

    private var rad: CGFloat = 0

    // MARK: Für die Selbstprüfung (Probe.swift)

    func rechteckFuerProbe(_ i: Int) -> NSRect { berechne(); return rechtecke[i] }
    var aktiverIndexFuerProbe: Int? { aktiverIndex() }
    func schliessRechteckFuerProbe(_ i: Int) -> NSRect { berechne(); return schliessRechteck(rechtecke[i]) }
    func pinRechteckFuerProbe(_ i: Int) -> NSRect { berechne(); return pinRechteck(rechtecke[i]) }

    /// Den aktiven Tab ganz ins Bild holen.
    func zeigeAktiven() {
        let a = anfaenge
        let liste = tabs()
        guard let i = aktiverIndex(), i < a.count else { versatz = min(versatz, groessterVersatz); needsDisplay = true; return }
        let platz = bounds.width - (gesamtbreite > bounds.width - 4 ? 40 : 4)
        if a[i] < versatz {
            versatz = a[i]
        } else if a[i] + breite(liste[i]) - versatz > platz {
            versatz = a.first { a[i] + breite(liste[i]) - $0 <= platz } ?? a[i]
        }
        versatz = min(versatz, groessterVersatz)
        needsDisplay = true
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        zeigeAktiven()
    }
}

extension NSColor {
    convenience init(rgb: Int) {
        self.init(
            srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}
