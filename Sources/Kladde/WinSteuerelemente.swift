import AppKit

/// Steuerelemente, die aussehen wie die von Windows 10/11 in den Dialogen von
/// Notepad++: rechteckige graue Knöpfe mit blauem Rand beim Überfahren,
/// eckige Kästchen, runde Optionsfelder, flache Eingabefelder mit Pfeil,
/// Reiter links und Gruppenrahmen als dünne Linie. Hell oder dunkel wie
/// Notepad++ im Dunkelmodus.
enum Win {
    static var dunkel: Bool { Hauptfenster.istDunkel }
    static var grund: NSColor { NSColor(rgb: dunkel ? 0x202020 : 0xF0F0F0) }
    static var feld: NSColor { NSColor(rgb: dunkel ? 0x383838 : 0xFFFFFF) }
    static var text: NSColor { NSColor(rgb: dunkel ? 0xE0E0E0 : 0x000000) }
    static var textAus: NSColor { NSColor(rgb: dunkel ? 0x6E6E6E : 0x838383) }
    static var linie: NSColor { NSColor(rgb: dunkel ? 0x646464 : 0xDCDCDC) }
    static var akzent: NSColor { NSColor(rgb: dunkel ? 0x4CC2FF : 0x0078D7) }
    /// Eine Schrift für alle Dialoge, wie «MS Shell Dlg» 8 Punkt (Tahoma, 11 Pixel)
    /// in Notepad++. Nichts wird verkleinert: Was nicht passt, bricht wie unter
    /// Windows in Knöpfen um und wird sonst gekürzt.
    static let schrift = NSFont.systemFont(ofSize: 11)

    static func rechteck(_ r: NSRect, fuell: NSColor, rand: NSColor, breite: CGFloat = 1) {
        fuell.setFill()
        r.fill()
        rand.setStroke()
        let p = NSBezierPath(rect: r.insetBy(dx: breite / 2, dy: breite / 2))
        p.lineWidth = breite
        p.stroke()
    }

    static func zeichne(_ titel: String, in r: NSRect, farbe: NSColor, mitte: Bool = false, umbruch: Bool = false) {
        // «&» kennzeichnet unter Windows die Zugriffstaste; auf dem Mac fällt es weg.
        // Zugriffstasten («&») hat scripts/oberflaeche.py schon entfernt; ein «&» hier ist echt.
        let t = titel
        let passt = (t as NSString).size(withAttributes: [.font: schrift]).width <= r.width
        let absatz = NSMutableParagraphStyle()
        absatz.alignment = mitte ? .center : .left
        absatz.lineBreakMode = umbruch && !passt ? .byWordWrapping : .byTruncatingTail
        let a: [NSAttributedString.Key: Any] = [.font: schrift, .foregroundColor: farbe, .paragraphStyle: absatz]
        let s = NSAttributedString(string: t, attributes: a)
        let h = min(r.height, s.boundingRect(with: NSSize(width: r.width, height: 1000), options: [.usesLineFragmentOrigin]).height)
        s.draw(with: NSRect(x: r.minX, y: r.midY - h / 2, width: r.width, height: h), options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

}

/// Grundfläche eines Dialogs: oben links beginnend, Farbe wie Windows.
final class WinFlaeche: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        Win.grund.setFill()
        bounds.fill()
    }
}

/// Basis der Knöpfe: merkt sich Überfahren und Drücken.
class WinSchalter: NSButton {
    var ueber = false { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    override var state: NSControl.StateValue { didSet { needsDisplay = true } }
    override var isEnabled: Bool { didSet { needsDisplay = true } }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { ueber = true }
    override func mouseExited(with event: NSEvent) { ueber = false }
    override var focusRingType: NSFocusRingType { get { .none } set {} }
}

/// Ein Druckknopf. Der Standardknopf hat einen blauen Rand.
final class WinKnopf: WinSchalter {
    var istStandard = false { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let gedrueckt = isHighlighted
        let d = Win.dunkel
        let (fuell, rand): (Int, Int)
        if !isEnabled { (fuell, rand) = d ? (0x2B2B2B, 0x3F3F3F) : (0xCCCCCC, 0xBFBFBF) }
        else if gedrueckt { (fuell, rand) = d ? (0x1E3A50, 0x4CC2FF) : (0xCCE4F7, 0x005499) }
        else if ueber { (fuell, rand) = d ? (0x45494C, 0x4CC2FF) : (0xE5F1FB, 0x0078D7) }
        else if istStandard { (fuell, rand) = d ? (0x333333, 0x4CC2FF) : (0xE1E1E1, 0x0078D7) }
        else { (fuell, rand) = d ? (0x333333, 0x9B9B9B) : (0xE1E1E1, 0xADADAD) }
        Win.rechteck(bounds, fuell: NSColor(rgb: fuell), rand: NSColor(rgb: rand), breite: istStandard && isEnabled && !gedrueckt ? 2 : 1)
        Win.zeichne(title, in: bounds.insetBy(dx: 4, dy: 2), farbe: isEnabled ? Win.text : Win.textAus, mitte: true, umbruch: true)
    }
}

/// Ein Kontrollkästchen oder Optionsfeld mit Beschriftung rechts.
final class WinKaestchen: WinSchalter {
    let rund: Bool

