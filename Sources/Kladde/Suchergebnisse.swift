import AppKit
import ScintillaBruecke

/// Das Suchergebnis unten im Fenster wie in Notepad++: eine Scintilla-Ansicht,
/// eingefärbt mit den Stilen «searchResult» des Farbschemas:
///
///     Suche "bern" (5 Treffer in 1 Dateien von 1 gesucht) [Normal]
///       /pfad/staedte.txt (5 Treffer)
///     	Zeile 2: Bern ist die Bundesstadt.
///
/// Neue Suchen oben, ältere zugeklappt. Doppelklick, ↩ oder F4 springen hin.
final class Suchergebnisse: NSObject, ScintillaNotificationProtocol {
    static let gemeinsam = Suchergebnisse()

    final class Suche {
        let optionen: SuchOptionen
        let ort: String?
        var dateien: [Datei] = []
        var geprueft = 0
        var laeuft = false
        var trefferzahl: Int { dateien.reduce(0) { $0 + $1.trefferzahl } }
        init(optionen: SuchOptionen, ort: String?) {
            self.optionen = optionen
            self.ort = ort
        }
    }

    final class Datei {
        let name: String
        let url: URL?
        weak var dokument: Dokument?
        let zeilen: [Fundzeile]
        var trefferzahl: Int { zeilen.reduce(0) { $0 + $1.bereiche.count } }
        init(name: String, url: URL?, dokument: Dokument?, funde: [Fundzeile]) {
            self.name = name
            self.url = url
            self.dokument = dokument
            zeilen = funde
        }
    }

    private(set) var suchen: [Suche] = []
    private static let hoechstensSuchen = 10
    let ansicht = KladdeScintillaView(frame: NSRect(x: 0, y: 0, width: 600, height: 200))
    private(set) lazy var leiste: Seitenleiste = {
        let l = Seitenleiste(titel: Oberflaeche.gemeinsam.texte["find-result-caption"] ?? "Suchergebnisse", inhalt: ansicht)
        l.schliessen = { [weak self] in self?.verberge() }
        return l
    }()
    /// Zeile im Ergebnis → wohin sie springt.
    private var ziele: [Int: (Datei, Int)] = [:]
    private var aktuelleZeile = -1
    var hatTreffer: Bool { !ziele.isEmpty }

    private override init() {
        super.init()
        ansicht.delegate = self
        sci(SCI_SETCODEPAGE, Int(SC_CP_UTF8))
        sci(SCI_SETMARGINWIDTHN, 0, 0)
        sci(SCI_SETMARGINWIDTHN, 1, 0)
        sci(SCI_SETMARGINTYPEN, 2, Int(SC_MARGIN_SYMBOL))
        sci(SCI_SETMARGINMASKN, 2, Int(bitPattern: UInt(SC_MASK_FOLDERS)))
        sci(SCI_SETMARGINWIDTHN, 2, 14)
        sci(SCI_SETMARGINSENSITIVEN, 2, 1)
        let marken: [(Int32, Int32)] = [
            (SC_MARKNUM_FOLDEROPEN, SC_MARK_BOXMINUS), (SC_MARKNUM_FOLDER, SC_MARK_BOXPLUS),
            (SC_MARKNUM_FOLDERSUB, SC_MARK_VLINE), (SC_MARKNUM_FOLDERTAIL, SC_MARK_LCORNER),
            (SC_MARKNUM_FOLDEREND, SC_MARK_BOXPLUSCONNECTED), (SC_MARKNUM_FOLDEROPENMID, SC_MARK_BOXMINUSCONNECTED),
            (SC_MARKNUM_FOLDERMIDTAIL, SC_MARK_TCORNER),
        ]
        for (m, f) in marken { sci(SCI_MARKERDEFINE, Int(m), Int(f)) }
        sci(SCI_SETAUTOMATICFOLD, Int(SC_AUTOMATICFOLD_CLICK))
        sci(SCI_SETCARETLINEVISIBLE, 1)
        // Wie in Notepad++: Die Zeile der Marke leuchtet nur, solange das Panel den Fokus hat.
        sci(SCI_SETCARETLINEVISIBLEALWAYS, 0)
        ansicht.kontextmenue = { [weak self] in self?.kontextmenue() }
        darstellungGeaendert()
    }

