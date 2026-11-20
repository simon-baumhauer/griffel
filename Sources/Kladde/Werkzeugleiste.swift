import AppKit

/// Die Werkzeugleiste von Notepad++ (toolBarIcons in Notepad_plus.cpp): dieselben
/// Knöpfe in derselben Reihenfolge und Gruppierung, mit den Symbolen von
/// Notepad++. Hell klassisch (wie dort voreingestellt), dunkel Fluent.
final class Werkzeugleiste: NSView {
    /// Symbolname, Befehl; nil ist ein Trenner.
    static let knoepfe: [(String, String)?] = [
        ("newFile", "IDM_FILE_NEW"), ("openFile", "IDM_FILE_OPEN"), ("saveFile", "IDM_FILE_SAVE"),
        ("saveAll", "IDM_FILE_SAVEALL"), ("closeFile", "IDM_FILE_CLOSE"), ("closeAll", "IDM_FILE_CLOSEALL"),
        ("print", "IDM_FILE_PRINT"), nil,
        ("cut", "IDM_EDIT_CUT"), ("copy", "IDM_EDIT_COPY"), ("paste", "IDM_EDIT_PASTE"), nil,
        ("undo", "IDM_EDIT_UNDO"), ("redo", "IDM_EDIT_REDO"), nil,
        ("find", "IDM_SEARCH_FIND"), ("findReplace", "IDM_SEARCH_REPLACE"), nil,
        ("zoomIn", "IDM_VIEW_ZOOMIN"), ("zoomOut", "IDM_VIEW_ZOOMOUT"), nil,
        ("syncV", "IDM_VIEW_SYNSCROLLV"), ("syncH", "IDM_VIEW_SYNSCROLLH"), nil,
        ("wrap", "IDM_VIEW_WRAP"), ("allChars", "IDM_VIEW_ALL_CHARACTERS"), ("indentGuide", "IDM_VIEW_INDENT_GUIDE"), nil,
        ("udl", "IDM_LANG_USER_DLG"), ("docMap", "IDM_VIEW_DOC_MAP"), ("docList", "IDM_VIEW_DOCLIST"),
        ("funcList", "IDM_VIEW_FUNC_LIST"), ("fileBrowser", "IDM_VIEW_FILEBROWSER"), nil,
        ("monitoring", "IDM_VIEW_MONITORING"), nil,
        ("startRecord", "IDM_MACRO_STARTRECORDINGMACRO"), ("stopRecord", "IDM_MACRO_STOPRECORDINGMACRO"),
        ("playRecord", "IDM_MACRO_PLAYBACKRECORDEDMACRO"), ("playRecord_m", "IDM_MACRO_RUNMULTIMACRODLG"),
        ("saveRecord", "IDM_MACRO_SAVECURRENTMACRO"),
    ]

    /// Fragt je Befehl: ausführbar? eingeschaltet?
    var zustand: (String) -> (moeglich: Bool, an: Bool) = { _ in (true, false) }
    var ausfuehren: (String) -> Void = { _ in }

    private var stapel = NSStackView()
    private var knopfListe: [Knopf] = []
    static let hoehe: CGFloat = 28

    override init(frame: NSRect) {
        super.init(frame: frame)
        heightAnchor.constraint(equalToConstant: Self.hoehe).isActive = true
        stapel.orientation = .horizontal
        stapel.spacing = 0
        stapel.edgeInsets = NSEdgeInsets(top: 2, left: 3, bottom: 2, right: 3)
        stapel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stapel)
        NSLayoutConstraint.activate([
            stapel.leadingAnchor.constraint(equalTo: leadingAnchor),
            stapel.topAnchor.constraint(equalTo: topAnchor),
            stapel.bottomAnchor.constraint(equalTo: bottomAnchor),
            stapel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
        ])
        baue()
        setAccessibilityRole(.toolbar)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Werkzeugleiste entsteht nur im Code") }