    init(titel: String, rund: Bool, target: AnyObject?, action: Selector?) {
        self.rund = rund
        super.init(frame: .zero)
        title = titel
        // Auch Optionsfelder als Schalter: macOS koppelt sonst alle mit gleicher
        // Aktion; die Gruppen führt der Dialog selbst.
        setButtonType(.switch)
        self.target = target
        self.action = action
        isBordered = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let d = Win.dunkel
        let an = state == .on
        let box = NSRect(x: 0.5, y: (bounds.height - 13) / 2 + 0.5, width: 13, height: 13)
        let randFarbe: NSColor = !isEnabled ? NSColor(rgb: d ? 0x555555 : 0xBCBCBC)
            : (ueber || isHighlighted) ? Win.akzent : NSColor(rgb: d ? 0xC0C0C0 : 0x333333)
        let fuell = isHighlighted ? NSColor(rgb: d ? 0x1E3A50 : 0xCCE4F7) : Win.feld
        if rund {
            let kreis = NSBezierPath(ovalIn: box.insetBy(dx: 0.5, dy: 0.5))
            fuell.setFill(); kreis.fill()
            randFarbe.setStroke(); kreis.stroke()
            if an {
                (isEnabled ? (ueber ? Win.akzent : NSColor(rgb: d ? 0xE0E0E0 : 0x333333)) : randFarbe).setFill()
                NSBezierPath(ovalIn: box.insetBy(dx: 3.5, dy: 3.5)).fill()
            }
        } else {
            Win.rechteck(box, fuell: fuell, rand: randFarbe)
            if an {
                let haken = NSBezierPath()
                haken.move(to: NSPoint(x: box.minX + 3, y: box.midY))
                haken.line(to: NSPoint(x: box.minX + 5.5, y: box.maxY - 3.5))
                haken.line(to: NSPoint(x: box.maxX - 2.5, y: box.minY + 3))
                haken.lineWidth = 1.6
                (isEnabled ? NSColor(rgb: d ? 0xE0E0E0 : 0x000000) : randFarbe).setStroke()
                haken.stroke()
            }
        }
        Win.zeichne(title, in: NSRect(x: 18, y: 0, width: bounds.width - 18, height: bounds.height), farbe: isEnabled ? Win.text : Win.textAus)
    }
}

/// Ein Eingabefeld mit Verlauf: flach, mit Pfeil rechts, wie die Combobox
/// in Notepad++. Der Pfeil zeigt den Verlauf als Menü.
final class WinKombi: NSView, NSTextFieldDelegate {
    let feld = NSTextField()
    private(set) var eintraege: [String] = []
    /// Nach jeder Änderung des Texts (Tippen oder Wahl aus dem Verlauf).
    var geaendert: (() -> Void)?
    private var ueber = false

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        feld.isBordered = false
        feld.drawsBackground = false
        feld.focusRingType = .none
        feld.font = Win.schrift
        feld.usesSingleLineMode = true
        feld.cell?.isScrollable = true
        feld.cell?.wraps = false
        feld.delegate = self
        addSubview(feld)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    var stringValue: String {
        get { feld.stringValue }
        set { feld.stringValue = newValue }
    }

    func removeAllItems() { eintraege = [] }
    func addItems(withObjectValues werte: [Any]) { eintraege += werte.compactMap { $0 as? String } }