    @discardableResult
    private func sci(_ n: Int32, _ w: Int = 0, _ l: Int = 0) -> Int {
        ansicht.message(UInt32(n), wParam: UInt(bitPattern: w), lParam: l)
    }

    // MARK: Füllen

    @discardableResult
    func beginne(_ optionen: SuchOptionen, ort: String?) -> Suche {
        let suche = Suche(optionen: optionen, ort: ort)
        suchen.insert(suche, at: 0)
        if suchen.count > Self.hoechstensSuchen { suchen.removeLast() }
        zeige()
        zeichne()
        return suche
    }

    func fuegeHinzu(_ datei: Datei, zu suche: Suche) {
        suche.dateien.append(datei)
        zeichne()
    }

    func beende(_ suche: Suche) {
        suche.laeuft = false
        zeichne()
    }

    /// «Alle in aktiver Datei suchen» und «In offenen Dateien suchen».
    func findeAlle(in dokumente: [Dokument]) -> Suchaktion.Antwort {
        let muster: Suchmuster
        do { muster = try SuchZustand.gemeinsam.muster() } catch {
            return Suchaktion.Antwort(text: (error as? Suchfehler)?.meldung ?? "", fehler: true)
        }
        let suche = beginne(muster.optionen, ort: nil)
        suche.geprueft = dokumente.count
        for dokument in dokumente {
            guard let editor = dokument.editor else { continue }
            let text = editor.suchtext
            let treffer = muster.alle(in: text)
            guard !treffer.isEmpty else { continue }
            suche.dateien.append(Datei(
                name: dokument.fileURL?.path ?? dokument.tabTitel, url: dokument.fileURL, dokument: dokument,
                funde: Fundzeilen.aus(treffer, in: text)))
        }
        beende(suche)
        let anzahl = suche.trefferzahl
        return Suchaktion.Antwort(text: anzahl == 0 ? "Nicht gefunden" : "\(anzahl) Treffer gefunden", fehler: anzahl == 0)
    }

    // MARK: Zeichnen

    private enum Stil: Int { case standard = 0, kopf = 1, datei = 2, zeilennummer = 3, treffer = 4 }

    private func kopfzeile(_ s: Suche) -> String {
        let o = Oberflaeche.gemeinsam
        let titel = o.texte["find-result-title"] ?? "Suche"
        let info = o.text("find-result-title-info", "\(s.trefferzahl)", "\(s.dateien.count)", "\(max(s.geprueft, s.dateien.count))")
        let modus: String
        switch s.optionen.modus {
        case .normal: modus = o.texte["find-result-title-info-options-searchmode-normal"] ?? "Normal"
        case .erweitert: modus = o.texte["find-result-title-info-options-searchmode-extended"] ?? "Erweitert"
        case .regulaer: modus = o.texte["find-result-title-info-options-searchmode-regexp"] ?? "RegEx"
        }
        var zusatz: [String] = []
        if s.optionen.grossKlein { zusatz.append(o.texte["find-result-title-info-options-case"] ?? "Groß-/Kleinschreibung") }
        if s.optionen.ganzesWort { zusatz.append(o.texte["find-result-title-info-options-word"] ?? "Wort") }
        let klammer = modus + (zusatz.isEmpty ? "" : ": " + zusatz.joined(separator: "/"))
        return "\(titel) \"\(s.optionen.text)\" \(s.laeuft ? "…" : info) [\(klammer)]"
    }