    func baue() {
        stapel.arrangedSubviews.forEach { $0.removeFromSuperview() }
        knopfListe = []
        for k in Self.knoepfe {
            guard let (symbol, befehl) = k else {
                let trenner = Trenner()
                trenner.widthAnchor.constraint(equalToConstant: 8).isActive = true
                stapel.addArrangedSubview(trenner)
                continue
            }
            let knopf = Knopf(symbol: symbol, befehl: befehl, aufklappen: Self.aufklappmenue(befehl))
            knopf.setAccessibilityLabel(Oberflaeche.gemeinsam.titel(befehl).replacingOccurrences(of: " …", with: ""))
            knopf.target = self
            knopf.action = #selector(gedrueckt(_:))
            stapel.addArrangedSubview(knopf)
            knopfListe.append(knopf)
        }
        aktualisiere()
    }

    @objc private func gedrueckt(_ sender: Knopf) { ausfuehren(sender.befehl) }

    // MARK: Aufklappmenüs

    /// Ein Befehl aus dem Hauptmenü, mit Titel, Kürzel und Beschreibung wie dort.
    private static func befehl(_ id: String) -> NSMenuItem {
        Befehlsmenue.eintrag(id: id, titel: Oberflaeche.gemeinsam.titel(id), kuerzel: Oberflaeche.gemeinsam.kuerzel(id))
    }

    private static func menue(_ ids: [String?]) -> NSMenu {
        let m = NSMenu()
        m.autoenablesItems = true
        for id in ids { m.addItem(id.map(befehl) ?? .separator()) }
        return m
    }

