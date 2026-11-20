import AppKit
import ScintillaBruecke

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
            t.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
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

/// Ein Dialog nach einer .rc-Beschreibung von Notepad++ (Oberflaeche.dialoge):
/// dieselben Elemente an derselben Stelle, im Windows-Stil, als Fenster über
/// dem Hauptfenster. Die Logik setzt der Aufrufer über `gedrueckt` und die
/// Zugriffe auf die Elemente.
final class WinDialog: NSObject, NSWindowDelegate {
    let fenster: NSPanel
    private(set) var elemente: [String: NSView] = [:]
    /// Optionsfelder, die sich gegenseitig ausschliessen.
    var gruppen: [[String]] = []
    /// Ein Knopf (Kennung wie IDOK) oder ein Kästchen wurde gedrückt.
    var gedrueckt: ((String) -> Void)?
    private static var offen: [WinDialog] = []

    private static let sx: CGFloat = 1.62
    private static let sy: CGFloat = 1.78

    init?(_ schluessel: String) {
        guard let d = Oberflaeche.gemeinsam.dialoge?[schluessel] else { return nil }
        let breite = CGFloat(d.groesse[0]) * Self.sx + 4
        let hoehe = CGFloat(d.groesse[1]) * Self.sy + 4
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
        for e in d.elemente { baue(e, in: flaeche) }
        // Kästchen und Texte enden vor dem nächsten Element derselben Zeile
        // (die Mac-Schrift ist breiter; sonst läge die Beschriftung darunter).
        let alle = Array(elemente.values).filter { !($0 is WinGruppe) }
        for v in alle where v is WinKaestchen || v is WinText {
            let rechts = alle.filter { $0 !== v && $0.frame.minX > v.frame.minX + 10 && $0.frame.minX < v.frame.maxX
                && $0.frame.maxY > v.frame.minY + 3 && $0.frame.minY < v.frame.maxY - 3 }.map(\.frame.minX).min()
            if let rechts { v.frame.size.width = rechts - v.frame.minX - 4 }
        }
    }

    private func rechteck(_ e: Oberflaeche.Element, hoehe: CGFloat? = nil) -> NSRect {
        NSRect(x: CGFloat(e.x) * Self.sx + 2, y: CGFloat(e.y) * Self.sy + 2, width: CGFloat(e.b) * Self.sx, height: hoehe ?? CGFloat(e.h) * Self.sy)
    }

    private func baue(_ e: Oberflaeche.Element, in flaeche: NSView) {
        let text = Mac.text(e.text)
        let stil = e.stil ?? ""
        let v: NSView
        switch e.art {
        case "LTEXT", "RTEXT", "CTEXT":
            let t = WinText(text, rechts: e.art == "RTEXT")
            if e.art == "CTEXT" { t.alignment = .center }
            v = t
            var r = rechteck(e, hoehe: 18).offsetBy(dx: 0, dy: -3)
            if e.art == "RTEXT" { r = NSRect(x: max(2, r.minX - 14), y: r.minY, width: r.maxX - max(2, r.minX - 14), height: r.height) }
            v.frame = r
        case "EDITTEXT":
            let mehr = stil.contains("MULTILINE")
            let f = WinEingabe(mehrzeilig: mehr)
            f.nurLesen = stil.contains("READONLY")
            f.geaendert = { [weak self] in self?.gedrueckt?(e.id) }
            v = f
            v.frame = mehr ? rechteck(e) : rechteck(e, hoehe: 23).offsetBy(dx: 0, dy: -2)
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
            v.frame = rechteck(e, hoehe: 23).offsetBy(dx: 0, dy: -2)
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
            v.frame = e.h > 15 ? rechteck(e) : rechteck(e, hoehe: 25).offsetBy(dx: 0, dy: -1)
        case "CHECKBOX", "RADIO":
            let k = WinKaestchen(titel: text, rund: e.art == "RADIO", target: self, action: #selector(knopf(_:)))
            v = k
            v.frame = rechteck(e, hoehe: 18).offsetBy(dx: 0, dy: -3)
        case "GROUPBOX":
            v = WinGruppe(titel: text)
            v.frame = rechteck(e).offsetBy(dx: 0, dy: -4)
        default:
            return
        }
        v.identifier = NSUserInterfaceItemIdentifier(e.id)
        if e.art == "GROUPBOX" { flaeche.addSubview(v, positioned: .below, relativeTo: nil) } else { flaeche.addSubview(v) }
        elemente[e.id] = v
    }

    @objc private func knopf(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        if let gruppe = gruppen.first(where: { $0.contains(id) }) {
            for g in gruppe { setzeHaken(g, g == id) }
        }
        if id == "IDCANCEL" { return schliesse() }
        gedrueckt?(id)
    }

    // MARK: Zugriff

    func text(_ id: String) -> String {
        (elemente[id] as? WinEingabe)?.stringValue ?? (elemente[id] as? WinKombi)?.stringValue ?? (elemente[id] as? NSTextField)?.stringValue ?? ""
    }

    func setzeText(_ id: String, _ t: String) {
        if let f = elemente[id] as? WinEingabe { f.stringValue = t }
        else if let f = elemente[id] as? WinKombi { f.stringValue = t }
        else if let f = elemente[id] as? NSTextField { f.stringValue = t }
        else if let k = elemente[id] as? NSButton { k.title = t }
    }

    func haken(_ id: String) -> Bool { (elemente[id] as? NSButton)?.state == .on }
    func setzeHaken(_ id: String, _ an: Bool) { (elemente[id] as? NSButton)?.state = an ? .on : .off }
    func zahl(_ id: String) -> Int? { Int(text(id).trimmingCharacters(in: .whitespaces)) }
    func auswahl(_ id: String) -> WinAuswahl? { elemente[id] as? WinAuswahl }
    func kombi(_ id: String) -> WinKombi? { elemente[id] as? WinKombi }
    func eingabe(_ id: String) -> WinEingabe? { elemente[id] as? WinEingabe }

    func aktiv(_ id: String, _ an: Bool) {
        if let c = elemente[id] as? NSControl { c.isEnabled = an }
        (elemente[id] as? WinAuswahl)?.isEnabled = an
        (elemente[id] as? WinEingabe)?.nurLesen = !an
    }

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

    func schliesse() {
        fenster.parent?.removeChildWindow(fenster)
        fenster.orderOut(nil)
        Self.offen.removeAll { $0 === self }
        if let e = Hauptfenster.gemeinsam.aktiv { Hauptfenster.gemeinsam.window?.makeFirstResponder(e.ansicht.content()) }
    }

    func windowWillClose(_ notification: Notification) {
        fenster.parent?.removeChildWindow(fenster)
        Self.offen.removeAll { $0 === self }
    }
}

// MARK: - Die Dialoge

enum Dialoge {
    private static let ablage = UserDefaults.standard

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