    override func layout() {
        super.layout()
        let h = feld.intrinsicContentSize.height
        feld.frame = NSRect(x: 4, y: (bounds.height - h) / 2, width: bounds.width - 4 - 20, height: h)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { ueber = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { ueber = false; needsDisplay = true }

    private var hatFokus: Bool {
        guard let r = window?.firstResponder as? NSTextView else { return false }
        return r.delegate === feld
    }

    func controlTextDidBeginEditing(_ obj: Notification) { needsDisplay = true }
    func controlTextDidEndEditing(_ obj: Notification) { needsDisplay = true }
    func controlTextDidChange(_ obj: Notification) { geaendert?() }

    override func draw(_ dirtyRect: NSRect) {
        let d = Win.dunkel
        let rand = hatFokus ? Win.akzent : ueber ? NSColor(rgb: d ? 0xC8C8C8 : 0x171717) : NSColor(rgb: d ? 0x9B9B9B : 0x7A7A7A)
        Win.rechteck(bounds, fuell: Win.feld, rand: rand)
        if hatFokus {
            // Unter Windows 11 eine dickere Linie unten.
            Win.akzent.setFill()
            NSRect(x: 1, y: bounds.height - 2, width: bounds.width - 2, height: 1).fill()
        }
        // Der Pfeil: ein Winkel, kein Knopf.
        let m = NSPoint(x: bounds.width - 10, y: bounds.midY)
        let p = NSBezierPath()
        p.move(to: NSPoint(x: m.x - 4, y: m.y - 2))
        p.line(to: NSPoint(x: m.x, y: m.y + 2))
        p.line(to: NSPoint(x: m.x + 4, y: m.y - 2))
        p.lineWidth = 1
        NSColor(rgb: d ? 0xC8C8C8 : 0x404040).setStroke()
        p.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard p.x > bounds.width - 20 else { window?.makeFirstResponder(feld); return }
        let m = NSMenu()
        if eintraege.isEmpty {
            let leer = NSMenuItem(title: "(kein Verlauf)", action: nil, keyEquivalent: "")
            leer.isEnabled = false
            m.addItem(leer)
        }
        for e in eintraege {
            let i = NSMenuItem(title: e, action: #selector(gewaehlt(_:)), keyEquivalent: "")
            i.target = self
            m.addItem(i)
        }
        m.minimumWidth = bounds.width
        m.font = Win.schrift
        m.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.height + 2), in: self)
    }

    @objc private func gewaehlt(_ sender: NSMenuItem) {
        stringValue = sender.title
        geaendert?()
        window?.makeFirstResponder(feld)
    }
}

/// Ein Gruppenrahmen: Linie, Titel auf der oberen Kante.
final class WinGruppe: NSView {
    let titel: String
    init(titel: String) {
        self.titel = titel
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let r = NSRect(x: 0.5, y: 7.5, width: bounds.width - 1, height: bounds.height - 8)
        Win.linie.setStroke()
        NSBezierPath(rect: r).stroke()
        guard !titel.isEmpty else { return }
        let a: [NSAttributedString.Key: Any] = [.font: Win.schrift, .foregroundColor: Win.text]
        let g = (titel as NSString).size(withAttributes: a)
        Win.grund.setFill()
        NSRect(x: 6, y: 0, width: g.width + 4, height: 16).fill()
        (titel as NSString).draw(at: NSPoint(x: 8, y: 0), withAttributes: a)
    }
}

/// Eine Beschriftung in Windows-Farbe.
final class WinText: NSTextField {
    convenience init(_ titel: String, rechts: Bool) {
        self.init(labelWithString: titel)
        font = Win.schrift
        alignment = rechts ? .right : .left
        lineBreakMode = .byClipping
        textColor = Win.text
    }

    /// Mehrzeilig: oben beginnend, am Wortende umgebrochen (LTEXT über mehrere Zeilen).
    var mehrzeilig = false

    /// Selbst gezeichnet wie die Beschriftung der Kästchen, damit alle Texte
    /// im Dialog gleich aussehen (NSTextField setzt dünne Schrift sonst kräftiger).
    override func draw(_ dirtyRect: NSRect) {
        let absatz = NSMutableParagraphStyle()
        absatz.alignment = alignment
        absatz.lineBreakMode = mehrzeilig ? .byWordWrapping : .byTruncatingTail
        let a: [NSAttributedString.Key: Any] = [.font: font ?? Win.schrift, .foregroundColor: textColor ?? Win.text, .paragraphStyle: absatz]
        if mehrzeilig {
            (stringValue as NSString).draw(with: NSRect(x: 2, y: 0, width: bounds.width - 4, height: bounds.height),
                                          options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: a)
            return
        }
        let h = (stringValue as NSString).size(withAttributes: a).height
        (stringValue as NSString).draw(in: NSRect(x: 2, y: (bounds.height - h) / 2, width: bounds.width - 4, height: h), withAttributes: a)
    }

}

/// Ein Schieberegler wie die Trackbar von Windows: dünne Spur, blauer Griff.
final class WinRegler: NSControl {
    var wert: Double = 80 { didSet { needsDisplay = true } }
    var bereich: ClosedRange<Double> = 20...100
    override var isFlipped: Bool { true }
    override var isEnabled: Bool { didSet { needsDisplay = true } }

