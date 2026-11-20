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
            let knopf = Knopf(symbol: symbol, befehl: befehl)
            knopf.toolTip = Oberflaeche.gemeinsam.titel(befehl).replacingOccurrences(of: " …", with: "")
            knopf.setAccessibilityLabel(knopf.toolTip)
            knopf.target = self
            knopf.action = #selector(gedrueckt(_:))
            stapel.addArrangedSubview(knopf)
            knopfListe.append(knopf)
        }
        aktualisiere()
    }

    @objc private func gedrueckt(_ sender: Knopf) { ausfuehren(sender.befehl) }

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
        var bild: NSImage?
        var bildAus: NSImage?
        var moeglich = true
        var an = false
        private var ueber = false
        private var unten = false

        init(symbol: String, befehl: String) {
            self.symbol = symbol
            self.befehl = befehl
            super.init(frame: NSRect(x: 0, y: 0, width: 23, height: 22))
            widthAnchor.constraint(equalToConstant: 23).isActive = true
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

        override func mouseEntered(with event: NSEvent) { ueber = true; needsDisplay = true }
        override func mouseExited(with event: NSEvent) { ueber = false; needsDisplay = true }

        override func mouseDown(with event: NSEvent) {
            guard moeglich else { return }
            unten = true
            needsDisplay = true
        }

        override func mouseUp(with event: NSEvent) {
            guard unten else { return }
            unten = false
            needsDisplay = true
            if bounds.contains(convert(event.locationInWindow, from: nil)), let action, let target {
                NSApp.sendAction(action, to: target, from: self)
            }
        }

        override func draw(_ dirtyRect: NSRect) {
            let dunkel = Hauptfenster.istDunkel
            let kasten = bounds.insetBy(dx: 0.5, dy: 0.5)
            if moeglich, unten || an || ueber {
                let (fuell, rand): (Int, Int) = unten
                    ? (dunkel ? (0x3D5A73, 0x5A8AB0) : (0xCCE8FF, 0x99D1FF))
                    : an ? (dunkel ? (0x354A5E, 0x4F7393) : (0xCCE8FF, 0x99D1FF))
                    : (dunkel ? (0x2E3B47, 0x4F7393) : (0xE5F3FF, 0xCCE8FF))
                NSColor(rgb: fuell).setFill()
                kasten.fill()
                NSColor(rgb: rand).setStroke()
                NSBezierPath(rect: kasten).stroke()
            }
            let b = (!moeglich ? bildAus : nil) ?? bild
            b?.draw(
                in: NSRect(x: (bounds.width - 16) / 2, y: (bounds.height - 16) / 2, width: 16, height: 16),
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
