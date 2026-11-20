import AppKit

/// Der Dialog «Optionen» (Einstellungen → Optionen …, ⌘,) wie in Notepad++:
/// links die Liste der Kategorien mit den Namen von dort, rechts die Seite,
/// unten «Schließen». Jede Änderung gilt sofort.
final class EinstellungsFenster: NSWindowController, NSWindowDelegate {
    static let gemeinsam = EinstellungsFenster()

    private let liste = WinListe()
    private let seite = WinFlaeche()
    private var seiten: [(String, () -> [Zeile])] = []

    /// Ein Element einer Seite: Gruppe, Kästchen, Auswahl, Zahl oder Knopf.
    enum Zeile {
        case gruppe(String)
        case haken(String, get: () -> Bool, set: (Bool) -> Void)
        case optionen(String?, [String], get: () -> Int, set: (Int) -> Void)
        case auswahl(String, [String], get: () -> Int, set: (Int) -> Void)
        case zahl(String, get: () -> Int, set: (Int) -> Void, bereich: ClosedRange<Int>)
        case knopf(String, () -> Void)
        case hinweis(String)
    }

    private init() {
        let fenster = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 760, height: 480), styleMask: [.titled, .closable],
                              backing: .buffered, defer: true)
        fenster.title = Oberflaeche.gemeinsam.texte["Preference.title"] ?? "Optionen"
        fenster.isRestorable = false
        fenster.isReleasedWhenClosed = false
        super.init(window: fenster)
        fenster.delegate = self
        let flaeche = WinFlaeche(frame: NSRect(x: 0, y: 0, width: 760, height: 480))
        fenster.contentView = flaeche
        liste.frame = NSRect(x: 12, y: 12, width: 170, height: 418)
        seite.frame = NSRect(x: 196, y: 12, width: 552, height: 418)
        let zu = WinKnopf()
        zu.title = "Schließen"
        zu.isBordered = false
        zu.frame = NSRect(x: 336, y: 442, width: 100, height: 25)
        zu.target = self
        zu.action = #selector(schliessen)
        zu.keyEquivalent = "\u{1b}"
        for v in [liste, seite, zu] as [NSView] { flaeche.addSubview(v) }
        seiten = Self.inhalt()
        liste.eintraege = seiten.map(\.0)
        liste.gewechselt = { [weak self] i in self?.zeigeSeite(i) }
        zeigeSeite(UserDefaults.standard.integer(forKey: "OptionenSeite"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    @objc private func schliessen() { close() }

    func zeige() {
        window?.backgroundColor = Win.grund
        zeigeSeite(liste.gewaehlt)
        window?.contentView?.needsDisplay = true
        if window?.isVisible != true, let haupt = Hauptfenster.gemeinsam.window, let f = window?.frame {
            window?.setFrameOrigin(NSPoint(x: haupt.frame.midX - f.width / 2, y: haupt.frame.midY - f.height / 2 + 40))
        }
        showWindow(nil)
    }

    // MARK: Seiten

    /// Die Kategorien heissen wie in Notepad++ (german.xml); jede mit dem, was Kladde dort einstellen kann.
    private static func inhalt() -> [(String, () -> [Zeile])] {
        let e = Einstellungen.self
        let schemata = [""] + Sprachdaten.gemeinsam.farbschemaNamen
        let schemaTitel = ["Automatisch (folgt macOS: hell Standard, dunkel DarkModeDefault)"]
            + Sprachdaten.gemeinsam.farbschemaNamen.map { $0 == "DarkModeDefault" ? "Dark Mode Default" : $0 }
        let schriften = [""] + NSFontManager.shared.availableFontFamilies.filter { NSFont(name: $0, size: 12)?.isFixedPitch ?? false }
        let saetze = ["standard", "fluent", "fluentGefuellt"]
        return [
            ("Allgemein", {
                [.gruppe("Beim Start"),
                 .haken("Letzte Sitzung wiederherstellen (alle Tabs, auch ungesicherte)", get: { e.sitzungMerken }, set: { e.sitzungMerken = $0 }),
                 .gruppe("Terminal"),
                 .knopf("Befehl «kladde» installieren …", { NSApp.sendAction(#selector(AppDelegate.installiereBefehl(_:)), to: nil, from: nil) }),
                 .hinweis("Danach öffnet «kladde datei.txt» im Terminal die Datei in Kladde.")]
            }),
            ("Symbolleiste", {
                [.gruppe("Symbole"),
                 .optionen(nil, ["Klein (klassisch)", "Fluent UI: klein", "Fluent UI: klein, gefüllt"],
                           get: { saetze.firstIndex(of: e.symbolsatz) ?? 0 },
                           set: { e.symbolsatz = saetze[$0]; Hauptfenster.gemeinsam.werkzeugleiste.aktualisiere() }),
                 .hinweis("Auch mit Rechtsklick auf die Symbolleiste.")]
            }),
            ("Bearbeiten 1", {
                [.gruppe("Anzeige"),
                 .haken("Zeilennummern anzeigen", get: { e.zeilennummern }, set: { e.zeilennummern = $0 }),
                 .haken("Einrückungslinien anzeigen", get: { e.einrueckungshilfen }, set: { e.einrueckungshilfen = $0 }),
                 .haken("Leerzeichen und Tabulatoren anzeigen", get: { e.leerzeichenZeigen }, set: { e.leerzeichenZeigen = $0 }),
                 .haken("Zeilenende anzeigen", get: { e.zeilenendenZeigen }, set: { e.zeilenendenZeigen = $0 }),
                 .gruppe("Eingabe"),
                 .haken("Neue Zeile übernimmt die Einrückung der vorigen", get: { e.autoEinzug }, set: { e.autoEinzug = $0 })]
            }),
            ("Dunkler Modus", {
                [.gruppe("Farbschema"),
                 .auswahl("Farbschema:", schemaTitel, get: { schemata.firstIndex(of: e.farbschema) ?? 0 }, set: { e.farbschema = schemata[$0] }),
                 .gruppe("Schrift"),
                 .auswahl("Schriftart:", ["Wie im Farbschema"] + schriften.dropFirst(),
                          get: { schriften.firstIndex(of: e.schriftName) ?? 0 }, set: { e.schriftName = schriften[$0] }),
                 .zahl("Schriftgrösse:", get: { e.schriftGroesse }, set: { e.schriftGroesse = $0 }, bereich: 6...72),
                 .hinweis("Die Schriftgrösse gilt nur mit fest gewählter Schriftart.")]
            }),
            ("Sprache", {
                [.gruppe("Tabulator-Einstellungen"),
                 .zahl("Tabulatorgröße:", get: { e.tabbreite }, set: { e.tabbreite = $0 }, bereich: 1...16),
                 .haken("Durch Leerzeichen ersetzen", get: { e.tabsAlsLeerzeichen }, set: { e.tabsAlsLeerzeichen = $0 })]
            }),
            ("Hervorhebung", {
                [.gruppe("Intelligente Hervorhebung"),
                 .haken("Aktivieren (ein ausgewähltes Wort leuchtet überall)", get: { e.smartHighlighting }, set: { e.smartHighlighting = $0 })]
            }),
            ("Autovervollständigung", {
                [.gruppe("Autovervollständigung"),
                 .auswahl("Vorschläge:", ["Aus"] + (1...9).map { "ab \($0). Zeichen" },
                          get: { e.vervollstaendigenAb }, set: { e.vervollstaendigenAb = $0 }),
                 .gruppe("Automatisch einfügen"),
                 .haken("Klammern und Anführungszeichen schliessen ( ) [ ] { } \" '", get: { e.klammernSchliessen }, set: { e.klammernSchliessen = $0 })]
            }),
        ]
    }

    func zeigeSeite(_ i: Int) {
        let i = seiten.indices.contains(i) ? i : 0
        liste.gewaehlt = i
        UserDefaults.standard.set(i, forKey: "OptionenSeite")
        seite.subviews.forEach { $0.removeFromSuperview() }
        var y: CGFloat = 4
        var gruppe: WinGruppe?
        func schliesseGruppe() {
            if let g = gruppe { g.frame.size.height = y - g.frame.minY + 6; y += 14 }
            gruppe = nil
        }
        for z in seiten[i].1() {
            switch z {
            case .gruppe(let t):
                schliesseGruppe()
                let g = WinGruppe(titel: t)
                g.frame = NSRect(x: 0, y: y, width: seite.bounds.width, height: 30)
                seite.addSubview(g, positioned: .below, relativeTo: nil)
                gruppe = g
                y += 24
            case let .haken(t, get, set):
                let k = schalter(titel: t, rund: false) { set($0 == 0) }
                k.state = get() ? .on : .off
                k.frame = NSRect(x: 14, y: y, width: seite.bounds.width - 28, height: 18)
                seite.addSubview(k)
                y += 24
            case let .optionen(_, titel, get, set):
                var knoepfe: [WinKaestchen] = []
                for (n, t) in titel.enumerated() {
                    let k = schalter(titel: t, rund: true) { _ in
                        for (m, o) in knoepfe.enumerated() { o.state = m == n ? .on : .off }
                        set(n)
                    }
                    k.state = get() == n ? .on : .off
                    k.frame = NSRect(x: 14, y: y, width: seite.bounds.width - 28, height: 18)
                    seite.addSubview(k)
                    knoepfe.append(k)
                    y += 24
                }
            case let .auswahl(t, werte, get, set):
                let l = WinText(t, rechts: false)
                l.frame = NSRect(x: 14, y: y + 2, width: 110, height: 18)
                let a = WinAuswahl()
                a.eintraege = werte
                a.gewaehlt = get()
                a.geaendert = { [weak a] in set(a?.gewaehlt ?? 0) }
                a.frame = NSRect(x: 128, y: y, width: seite.bounds.width - 142, height: 23)
                seite.addSubview(l)
                seite.addSubview(a)
                y += 30
            case let .zahl(t, get, set, bereich):
                let l = WinText(t, rechts: false)
                l.frame = NSRect(x: 14, y: y + 2, width: 110, height: 18)
                let f = WinEingabe(mehrzeilig: false)
                f.stringValue = "\(get())"
                f.geaendert = { [weak f] in
                    if let n = Int(f?.stringValue ?? ""), bereich.contains(n) { set(n) }
                }
                f.frame = NSRect(x: 128, y: y, width: 60, height: 23)
                seite.addSubview(l)
                seite.addSubview(f)
                y += 30
            case let .knopf(t, aktion):
                let k = KnopfHilfe.knopf(t, aktion)
                k.frame = NSRect(x: 14, y: y, width: 260, height: 25)
                seite.addSubview(k)
                y += 32
            case .hinweis(let t):
                let l = WinText(t, rechts: false)
                l.textColor = Win.textAus
                l.frame = NSRect(x: 14, y: y, width: seite.bounds.width - 28, height: 18)
                seite.addSubview(l)
                y += 24
            }
        }
        schliesseGruppe()
        seite.needsDisplay = true
    }

    /// Ein Knopf mit Rückruf.
    enum KnopfHilfe {
        private static var halter: [AnyObject] = []
        static func knopf(_ titel: String, _ aktion: @escaping () -> Void) -> WinKnopf {
            let k = WinKnopf()
            k.title = titel
            k.isBordered = false
            let r = Rueckruf { _ in aktion() }
            halter.append(r)
            k.target = r
            k.action = #selector(Rueckruf.los(_:))
            return k
        }
    }

    final class Rueckruf: NSObject {
        let tun: (Int) -> Void
        init(_ tun: @escaping (Int) -> Void) { self.tun = tun }
        @objc func los(_ sender: NSButton) { tun(sender.state == .on ? 0 : 1) }
    }
}

/// Ein Kästchen oder Optionsfeld mit Rückruf (Wert 0 = an).
private func schalter(titel: String, rund: Bool, _ tun: @escaping (Int) -> Void) -> WinKaestchen {
    let r = EinstellungsFenster.Rueckruf { wert in tun(wert) }
    let k = WinKaestchen(titel: titel, rund: rund, target: r, action: #selector(EinstellungsFenster.Rueckruf.los(_:)))
    objc_setAssociatedObject(k, &rueckrufSchluessel, r, .OBJC_ASSOCIATION_RETAIN)
    return k
}

private var rueckrufSchluessel: UInt8 = 0

/// Eine Liste wie die ListBox von Windows: weiss, Auswahl blau hinterlegt.
final class WinListe: NSView {
    var eintraege: [String] = [] { didSet { needsDisplay = true } }
    var gewaehlt = 0 { didSet { needsDisplay = true } }
    var gewechselt: ((Int) -> Void)?
    override var isFlipped: Bool { true }
    private let zeile: CGFloat = 20

    override func draw(_ dirtyRect: NSRect) {
        let d = Win.dunkel
        Win.rechteck(bounds, fuell: Win.feld, rand: NSColor(rgb: d ? 0x646464 : 0x828790))
        for (i, t) in eintraege.enumerated() {
            let r = NSRect(x: 1, y: 2 + CGFloat(i) * zeile, width: bounds.width - 2, height: zeile)
            if i == gewaehlt {
                NSColor(rgb: d ? 0x0078D7 : 0x0078D7).setFill()
                r.fill()
            }
            let a: [NSAttributedString.Key: Any] = [.font: Win.schrift, .foregroundColor: i == gewaehlt ? NSColor.white : Win.text]
            (t as NSString).draw(at: NSPoint(x: r.minX + 5, y: r.minY + 2), withAttributes: a)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let i = Int((p.y - 2) / zeile)
        guard eintraege.indices.contains(i), i != gewaehlt else { return }
        gewaehlt = i
        gewechselt?(i)
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 125 where gewaehlt < eintraege.count - 1: gewaehlt += 1; gewechselt?(gewaehlt)
        case 126 where gewaehlt > 0: gewaehlt -= 1; gewechselt?(gewaehlt)
        default: super.keyDown(with: event)
        }
    }
}