    /// Baut den ganzen Text neu, färbt ihn selbst ein (kein Lexer) und setzt die Faltstufen.
    private func zeichne() {
        let o = Oberflaeche.gemeinsam
        let praefix = o.texte["find-result-line-prefix"] ?? "Zeile"
        var text = Data()
        var stile: [(Int, Int, Stil)] = []
        var stufen: [Int] = []
        ziele = [:]
        func zeile(_ inhalt: String, stufe: Int, kopf: Bool, stil: Stil) -> Int {
            let start = text.count
            text.append(contentsOf: Array(inhalt.utf8))
            text.append(0x0A)
            stile.append((start, inhalt.utf8.count, stil))
            stufen.append((Int(SC_FOLDLEVELBASE) + stufe) | (kopf ? Int(SC_FOLDLEVELHEADERFLAG) : 0))
            return start
        }
        for s in suchen {
            _ = zeile(kopfzeile(s), stufe: 0, kopf: true, stil: .kopf)
            for d in s.dateien {
                _ = zeile("  \(d.name) " + o.text("find-result-hits", "\(d.trefferzahl)"), stufe: 1, kopf: true, stil: .datei)
                for (i, f) in d.zeilen.enumerated() {
                    let vorne = "\t\(praefix) \(f.nummer): "
                    let start = zeile(vorne + f.text, stufe: 2, kopf: false, stil: .standard)
                    stile.append((start + 1, vorne.utf8.count - 1, .zeilennummer))
                    for h in f.hervorhebungen {
                        let davor = (f.text as NSString).substring(to: h.location).utf8.count
                        let laenge = (f.text as NSString).substring(with: h).utf8.count
                        stile.append((start + vorne.utf8.count + davor, laenge, .treffer))
                    }
                    ziele[stufen.count - 1] = (d, i)
                }
            }
        }
        sci(SCI_SETREADONLY, 0)
        sci(SCI_CLEARALL)
        text.withUnsafeBytes { b in if let p = b.baseAddress { _ = sci(SCI_ADDTEXT, b.count, Int(bitPattern: p)) } }
        for (start, laenge, stil) in stile where laenge > 0 {
            sci(SCI_STARTSTYLING, start)
            sci(SCI_SETSTYLING, laenge, stil.rawValue)
        }
        for (z, stufe) in stufen.enumerated() { sci(SCI_SETFOLDLEVEL, z, stufe) }
        // Ältere Suchen zugeklappt, wie in Notepad++.
        var zeileNr = 0
        for (i, s) in suchen.enumerated() {
            if i > 0 { sci(SCI_FOLDLINE, zeileNr, Int(SC_FOLDACTION_CONTRACT)) }
            zeileNr += 1 + s.dateien.reduce(0) { $0 + 1 + $1.zeilen.count }
        }
        sci(SCI_SETREADONLY, 1)
        sci(SCI_GOTOPOS, 0)
        aktuelleZeile = -1
    }

    func darstellungGeaendert() {
        let schema = Sprachdaten.gemeinsam.farbschema(Einstellungen.schemaName(fuer: NSApp.effectiveAppearance))
        let standard = schema.global["Default Style"]
        let schrift = standard?.schriftart.flatMap { NSFont(name: $0, size: 12) != nil ? $0 : nil } ?? "Menlo"
        schrift.withCString { _ = sci(SCI_STYLESETFONT, Int(STYLE_DEFAULT), Int(bitPattern: $0)) }
        sci(SCI_STYLESETSIZE, Int(STYLE_DEFAULT), Int((Double(standard?.groesse ?? 10) * 4 / 3).rounded()))
        sci(SCI_STYLESETFORE, Int(STYLE_DEFAULT), scintillaFarbe(standard?.vorne ?? 0))
        sci(SCI_STYLESETBACK, Int(STYLE_DEFAULT), scintillaFarbe(standard?.hinten ?? 0xFFFFFF))
        sci(SCI_STYLECLEARALL)
        for stil in schema.lexer["searchResult"] ?? [] {
            if let v = stil.vorne { sci(SCI_STYLESETFORE, stil.id, scintillaFarbe(v)) }
            if let h = stil.hinten { sci(SCI_STYLESETBACK, stil.id, scintillaFarbe(h)) }
            if let s = stil.schrift { sci(SCI_STYLESETBOLD, stil.id, s & 1) }
            if stil.id == 1 || stil.id == 2 { sci(SCI_STYLESETEOLFILLED, stil.id, 1) }
            if stil.id == 6, let h = stil.hinten { sci(SCI_SETCARETLINEBACK, scintillaFarbe(h)) }
        }
        ansicht.appearance = NSAppearance(named: Hauptfenster.istDunkel ? .darkAqua : .aqua)
        leiste.faerbe()
        zeichne()
    }

