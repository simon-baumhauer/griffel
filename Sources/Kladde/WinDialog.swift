import AppKit
import ScintillaBruecke

extension NSView {
    fileprivate func identifiziert(_ id: String) -> NSView {
        identifier = NSUserInterfaceItemIdentifier(id)
        return self
    }
}

/// Ein einzeiliges oder mehrzeiliges Eingabefeld im Windows-Stil (EDITTEXT).
final class WinEingabe: NSView, NSTextFieldDelegate, NSTextViewDelegate {
    private let feld: NSTextField?
    private let rollen: NSScrollView?
    let textAnsicht: NSTextView?
    var geaendert: (() -> Void)?
    var nurLesen = false {
        didSet { feld?.isEditable = !nurLesen; textAnsicht?.isEditable = !nurLesen; needsDisplay = true }
    }
    override var isFlipped: Bool { true }

    init(mehrzeilig: Bool) {
        if mehrzeilig {
            let r = NSScrollView()
            let t = NSTextView()
            t.isRichText = false
            t.font = Win.schrift
            t.textColor = Win.text
            t.drawsBackground = false
            t.isAutomaticQuoteSubstitutionEnabled = false
            t.isAutomaticDashSubstitutionEnabled = false
            t.isAutomaticSpellingCorrectionEnabled = false
            t.isVerticallyResizable = true
            t.autoresizingMask = [.width]
            r.documentView = t
            r.hasVerticalScroller = true
            r.drawsBackground = false
            r.borderType = .noBorder
            rollen = r
            textAnsicht = t
            feld = nil
        } else {
            let f = NSTextField()
            f.isBordered = false
            f.drawsBackground = false
            f.focusRingType = .none
            f.font = Win.schrift
            f.textColor = Win.text
            f.usesSingleLineMode = true
            f.cell?.isScrollable = true
            f.cell?.wraps = false
            feld = f
            rollen = nil
            textAnsicht = nil
        }
        super.init(frame: .zero)
        if let feld { feld.delegate = self; addSubview(feld) }
        if let rollen { textAnsicht?.delegate = self; addSubview(rollen) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    var stringValue: String {
        get { feld?.stringValue ?? textAnsicht?.string ?? "" }
        set { feld?.stringValue = newValue; textAnsicht?.string = newValue }
    }

    var ersterAntworter: NSView? { feld ?? textAnsicht }

    /// Für die Selbstprüfung: wohin getippt wird (der Feldeditor eines einzeiligen Felds).
    var textAnsichtOderFeldFuerProbe: NSTextView? {
        if let t = textAnsicht { window?.makeFirstResponder(t); return t }
        guard let f = feld, let w = window else { return nil }
        w.makeFirstResponder(f)
        return (w.firstResponder as? NSTextView) ?? (w.fieldEditor(false, for: f) as? NSTextView)
    }

    override func layout() {
        super.layout()
        if let feld {
            let h = feld.intrinsicContentSize.height
            feld.frame = NSRect(x: 3, y: (bounds.height - h) / 2, width: bounds.width - 6, height: h)
        }
        rollen?.frame = bounds.insetBy(dx: 1, dy: 1)
        if let t = textAnsicht, let r = rollen { t.frame.size.width = r.contentSize.width; t.minSize = NSSize(width: 0, height: r.contentSize.height) }
    }

    func controlTextDidChange(_ obj: Notification) { geaendert?() }
    func textDidChange(_ notification: Notification) { geaendert?() }
    func controlTextDidBeginEditing(_ obj: Notification) { needsDisplay = true }
    func controlTextDidEndEditing(_ obj: Notification) { needsDisplay = true }

    private var hatFokus: Bool {
        guard let r = window?.firstResponder as? NSTextView else { return false }
        return r === textAnsicht || r.delegate === feld
    }

    override func draw(_ dirtyRect: NSRect) {
        let rand = hatFokus ? Win.akzent : NSColor(rgb: Win.dunkel ? 0x9B9B9B : 0x7A7A7A)
        Win.rechteck(bounds, fuell: nurLesen ? Win.grund : Win.feld, rand: rand)
    }
}

/// Eine Auswahlliste (COMBOBOX mit CBS_DROPDOWNLIST): flach, Pfeil rechts, ein Klick zeigt die Liste.
final class WinAuswahl: NSView {
    var eintraege: [String] = [] { didSet { gewaehlt = min(gewaehlt, max(0, eintraege.count - 1)); needsDisplay = true } }
    var gewaehlt = 0 { didSet { needsDisplay = true } }
    var geaendert: (() -> Void)?
    var isEnabled = true { didSet { needsDisplay = true } }
    private var ueber = false
    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { ueber = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { ueber = false; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        let d = Win.dunkel
        let fuell = !isEnabled ? Win.grund : ueber ? NSColor(rgb: d ? 0x45494C : 0xE5F1FB) : NSColor(rgb: d ? 0x333333 : 0xE1E1E1)
        let rand = ueber && isEnabled ? Win.akzent : NSColor(rgb: d ? 0x9B9B9B : 0xADADAD)
        Win.rechteck(bounds, fuell: fuell, rand: rand)
        let t = eintraege.indices.contains(gewaehlt) ? eintraege[gewaehlt] : ""
        Win.zeichne(t, in: NSRect(x: 4, y: 0, width: bounds.width - 24, height: bounds.height), farbe: isEnabled ? Win.text : Win.textAus)
        let m = NSPoint(x: bounds.width - 10, y: bounds.midY)
        let p = NSBezierPath()
        p.move(to: NSPoint(x: m.x - 4, y: m.y - 2))
        p.line(to: NSPoint(x: m.x, y: m.y + 2))
        p.line(to: NSPoint(x: m.x + 4, y: m.y - 2))
        (isEnabled ? NSColor(rgb: d ? 0xC8C8C8 : 0x404040) : Win.textAus).setStroke()
        p.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled, !eintraege.isEmpty else { return }
        let m = NSMenu()
        for (i, e) in eintraege.enumerated() {
            let item = NSMenuItem(title: e, action: #selector(waehle(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            item.state = i == gewaehlt ? .on : .off
            m.addItem(item)
        }
        m.minimumWidth = bounds.width
        m.popUp(positioning: m.items[gewaehlt], at: NSPoint(x: 0, y: bounds.height - 3), in: self)
    }

    @objc private func waehle(_ sender: NSMenuItem) {
        gewaehlt = sender.tag
        geaendert?()
    }
}

/// Eine Liste wie die ListBox von Windows: weiss, Auswahl blau hinterlegt.
final class WinListe: NSView {
    var eintraege: [String] = [] { didSet { needsDisplay = true } }
    var gewaehlt = 0 { didSet { needsDisplay = true } }
    var gewechselt: ((Int) -> Void)?
    var isEnabled = true { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }
    private let zeile: CGFloat = 18
    private var oben = 0

    override func draw(_ dirtyRect: NSRect) {
        let d = Win.dunkel
        Win.rechteck(bounds, fuell: isEnabled ? Win.feld : Win.grund, rand: NSColor(rgb: d ? 0x646464 : 0x828790))
        let sichtbar = Int((bounds.height - 4) / zeile)
        oben = min(max(0, oben), max(0, eintraege.count - sichtbar))
        if gewaehlt < oben { oben = gewaehlt } else if gewaehlt >= oben + sichtbar { oben = gewaehlt - sichtbar + 1 }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: bounds.insetBy(dx: 1, dy: 1)).addClip()
        for i in oben..<min(eintraege.count, oben + sichtbar + 1) {
            let r = NSRect(x: 1, y: 2 + CGFloat(i - oben) * zeile, width: bounds.width - 2, height: zeile)
            let an = i == gewaehlt
            if an {
                (isEnabled ? Win.akzent : NSColor(rgb: d ? 0x454545 : 0xCCCCCC)).setFill()
                r.fill()
            }
            let farbe: NSColor = !isEnabled ? Win.textAus : an ? .white : Win.text
            Win.zeichne(eintraege[i], in: NSRect(x: r.minX + 4, y: r.minY, width: r.width - 8, height: r.height), farbe: farbe)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        window?.makeFirstResponder(self)
        let p = convert(event.locationInWindow, from: nil)
        let i = oben + Int((p.y - 2) / zeile)
        guard eintraege.indices.contains(i), i != gewaehlt else { return }
        gewaehlt = i
        gewechselt?(i)
    }

    override func scrollWheel(with event: NSEvent) {
        oben -= Int(event.scrollingDeltaY / 6)
        needsDisplay = true
    }

    override var acceptsFirstResponder: Bool { isEnabled }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 125 where gewaehlt < eintraege.count - 1: gewaehlt += 1; gewechselt?(gewaehlt)
        case 126 where gewaehlt > 0: gewaehlt -= 1; gewechselt?(gewaehlt)
        default: super.keyDown(with: event)
        }
    }
}

/// Baut Elemente einer .rc-Beschreibung von Notepad++ als Windows-Steuerelemente
/// in eine Fläche: Dialogeinheiten umgerechnet, Optionsfelder in Gruppen wie unter
/// Windows (eine Gruppe beginnt mit WS_GROUP), Beschriftungen enden vor dem
/// nächsten Element derselben Zeile.
final class WinFormular: NSObject {
    static let sx: CGFloat = 1.62
    static let sy: CGFloat = 1.78

    private(set) var elemente: [String: NSView] = [:]
    /// Optionsfelder, die sich gegenseitig ausschliessen.
    var gruppen: [[String]] = []
    /// Ein Knopf, ein Kästchen, ein Regler, eine Liste oder ein Feld hat sich geändert.
    var gedrueckt: ((String) -> Void)?

    func baue(_ liste: [Oberflaeche.Element], in flaeche: NSView, ursprung: NSPoint = .zero) {
        var neu: [NSView] = []
        var gruppe: [String]?
        for e in liste {
            if e.art == "RADIO" {
                if (e.stil ?? "").contains("WS_GROUP") || gruppe == nil {
                    if let g = gruppe, g.count > 1 { gruppen.append(g) }
                    gruppe = [e.id]
                } else {
                    gruppe?.append(e.id)
                }
            } else if (e.stil ?? "").contains("WS_GROUP"), let g = gruppe {
                if g.count > 1 { gruppen.append(g) }
                gruppe = nil
            }
            if let v = element(e, ursprung: ursprung) {
                if e.art == "GROUPBOX" { flaeche.addSubview(v, positioned: .below, relativeTo: nil) } else { flaeche.addSubview(v) }
                elemente[e.id] = v
                neu.append(v)
            }
        }
        if let g = gruppe, g.count > 1 { gruppen.append(g) }
        let alle = neu.filter { !($0 is WinGruppe) }
        for v in alle where v is WinKaestchen || v is WinText {
            let rechts = alle.filter { $0 !== v && $0.frame.minX > v.frame.minX + 10 && $0.frame.minX < v.frame.maxX
                && $0.frame.maxY > v.frame.minY + 3 && $0.frame.minY < v.frame.maxY - 3 }.map(\.frame.minX).min()
            if let rechts { v.frame.size.width = rechts - v.frame.minX - 4 }
        }
    }

    private func rechteck(_ e: Oberflaeche.Element, _ u: NSPoint, hoehe: CGFloat? = nil) -> NSRect {
        NSRect(x: (CGFloat(e.x) + u.x) * Self.sx + 2, y: (CGFloat(e.y) + u.y) * Self.sy + 2,
               width: CGFloat(e.b) * Self.sx, height: hoehe ?? CGFloat(e.h) * Self.sy)
    }

    private func element(_ e: Oberflaeche.Element, ursprung u: NSPoint) -> NSView? {
        let text = Mac.text(e.text)
        let stil = e.stil ?? ""
        let v: NSView
        switch e.art {
        case "LTEXT", "RTEXT", "CTEXT":
            let t = WinText(text, rechts: e.art == "RTEXT")
            if e.art == "CTEXT" { t.alignment = .center }
            if text == "(?)" { t.textColor = Win.akzent }
            v = t
            // Ab zwei Zeilen Höhe (16 Dialogeinheiten) mehrzeilig, sonst einzeilig mittig.
            if e.h >= 16 {
                t.mehrzeilig = true
                v.frame = rechteck(e, u)
                return v.identifiziert(e.id)
            }
            var r = rechteck(e, u, hoehe: 18).offsetBy(dx: 0, dy: -3)
            // «(?)» ist in den .rc-Dateien nur 10 Einheiten breit; die Mac-Schrift braucht etwas mehr.
            if text == "(?)" { r.size.width = max(r.width, 20) }
            if e.art == "RTEXT" { r = NSRect(x: max(2, r.minX - 14), y: r.minY, width: r.maxX - max(2, r.minX - 14), height: r.height) }
            v.frame = r
        case "EDITTEXT":
            let mehr = stil.contains("MULTILINE")
            let f = WinEingabe(mehrzeilig: mehr)
            f.nurLesen = stil.contains("READONLY")
            f.geaendert = { [weak self] in self?.gedrueckt?(e.id) }
            v = f
            v.frame = mehr ? rechteck(e, u) : rechteck(e, u, hoehe: 23).offsetBy(dx: 0, dy: -2)
        case "COMBOBOX":
            if stil.contains("DROPDOWNLIST") || e.liste != nil {
                let a = WinAuswahl()
                a.eintraege = e.liste ?? []
                a.geaendert = { [weak self] in self?.gedrueckt?(e.id) }
                v = a
            } else {
                let k = WinKombi()
                k.geaendert = { [weak self] in self?.gedrueckt?(e.id) }
                v = k
            }
            v.frame = rechteck(e, u, hoehe: 23).offsetBy(dx: 0, dy: -2)
        case "LISTBOX":
            let l = WinListe()
            l.gewechselt = { [weak self] _ in self?.gedrueckt?(e.id) }
            v = l
            v.frame = rechteck(e, u)
        case "SLIDER":
            let s = WinRegler()
            s.target = self
            s.action = #selector(geregelt(_:))
            v = s
            v.frame = rechteck(e, u, hoehe: 22).offsetBy(dx: 0, dy: -3)
        case "PUSHBUTTON":
            let k = WinKnopf()
            k.title = text
            k.isBordered = false
            k.target = self
            k.action = #selector(knopf(_:))
            k.istStandard = stil.contains("STANDARD")
            if k.istStandard { k.keyEquivalent = "\r" }
            if e.id == "IDCANCEL" { k.keyEquivalent = "\u{1b}" }
            v = k
            v.frame = e.h > 15 ? rechteck(e, u) : rechteck(e, u, hoehe: 25).offsetBy(dx: 0, dy: -1)
        case "CHECKBOX", "RADIO":
            let k = WinKaestchen(titel: text, rund: e.art == "RADIO", target: self, action: #selector(knopf(_:)))
            v = k
            v.frame = rechteck(e, u, hoehe: 18).offsetBy(dx: 0, dy: -3)
        case "GROUPBOX":
            v = WinGruppe(titel: text)
            v.frame = rechteck(e, u).offsetBy(dx: 0, dy: -4)
        default:
            return nil
        }
        return v.identifiziert(e.id)
    }

    @objc private func knopf(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        if let gruppe = gruppen.first(where: { $0.contains(id) }) {
            for g in gruppe { setzeHaken(g, g == id) }
        }
        gedrueckt?(id)
    }

    @objc private func geregelt(_ sender: WinRegler) {
        guard let id = sender.identifier?.rawValue else { return }
        gedrueckt?(id)
    }

    // MARK: Zugriff

    func text(_ id: String) -> String {
        (elemente[id] as? WinEingabe)?.stringValue ?? (elemente[id] as? WinKombi)?.stringValue ?? (elemente[id] as? NSTextField)?.stringValue ?? ""
    }

    func setzeText(_ id: String, _ t: String) {
        if let f = elemente[id] as? WinEingabe { f.stringValue = t }
        else if let f = elemente[id] as? WinKombi { f.stringValue = t }
        else if let f = elemente[id] as? NSTextField { f.stringValue = t; f.needsDisplay = true }
        else if let k = elemente[id] as? NSButton { k.title = t }
    }

    func haken(_ id: String) -> Bool { (elemente[id] as? NSButton)?.state == .on }
    func setzeHaken(_ id: String, _ an: Bool) { (elemente[id] as? NSButton)?.state = an ? .on : .off }
    func zahl(_ id: String) -> Int? { Int(text(id).trimmingCharacters(in: .whitespaces)) }
    func auswahl(_ id: String) -> WinAuswahl? { elemente[id] as? WinAuswahl }
    func kombi(_ id: String) -> WinKombi? { elemente[id] as? WinKombi }
    func eingabe(_ id: String) -> WinEingabe? { elemente[id] as? WinEingabe }
    func regler(_ id: String) -> WinRegler? { elemente[id] as? WinRegler }
    func liste(_ id: String) -> WinListe? { elemente[id] as? WinListe }

    func aktiv(_ id: String, _ an: Bool) {
        if let c = elemente[id] as? NSControl { c.isEnabled = an }
        (elemente[id] as? WinAuswahl)?.isEnabled = an
        (elemente[id] as? WinListe)?.isEnabled = an
        (elemente[id] as? WinEingabe)?.nurLesen = !an
        if let k = elemente[id] as? WinKombi { k.feld.isEnabled = an; k.alphaValue = an ? 1 : 0.6 }
    }

    func istAktiv(_ id: String) -> Bool {
        if let c = elemente[id] as? NSControl { return c.isEnabled }
        if let a = elemente[id] as? WinAuswahl { return a.isEnabled }
        if let l = elemente[id] as? WinListe { return l.isEnabled }
        if let f = elemente[id] as? WinEingabe { return !f.nurLesen }
        return true
    }
}

/// Ein Dialog nach einer .rc-Beschreibung von Notepad++ (Oberflaeche.dialoge):
/// dieselben Elemente an derselben Stelle, im Windows-Stil, als Fenster über
/// dem Hauptfenster. Die Logik setzt der Aufrufer über `gedrueckt` und die
/// Zugriffe auf die Elemente.
final class WinDialog: NSObject, NSWindowDelegate {
    let fenster: NSPanel
    let formular = WinFormular()
    var elemente: [String: NSView] { formular.elemente }
    /// Zusätzliche Gruppen von Optionsfeldern (die aus der .rc-Datei kennt das Formular selbst).
    var gruppen: [[String]] {
        get { formular.gruppen }
        set { formular.gruppen = newValue + formular.gruppen.filter { g in !newValue.contains { !Set($0).isDisjoint(with: g) } } }
    }
    /// Ein Knopf (Kennung wie IDOK) oder ein Kästchen wurde gedrückt; «Abbrechen» schliesst selbst.
    var gedrueckt: ((String) -> Void)?
    private static var offen: [WinDialog] = []

    init?(_ schluessel: String) {
        guard let d = Oberflaeche.gemeinsam.dialoge?[schluessel] else { return nil }
        let breite = CGFloat(d.groesse[0]) * WinFormular.sx + 4
        let hoehe = CGFloat(d.groesse[1]) * WinFormular.sy + 4
        fenster = NSPanel(contentRect: NSRect(x: 0, y: 0, width: breite, height: hoehe), styleMask: [.titled, .closable],
                          backing: .buffered, defer: true)
        fenster.title = d.titel
        fenster.isReleasedWhenClosed = false
        fenster.isRestorable = false
        fenster.backgroundColor = Win.grund
        super.init()
        fenster.delegate = self
        let flaeche = WinFlaeche(frame: NSRect(x: 0, y: 0, width: breite, height: hoehe))
        fenster.contentView = flaeche
        formular.baue(d.elemente, in: flaeche)
        formular.gedrueckt = { [weak self] id in
            if id == "IDCANCEL" { self?.schliesse() } else { self?.gedrueckt?(id) }
        }
    }

    // MARK: Zugriff (wie im Formular)

    func text(_ id: String) -> String { formular.text(id) }
    func setzeText(_ id: String, _ t: String) { formular.setzeText(id, t) }
    func haken(_ id: String) -> Bool { formular.haken(id) }
    func setzeHaken(_ id: String, _ an: Bool) { formular.setzeHaken(id, an) }
    func zahl(_ id: String) -> Int? { formular.zahl(id) }
    func auswahl(_ id: String) -> WinAuswahl? { formular.auswahl(id) }
    func kombi(_ id: String) -> WinKombi? { formular.kombi(id) }
    func eingabe(_ id: String) -> WinEingabe? { formular.eingabe(id) }
    func aktiv(_ id: String, _ an: Bool) { formular.aktiv(id, an) }

    // MARK: Zeigen

    /// Mittig über dem Hauptfenster, wie Notepad++ seine Dialoge zeigt; `fokus` bekommt die Eingabe.
    func zeige(fokus: String? = nil) {
        Self.offen.append(self)
        if let haupt = Hauptfenster.gemeinsam.window {
            let f = fenster.frame
            fenster.setFrameOrigin(NSPoint(x: haupt.frame.midX - f.width / 2, y: haupt.frame.midY - f.height / 2 + 80))
            haupt.addChildWindow(fenster, ordered: .above)
        }
        fenster.makeKeyAndOrderFront(nil)
        if let fokus {
            let ziel = (elemente[fokus] as? WinEingabe)?.ersterAntworter ?? (elemente[fokus] as? WinKombi)?.feld ?? elemente[fokus]
            fenster.makeFirstResponder(ziel)
            ((elemente[fokus] as? WinKombi)?.feld ?? ziel as? NSTextField)?.selectText(nil)
        }
    }

    private var modal = false
    private var modalErgebnis = "IDCANCEL"

    /// Modal wie ein Dialog von Windows: Kehrt mit der Kennung des gedrückten Knopfs
    /// zurück (IDCANCEL bei Esc oder Schliessen).
    func zeigeModal(fokus: String? = nil) -> String {
        let vorher = gedrueckt
        gedrueckt = { [weak self] id in
            vorher?(id)
            guard let self, ["IDOK", "IDYES", "IDNO", "IDRETRY", "IDIGNORE", "IDABORT"].contains(id) else { return }
            self.modalErgebnis = id
            self.schliesse()
        }
        modal = true
        modalErgebnis = "IDCANCEL"
        zeige(fokus: fokus)
        NSApp.runModal(for: fenster)
        return modalErgebnis
    }

    func schliesse() {
        if modal { modal = false; NSApp.stopModal() }
        fenster.parent?.removeChildWindow(fenster)
        fenster.orderOut(nil)
        Self.offen.removeAll { $0 === self }
        if let e = Hauptfenster.gemeinsam.aktiv { Hauptfenster.gemeinsam.window?.makeFirstResponder(e.ansicht.content()) }
    }

    func windowWillClose(_ notification: Notification) {
        if modal { modal = false; NSApp.stopModal() }
        fenster.parent?.removeChildWindow(fenster)
        Self.offen.removeAll { $0 === self }
    }

    /// Der oberste offene Dialog (für die Selbstprüfung).
    static var oberster: WinDialog? { offen.last }
}

// MARK: - Die Dialoge

enum Dialoge {
    private static let ablage = UserDefaults.standard

    /// «Speichern» wie doSaveOrNot in Notepad++: Ja, Nein, Abbruch, bei mehreren
    /// geänderten Dateien auch «Ja für alle» und «Nein für alle».
    static func speichernFrage(_ d: Dokument, mehrere: Bool) -> String {
        guard let w = WinDialog("speichern") else { return "IDNO" }
        let name = d.fileURL?.path ?? d.tabTitel
        w.setzeText("IDC_DOSAVEORNOTTEXT", w.text("IDC_DOSAVEORNOTTEXT").replacingOccurrences(of: "$STR_REPLACE$", with: name))
        for id in ["IDRETRY", "IDIGNORE"] { w.elemente[id]?.isHidden = !mehrere }
        return w.zeigeModal()
    }

    /// «Gehe zu» (Strg+G): Zeile oder Zeichen.
    static func geheZu(_ e: Editor) {
        guard let d = WinDialog("gehezu") else { return }
        d.gruppen = [["IDC_RADIO_GOTOLINE", "IDC_RADIO_GOTOOFFSET"]]
        func aktualisiere() {
            let zeile = d.haken("IDC_RADIO_GOTOLINE")
            d.setzeText("ID_CURRLINE_EDIT", zeile ? "\(e.aktuelleZeile)" : "\(e.marke)")
            d.setzeText("ID_LASTLINE", zeile ? "\(e.zeilenanzahl)" : "\(e.laenge)")
        }
        d.setzeHaken("IDC_RADIO_GOTOLINE", !ablage.bool(forKey: "GeheZuZeichen"))
        d.setzeHaken("IDC_RADIO_GOTOOFFSET", ablage.bool(forKey: "GeheZuZeichen"))
        d.eingabe("ID_CURRLINE_EDIT")?.nurLesen = true
        aktualisiere()
        d.gedrueckt = { id in
            switch id {
            case "IDC_RADIO_GOTOLINE", "IDC_RADIO_GOTOOFFSET":
                ablage.set(d.haken("IDC_RADIO_GOTOOFFSET"), forKey: "GeheZuZeichen")
                aktualisiere()
            case "IDOK":
                guard let z = d.zahl("ID_GOLINE_EDIT") else { return NSSound.beep() }
                if d.haken("IDC_RADIO_GOTOLINE") { e.geheZuZeile(z) } else {
                    let stelle = min(max(0, z), e.laenge)
                    e.waehleAus(stelle..<stelle)
                    e.nachricht(SCI_SCROLLCARET)
                }
                d.schliesse()
            default: break
            }
        }
        d.zeige(fokus: "ID_GOLINE_EDIT")
    }

    /// «Ausführen …» (F5): Befehl mit den Variablen von Notepad++, Verlauf, Datei wählen, Variablen einsetzen.
    static func ausfuehren(_ dokument: Dokument?, _ editor: Editor?) {
        guard let d = WinDialog("ausfuehren") else { return }
        let verlauf = ablage.stringArray(forKey: "AusfuehrenVerlauf") ?? []
        d.kombi("IDC_COMBO_RUN_PATH")?.addItems(withObjectValues: verlauf)
        d.setzeText("IDC_COMBO_RUN_PATH", ablage.string(forKey: "LetzterBefehl") ?? "open \"$(FULL_CURRENT_PATH)\"")
        d.aktiv("IDC_BUTTON_SAVE", false)
        (d.elemente["IDC_BUTTON_SAVE"] as? NSButton)?.toolTip = "Gesicherte Befehle im Menü «Ausführen» kennt Kladde noch nicht."
        (d.elemente["IDC_BUTTON_VARIABLES"] as? NSButton)?.toolTip = "Variable einsetzen"
        d.gedrueckt = { id in
            switch id {
            case "IDC_BUTTON_FILE_BROWSER":
                let wahl = NSOpenPanel()
                wahl.beginSheetModal(for: d.fenster) { a in
                    if a == .OK, let u = wahl.url { d.setzeText("IDC_COMBO_RUN_PATH", "\"\(u.path)\"") }
                }
            case "IDC_BUTTON_VARIABLES":
                let m = NSMenu()
                for v in ["FULL_CURRENT_PATH", "CURRENT_DIRECTORY", "FILE_NAME", "NAME_PART", "EXT_PART", "CURRENT_WORD", "CURRENT_LINE", "CURRENT_COLUMN"] {
                    let i = NSMenuItem(title: "$(\(v))", action: #selector(Variablen.gewaehlt(_:)), keyEquivalent: "")
                    i.target = Variablen.gemeinsam
                    m.addItem(i)
                }
                Variablen.gemeinsam.ziel = { t in d.setzeText("IDC_COMBO_RUN_PATH", d.text("IDC_COMBO_RUN_PATH") + t) }
                if let k = d.elemente[id] { m.popUp(positioning: nil, at: NSPoint(x: 0, y: k.bounds.height + 2), in: k) }
            case "IDOK":
                let befehl = d.text("IDC_COMBO_RUN_PATH")
                guard !befehl.isEmpty else { return NSSound.beep() }
                ablage.set(befehl, forKey: "LetzterBefehl")
                ablage.set(Array(([befehl] + verlauf.filter { $0 != befehl }).prefix(20)), forKey: "AusfuehrenVerlauf")
                d.schliesse()
                Werkzeuge.starte(befehl, dokument: dokument, editor: editor)
            default: break
            }
        }
        d.zeige(fokus: "IDC_COMBO_RUN_PATH")
    }

    final class Variablen: NSObject {
        static let gemeinsam = Variablen()
        var ziel: ((String) -> Void)?
        @objc func gewaehlt(_ sender: NSMenuItem) { ziel?(sender.title) }
    }

    /// «Block-Editor» (Alt+C): Text oder Zahlenfolge in jede Zeile.
    static func blockEditor(_ e: Editor) {
        guard let d = WinDialog("spalten") else { return }
        d.gruppen = [["IDC_COL_TEXT_RADIO", "IDC_COL_NUM_RADIO"],
                     ["IDC_COL_DEC_RADIO", "IDC_COL_HEX_RADIO", "IDC_COL_OCT_RADIO", "IDC_COL_BIN_RADIO"]]
        let zahlen = ablage.bool(forKey: "SpalteZahlen")
        d.setzeHaken("IDC_COL_TEXT_RADIO", !zahlen)
        d.setzeHaken("IDC_COL_NUM_RADIO", zahlen)
        d.setzeText("IDC_COL_TEXT_EDIT", ablage.string(forKey: "SpalteText") ?? "")
        d.setzeText("IDC_COL_INITNUM_EDIT", "\(ablage.object(forKey: "SpalteAnfang") as? Int ?? 1)")
        d.setzeText("IDC_COL_INCREASENUM_EDIT", "\(ablage.object(forKey: "SpalteSchritt") as? Int ?? 1)")
        d.setzeText("IDC_COL_REPEATNUM_EDIT", "\(ablage.object(forKey: "SpalteWiederholen") as? Int ?? 1)")
        d.auswahl("IDC_COL_LEADING_COMBO")?.gewaehlt = ablage.integer(forKey: "SpalteFuehrend")
        d.auswahl("IDC_COL_HEXUC_COMBO")?.eintraege = ["A-F", "a-f"]
        d.auswahl("IDC_COL_HEXUC_COMBO")?.gewaehlt = ablage.bool(forKey: "SpalteHexKlein") ? 1 : 0
        let formate = ["IDC_COL_DEC_RADIO", "IDC_COL_HEX_RADIO", "IDC_COL_OCT_RADIO", "IDC_COL_BIN_RADIO"]
        let format = min(max(0, ablage.integer(forKey: "SpalteFormat")), 3)
        for (i, f) in formate.enumerated() { d.setzeHaken(f, i == format) }
        func schalte() {
            let z = d.haken("IDC_COL_NUM_RADIO")
            d.aktiv("IDC_COL_TEXT_EDIT", !z)
            for id in ["IDC_COL_INITNUM_EDIT", "IDC_COL_INCREASENUM_EDIT", "IDC_COL_REPEATNUM_EDIT", "IDC_COL_LEADING_COMBO"] + formate {
                d.aktiv(id, z)
            }
            d.aktiv("IDC_COL_HEXUC_COMBO", z && d.haken("IDC_COL_HEX_RADIO"))
        }
        schalte()
        d.gedrueckt = { id in
            guard id == "IDOK" else { return schalte() }
            let zahlen = d.haken("IDC_COL_NUM_RADIO")
            let fi = formate.firstIndex { d.haken($0) } ?? 0
            ablage.set(zahlen, forKey: "SpalteZahlen")
            ablage.set(d.text("IDC_COL_TEXT_EDIT"), forKey: "SpalteText")
            ablage.set(d.zahl("IDC_COL_INITNUM_EDIT") ?? 1, forKey: "SpalteAnfang")
            ablage.set(d.zahl("IDC_COL_INCREASENUM_EDIT") ?? 1, forKey: "SpalteSchritt")
            ablage.set(d.zahl("IDC_COL_REPEATNUM_EDIT") ?? 1, forKey: "SpalteWiederholen")
            ablage.set(d.auswahl("IDC_COL_LEADING_COMBO")?.gewaehlt ?? 0, forKey: "SpalteFuehrend")
            ablage.set(fi, forKey: "SpalteFormat")
            ablage.set(d.auswahl("IDC_COL_HEXUC_COMBO")?.gewaehlt == 1, forKey: "SpalteHexKlein")
            if zahlen {
                var folge = Zahlenfolge()
                folge.anfang = d.zahl("IDC_COL_INITNUM_EDIT") ?? 1
                folge.schritt = d.zahl("IDC_COL_INCREASENUM_EDIT") ?? 1
                folge.wiederholen = max(1, d.zahl("IDC_COL_REPEATNUM_EDIT") ?? 1)
                folge.fuehrend = Zahlenfolge.Fuehrend(rawValue: d.auswahl("IDC_COL_LEADING_COMBO")?.gewaehlt ?? 0) ?? .keine
                folge.basis = [10, 16, 8, 2][fi]
                folge.grossbuchstaben = d.auswahl("IDC_COL_HEXUC_COMBO")?.gewaehlt != 1
                _ = e.fuegeInSpalteEin { folge.texte($0) }
            } else {
                let t = d.text("IDC_COL_TEXT_EDIT")
                guard !t.isEmpty else { return NSSound.beep() }
                _ = e.fuegeInSpalteEin { Array(repeating: t, count: $0) }
            }
            d.schliesse()
        }
        d.zeige(fokus: zahlen ? "IDC_COL_INITNUM_EDIT" : "IDC_COL_TEXT_EDIT")
    }

    /// «Makro mehrfach ausführen»: n-mal oder bis zum Ende der Datei.
    static func makroMehrfach(_ e: Editor) {
        let makros = Makros.gemeinsam
        if makros.nimmtAuf { makros.beende() }
        guard let d = WinDialog("makro") else { return }
        d.gruppen = [["IDC_M_RUN_MULTI", "IDC_M_RUN_EOF"]]
        d.auswahl("IDC_MACRO_COMBO")?.eintraege = ["Aktuell aufgenommenes Makro"] + makros.gesicherte.map(\.name)
        d.setzeHaken("IDC_M_RUN_MULTI", true)
        d.setzeText("IDC_M_RUN_TIMES", "1")
        d.gedrueckt = { id in
            guard id == "IDOK" else { return }
            let i = d.auswahl("IDC_MACRO_COMBO")?.gewaehlt ?? 0
            let schritte = i == 0 ? makros.aktuelles : makros.gesicherte[i - 1].schritte
            d.schliesse()
            if d.haken("IDC_M_RUN_EOF") { makros.spieleBisEnde(schritte, in: e) }
            else { makros.spiele(schritte, in: e, mal: max(1, min(d.zahl("IDC_M_RUN_TIMES") ?? 1, 100_000))) }
        }
        d.zeige(fokus: "IDC_M_RUN_TIMES")
    }

    /// «MD5/SHA-…-Hashwert erstellen»: Ergebnis wächst beim Tippen mit.
    static func hashAusText(art: String, titel: String) {
        guard let d = WinDialog("hash") else { return }
        d.fenster.title = titel
        d.eingabe("IDC_HASH_RESULT_FOMTEXT_EDIT")?.nurLesen = true
        func rechne() {
            let t = d.text("IDC_HASH_TEXT_EDIT")
            let teile = d.haken("IDC_HASH_EACHLINE_CHECK") ? t.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init) : [t]
            d.setzeText("IDC_HASH_RESULT_FOMTEXT_EDIT", t.isEmpty ? "" : teile.map { Werkzeuge.wert(art, Data($0.utf8)) }.joined(separator: "\n"))
        }
        d.gedrueckt = { id in
            if id == "IDC_HASH_FROMTEXT_TOCLIPBOARD_BUTTON" { Werkzeuge.zwischenablage(d.text("IDC_HASH_RESULT_FOMTEXT_EDIT")) } else { rechne() }
        }
        d.zeige(fokus: "IDC_HASH_TEXT_EDIT")
    }
}