    /// Welche Knöpfe ein ▾ haben und was darin steht: die verwandten Befehle
    /// aus dem Hauptmenü, beim Öffnen die zuletzt benutzten Dateien, beim
    /// Abspielen die gesicherten Makros.
    static func aufklappmenue(_ befehl: String) -> (() -> NSMenu)? {
        switch befehl {
        case "IDM_FILE_OPEN":
            return {
                let m = NSMenu()
                let zuletzt = NSMenu()
                ZuletztBenutzt.gemeinsam.menuNeedsUpdate(zuletzt)
                if zuletzt.items.contains(where: { $0.representedObject is URL }) {
                    let kopf = NSMenuItem(title: "Zuletzt benutzt", action: nil, keyEquivalent: "")
                    kopf.isEnabled = false
                    m.addItem(kopf)
                    for i in zuletzt.items where i.representedObject is URL { zuletzt.removeItem(i); m.addItem(i) }
                    m.addItem(.separator())
                }
                for id in ["IDM_FILE_OPEN", "IDM_FILE_OPENFOLDERASWORKSPACE", "IDM_FILE_RELOAD", "IDM_FILE_LOADSESSION"] {
                    m.addItem(Self.befehl(id))
                }
                return m
            }
        case "IDM_FILE_SAVE":
            return { menue(["IDM_FILE_SAVE", "IDM_FILE_SAVEAS", "IDM_FILE_SAVECOPYAS", "IDM_FILE_SAVEALL", nil, "IDM_FILE_SAVESESSION"]) }
        case "IDM_FILE_CLOSE":
            return {
                menue(["IDM_FILE_CLOSE", "IDM_FILE_CLOSEALL", nil, "IDM_FILE_CLOSEALL_BUT_CURRENT", "IDM_FILE_CLOSEALL_BUT_PINNED",
                       "IDM_FILE_CLOSEALL_TOLEFT", "IDM_FILE_CLOSEALL_TORIGHT", "IDM_FILE_CLOSEALL_UNCHANGED"])
            }
        case "IDM_FILE_PRINT": return { menue(["IDM_FILE_PRINT", "IDM_FILE_PRINTNOW"]) }
        case "IDM_SEARCH_FIND":
            return {
                menue(["IDM_SEARCH_FIND", "IDM_SEARCH_REPLACE", "IDM_SEARCH_FINDINFILES", "IDM_SEARCH_MARK", nil,
                       "IDM_SEARCH_FINDINCREMENT", "IDM_SEARCH_FINDNEXT", "IDM_SEARCH_FINDPREV", nil, "IDM_SEARCH_GOTOLINE"])
            }
        case "IDM_VIEW_ZOOMIN": return { menue(["IDM_VIEW_ZOOMIN", "IDM_VIEW_ZOOMOUT", "IDM_VIEW_ZOOMRESTORE"]) }
        case "IDM_VIEW_ALL_CHARACTERS":
            return { menue(["IDM_VIEW_TAB_SPACE", "IDM_VIEW_EOL", "IDM_VIEW_ALL_CHARACTERS", nil, "IDM_VIEW_INDENT_GUIDE", "IDM_VIEW_WRAP_SYMBOL"]) }
        case "IDM_VIEW_FUNC_LIST":
            return { menue(["IDM_VIEW_FUNC_LIST", "IDM_VIEW_DOC_MAP", "IDM_VIEW_DOCLIST", "IDM_VIEW_FILEBROWSER"]) }
        case "IDM_MACRO_PLAYBACKRECORDEDMACRO":
            return {
                let m = menue(["IDM_MACRO_PLAYBACKRECORDEDMACRO", "IDM_MACRO_RUNMULTIMACRODLG"])
                let gesicherte = Makros.gemeinsam.gesicherte
                if !gesicherte.isEmpty {
                    m.addItem(.separator())
                    let kopf = NSMenuItem(title: "Gesicherte Makros", action: nil, keyEquivalent: "")
                    kopf.isEnabled = false
                    m.addItem(kopf)
                    for makro in gesicherte {
                        let i = NSMenuItem(title: makro.name, action: #selector(MakroMenue.spiele(_:)), keyEquivalent: "")
                        i.target = MakroMenue.gemeinsam
                        i.representedObject = makro.name
                        m.addItem(i)
                    }
                }
                return m
            }
        default: return nil
        }
    }

    // MARK: Rechtsklick: Symbolsatz wie in den Einstellungen von Notepad++

    override func menu(for event: NSEvent) -> NSMenu? {
        let m = NSMenu()
        let kopf = NSMenuItem(title: "Symbole der Werkzeugleiste", action: nil, keyEquivalent: "")
        kopf.isEnabled = false
        m.addItem(kopf)
        for (satz, titel) in [("standard", "Klein (klassisch)"), ("fluent", "Fluent UI: klein"), ("fluentGefuellt", "Fluent UI: klein, gefüllt")] {
            let i = NSMenuItem(title: titel, action: #selector(symbolsatzGewaehlt(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = satz
            i.state = Einstellungen.symbolsatz == satz ? .on : .off
            m.addItem(i)
        }
        return m
    }

    @objc private func symbolsatzGewaehlt(_ sender: NSMenuItem) {
        guard let satz = sender.representedObject as? String else { return }
        Einstellungen.symbolsatz = satz
        aktualisiere()
    }

    func aktualisiere() {
        let dunkel = Hauptfenster.istDunkel
        let satz = Einstellungen.symbolsatz
        for k in knopfListe {
            let z = zustand(k.befehl)
            k.moeglich = z.moeglich
            k.an = z.an
            k.bild = Symbole.werkzeug(k.symbol, satz: satz, dunkel: dunkel)
            k.bildAus = satz == "standard" && !dunkel ? nil : Symbole.werkzeug(k.symbol, satz: satz, dunkel: dunkel, aus: true)
            k.needsDisplay = true
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        (Hauptfenster.istDunkel ? NSColor(rgb: 0x202020) : NSColor(rgb: 0xF0F0F0)).setFill()
        bounds.fill()
        (Hauptfenster.istDunkel ? NSColor(rgb: 0x404040) : NSColor(rgb: 0xD9D9D9)).setFill()
        NSRect(x: 0, y: 0, width: bounds.width, height: 1).fill()
    }

    /// Ein flacher Knopf wie in der Windows-Werkzeugleiste: Kasten nur beim
    /// Überfahren, Drücken oder wenn eingeschaltet.
    final class Knopf: NSControl {
        let symbol: String
        let befehl: String
        /// Mit ▾: was rechts daneben aufklappt.
        let aufklappen: (() -> NSMenu)?
        var bild: NSImage?
        var bildAus: NSImage?
        var moeglich = true
        var an = false
        private var ueber = false
        private var unten = false
        private var pfeilOffen = false
        static let pfeilBreite: CGFloat = 11

        init(symbol: String, befehl: String, aufklappen: (() -> NSMenu)? = nil) {
            self.symbol = symbol
            self.befehl = befehl
            self.aufklappen = aufklappen
            let breite = 23 + (aufklappen == nil ? 0 : Self.pfeilBreite)
            super.init(frame: NSRect(x: 0, y: 0, width: breite, height: 22))
            widthAnchor.constraint(equalToConstant: breite).isActive = true
            heightAnchor.constraint(equalToConstant: 22).isActive = true
            setAccessibilityRole(.button)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        }

        override func mouseEntered(with event: NSEvent) {
            ueber = true
            needsDisplay = true
            Hinweis.gemeinsam.plane(
                fuer: self, titel: Oberflaeche.gemeinsam.titel(befehl).replacingOccurrences(of: " …", with: ""),
                kuerzel: Beschreibung.kuerzel(befehl), text: Beschreibung.text(befehl))
        }

        override func mouseExited(with event: NSEvent) {
            ueber = false
            needsDisplay = true
            Hinweis.gemeinsam.verberge()
        }

        private var knopfBreite: CGFloat { bounds.width - (aufklappen == nil ? 0 : Self.pfeilBreite) }

        override func mouseDown(with event: NSEvent) {
            Hinweis.gemeinsam.verberge()
            let punkt = convert(event.locationInWindow, from: nil)
            if let aufklappen, punkt.x >= knopfBreite {
                // Das Menü klappt unter dem ganzen Knopf auf, bündig links.
                pfeilOffen = true
                needsDisplay = true
                aufklappen().popUp(positioning: nil, at: NSPoint(x: 0, y: -3), in: self)
                pfeilOffen = false
                ueber = bounds.contains(convert(window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil))
                needsDisplay = true
                return
            }
            guard moeglich else { return }
            unten = true
            needsDisplay = true
        }

        override func mouseUp(with event: NSEvent) {
            guard unten else { return }
            unten = false
            needsDisplay = true
            let punkt = convert(event.locationInWindow, from: nil)
            if bounds.contains(punkt), punkt.x < knopfBreite, let action, let target {
                NSApp.sendAction(action, to: target, from: self)
            }
        }

        override func draw(_ dirtyRect: NSRect) {
            let dunkel = Hauptfenster.istDunkel
            let kasten = bounds.insetBy(dx: 0.5, dy: 0.5)
            if pfeilOffen || moeglich && (unten || an || ueber) {
                let (fuell, rand): (Int, Int) = unten
                    ? (dunkel ? (0x3D5A73, 0x5A8AB0) : (0xCCE8FF, 0x99D1FF))
                    : an ? (dunkel ? (0x354A5E, 0x4F7393) : (0xCCE8FF, 0x99D1FF))
                    : (dunkel ? (0x2E3B47, 0x4F7393) : (0xE5F3FF, 0xCCE8FF))
                NSColor(rgb: fuell).setFill()
                kasten.fill()
                NSColor(rgb: rand).setStroke()
                NSBezierPath(rect: kasten).stroke()
                if aufklappen != nil {
                    NSBezierPath.strokeLine(from: NSPoint(x: knopfBreite + 0.5, y: 2), to: NSPoint(x: knopfBreite + 0.5, y: bounds.height - 2))
                }
            }
            if aufklappen != nil {
                // Das ▾ wie in Windows-Werkzeugleisten: ein kleines gefülltes Dreieck.
                let mitte = NSPoint(x: knopfBreite + Self.pfeilBreite / 2, y: bounds.midY)
                let pfeil = NSBezierPath()
                pfeil.move(to: NSPoint(x: mitte.x - 3, y: mitte.y + 1.5))
                pfeil.line(to: NSPoint(x: mitte.x + 3, y: mitte.y + 1.5))
                pfeil.line(to: NSPoint(x: mitte.x, y: mitte.y - 1.5))
                pfeil.close()
                (dunkel ? NSColor(rgb: 0xC8C8C8) : NSColor(rgb: 0x404040)).setFill()
                pfeil.fill()
            }
            let b = (!moeglich ? bildAus : nil) ?? bild
            b?.draw(
                in: NSRect(x: (knopfBreite - 16) / 2, y: (bounds.height - 16) / 2, width: 16, height: 16),
                from: .zero, operation: .sourceOver, fraction: moeglich || bildAus != nil ? 1 : 0.35)
        }
    }

    final class Trenner: NSView {
        override func draw(_ dirtyRect: NSRect) {
            (Hauptfenster.istDunkel ? NSColor(rgb: 0x505050) : NSColor(rgb: 0xC8C8C8)).setFill()
            NSRect(x: bounds.midX - 0.5, y: 4, width: 1, height: bounds.height - 8).fill()
        }
    }
}