    private var anteil: CGFloat { CGFloat((wert - bereich.lowerBound) / (bereich.upperBound - bereich.lowerBound)) }

    override func draw(_ dirtyRect: NSRect) {
        let spur = NSRect(x: 5, y: bounds.midY - 2, width: bounds.width - 10, height: 4)
        Win.rechteck(spur, fuell: NSColor(rgb: Win.dunkel ? 0x555555 : 0xE7EAEA), rand: NSColor(rgb: Win.dunkel ? 0x6E6E6E : 0xD6D6D6))
        let x = spur.minX + anteil * spur.width
        let griff = NSRect(x: x - 5, y: bounds.midY - 9, width: 10, height: 18)
        (isEnabled ? Win.akzent : NSColor(rgb: Win.dunkel ? 0x555555 : 0xCCCCCC)).setFill()
        NSBezierPath(roundedRect: griff, xRadius: 2, yRadius: 2).fill()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        var e: NSEvent? = event
        while let ev = e {
            let p = convert(ev.locationInWindow, from: nil)
            let a = min(max((p.x - 5) / (bounds.width - 10), 0), 1)
            wert = bereich.lowerBound + Double(a) * (bereich.upperBound - bereich.lowerBound)
            if let action { NSApp.sendAction(action, to: target, from: self) }
            if ev.type == .leftMouseUp { break }
            e = window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp])
        }
    }
}

/// Die Reiter oben links, wie das Tab-Control von Windows: der gewählte heller
/// und etwas höher, darunter eine Linie über die ganze Breite.
final class WinReiter: NSView {
    var titel: [String] = [] { didSet { needsDisplay = true } }
    var gewaehlt = 0 { didSet { needsDisplay = true } }
    var gewechselt: ((Int) -> Void)?
    private var ueber: Int?
    override var isFlipped: Bool { true }

    private func rechtecke() -> [NSRect] {
        var x: CGFloat = 4
        return titel.map { t in
            let b = (t as NSString).size(withAttributes: [.font: Win.schrift]).width + 18
            defer { x += b }
            return NSRect(x: x, y: 2, width: b, height: bounds.height - 2)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let i = rechtecke().firstIndex { $0.contains(p) }
        if i != ueber { ueber = i; needsDisplay = true }
    }

    override func mouseExited(with event: NSEvent) { ueber = nil; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let i = rechtecke().firstIndex(where: { $0.contains(p) }), i != gewaehlt else { return }
        gewaehlt = i
        gewechselt?(i)
    }

    override func draw(_ dirtyRect: NSRect) {
        Win.grund.setFill()
        bounds.fill()
        let d = Win.dunkel
        let rand = NSColor(rgb: d ? 0x646464 : 0xD9D9D9)
        rand.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
        for (i, var r) in rechtecke().enumerated() {
            let aktiv = i == gewaehlt
            if !aktiv { r = NSRect(x: r.minX, y: r.minY + 2, width: r.width, height: r.height - 2) }
            let fuell: Int = aktiv ? (d ? 0x383838 : 0xFFFFFF) : ueber == i ? (d ? 0x45494C : 0xD8EAF9) : (d ? 0x2B2B2B : 0xF0F0F0)
            NSColor(rgb: fuell).setFill()
            r.fill()
            rand.setStroke()
            let p = NSBezierPath()
            p.move(to: NSPoint(x: r.minX + 0.5, y: r.maxY))
            p.line(to: NSPoint(x: r.minX + 0.5, y: r.minY + 0.5))
            p.line(to: NSPoint(x: r.maxX - 0.5, y: r.minY + 0.5))
            p.line(to: NSPoint(x: r.maxX - 0.5, y: r.maxY))
            p.stroke()
            if aktiv {
                NSColor(rgb: fuell).setFill()
                NSRect(x: r.minX + 1, y: r.maxY - 1, width: r.width - 2, height: 1).fill()
            }
            Win.zeichne(titel[i], in: r, farbe: Win.text, mitte: true)
        }
    }
}