    // MARK: Zeigen und springen

    func zeige() { Hauptfenster.gemeinsam.untererDock.zeige(leiste, an: true) }
    func verberge() { Hauptfenster.gemeinsam.untererDock.zeige(leiste, an: false) }

    func fokussiere() {
        zeige()
        ansicht.window?.makeFirstResponder(ansicht.content())
    }

    /// F4 / Umschalt+F4: nächster oder vorheriger Treffer.
    func springe(weiter: Bool) {
        let zeilen = ziele.keys.sorted()
        guard !zeilen.isEmpty else { return }
        let ziel = weiter
            ? (zeilen.first { $0 > aktuelleZeile } ?? zeilen[0])
            : (zeilen.last { $0 < aktuelleZeile } ?? zeilen[zeilen.count - 1])
        oeffne(zeile: ziel)
    }

    private func oeffne(zeile: Int) {
        guard let (datei, i) = ziele[zeile] else {
            sci(SCI_TOGGLEFOLD, zeile)
            return
        }
        aktuelleZeile = zeile
        sci(SCI_ENSUREVISIBLE, zeile)
        sci(SCI_GOTOLINE, zeile)
        let bereich = datei.zeilen[i].bereiche[0]
        func zeigeIn(_ d: Dokument) {
            Hauptfenster.gemeinsam.aktiviere(d)
            d.editor?.waehleAus(bereich)
            d.editor?.nachricht(SCI_VERTICALCENTRECARET)
        }
        if let d = datei.dokument ?? datei.url.flatMap({ NSDocumentController.shared.document(for: $0) as? Dokument }) {
            return zeigeIn(d)
        }
        guard let url = datei.url else { return NSSound.beep() }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { d, _, fehler in
            if let d = d as? Dokument { zeigeIn(d) } else if let fehler { NSApp.presentError(fehler) }
        }
    }

    func notification(_ meldung: UnsafeMutablePointer<SCNotification>!) {
        if Int32(meldung.pointee.nmhdr.code) == SCN_DOUBLECLICK {
            oeffne(zeile: sci(SCI_LINEFROMPOSITION, meldung.pointee.position))
        }
    }

    // MARK: Kontextmenü

    private func kontextmenue() -> NSMenu {
        let m = NSMenu()
        let liste: [(String, Selector?)] = [
            ("Alle einklappen", #selector(alleEin)), ("Alle ausklappen", #selector(alleAus)), ("", nil),
            ("Kopieren", #selector(kopieren)), ("Alles auswählen", #selector(allesWaehlen)), ("", nil),
            ("Alles löschen", #selector(leeren)),
        ]
        for (titel, aktion) in liste {
            guard let aktion else { m.addItem(.separator()); continue }
            let e = NSMenuItem(title: titel, action: aktion, keyEquivalent: "")
            e.target = self
            m.addItem(e)
        }
        return m
    }

    @objc private func alleEin() { sci(SCI_FOLDALL, Int(SC_FOLDACTION_CONTRACT)) }
    @objc private func alleAus() { sci(SCI_FOLDALL, Int(SC_FOLDACTION_EXPAND)) }
    @objc private func kopieren() { sci(SCI_COPY) }
    @objc private func allesWaehlen() { sci(SCI_SELECTALL) }
    @objc private func leeren() {
        suchen = []
        zeichne()
    }

    /// Für die Selbstprüfung: der Text des Ergebnisses.
    var text: String {
        let laenge = sci(SCI_GETLENGTH)
        guard laenge > 0, let p = UnsafeRawPointer(bitPattern: sci(SCI_GETCHARACTERPOINTER)) else { return "" }
        return String(decoding: UnsafeRawBufferPointer(start: p, count: laenge), as: UTF8.self)
    }
}
