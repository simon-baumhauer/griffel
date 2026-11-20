import AppKit
import ScintillaBruecke

/// Eine ScintillaView samt ihrer Einrichtung. Alles, was die App vom
/// Editor-Kern will, geht hier durch.
final class Editor: NSObject, ScintillaNotificationProtocol {
    let ansicht = ScintillaView(frame: NSRect(x: 0, y: 0, width: 900, height: 650))

    /// Der Text weicht vom gesicherten Stand ab (true) oder stimmt wieder (false).
    var geaendert: ((Bool) -> Void)?

    private(set) var sprache = Sprachdaten.gemeinsam.normal
    private var zeilennummernStellen = 0
    private var klammerMarkiert = false
    private var beobachter: NSObjectProtocol?

    /// Rand 0 Zeilennummern, Rand 1 Lesezeichen (später), Rand 2 Faltung.
    private static let randFaltung: UInt = 2

    override init() {
        super.init()
        ansicht.delegate = self
        richteEin()
        setzeSprache(sprache)
        beobachter = NotificationCenter.default.addObserver(
            forName: Einstellungen.geaendert, object: nil, queue: .main
        ) { [weak self] _ in self?.wendeDarstellungAn() }
    }

    deinit {
        if let beobachter { NotificationCenter.default.removeObserver(beobachter) }
    }

    // MARK: Nachrichten

    @discardableResult
    private func sci(_ nachricht: Int32, _ w: Int = 0, _ l: Int = 0) -> Int {
        ansicht.message(UInt32(nachricht), wParam: UInt(bitPattern: w), lParam: l)
    }

    @discardableResult
    private func sci(_ nachricht: Int32, _ w: Int, _ text: String) -> Int {
        text.withCString { sci(nachricht, w, Int(bitPattern: $0)) }
    }

    private func eigenschaft(_ name: String, _ wert: String) {
        name.withCString { n in
            wert.withCString { w in
                _ = sci(SCI_SETPROPERTY, Int(bitPattern: n), Int(bitPattern: w))
            }
        }
    }

    // MARK: Einrichtung

    private func richteEin() {
        sci(SCI_SETCODEPAGE, Int(SC_CP_UTF8))
        sci(SCI_SETTABWIDTH, 4)
        sci(SCI_SETSCROLLWIDTH, 1)
        sci(SCI_SETSCROLLWIDTHTRACKING, 1)

        // Mehrere Einfügemarken und Spaltenauswahl (Wahltaste + Ziehen) wie in Notepad++.
        sci(SCI_SETMULTIPLESELECTION, 1)
        sci(SCI_SETADDITIONALSELECTIONTYPING, 1)
        sci(SCI_SETMULTIPASTE, Int(SC_MULTIPASTE_EACH))
        sci(SCI_SETVIRTUALSPACEOPTIONS, Int(SCVS_RECTANGULARSELECTION))

        sci(SCI_SETMARGINTYPEN, 0, Int(SC_MARGIN_NUMBER))
        sci(SCI_SETMARGINWIDTHN, 1, 0)
        sci(SCI_SETCARETLINEVISIBLE, 1)
        sci(SCI_SETCARETLINEVISIBLEALWAYS, 1)

        // Faltung wie in Notepad++ («Box tree»): Kästchen mit Plus und Minus, verbunden durch Linien.
        let rand = Int(Self.randFaltung)
        sci(SCI_SETMARGINTYPEN, rand, Int(SC_MARGIN_SYMBOL))
        sci(SCI_SETMARGINMASKN, rand, Int(bitPattern: UInt(SC_MASK_FOLDERS)))
        sci(SCI_SETMARGINSENSITIVEN, rand, 1)
        let marken: [(Int32, Int32)] = [
            (SC_MARKNUM_FOLDEROPEN, SC_MARK_BOXMINUS), (SC_MARKNUM_FOLDER, SC_MARK_BOXPLUS),
            (SC_MARKNUM_FOLDERSUB, SC_MARK_VLINE), (SC_MARKNUM_FOLDERTAIL, SC_MARK_LCORNER),
            (SC_MARKNUM_FOLDEREND, SC_MARK_BOXPLUSCONNECTED),
            (SC_MARKNUM_FOLDEROPENMID, SC_MARK_BOXMINUSCONNECTED),
            (SC_MARKNUM_FOLDERMIDTAIL, SC_MARK_TCORNER),
        ]
        for (marke, form) in marken { sci(SCI_MARKERDEFINE, Int(marke), Int(form)) }
        sci(SCI_MARKERENABLEHIGHLIGHT, 1)
        sci(SCI_SETFOLDFLAGS, Int(SC_FOLDFLAG_LINEAFTER_CONTRACTED))
        // Klick auf ein Kästchen klappt; Änderungen am Text halten gefaltete Blöcke sichtbar.
        sci(SCI_SETAUTOMATICFOLD, Int(SC_AUTOMATICFOLD_SHOW | SC_AUTOMATICFOLD_CLICK | SC_AUTOMATICFOLD_CHANGE))
    }

    // MARK: Sprache

    /// Neuer Lexer, seine Wörter und Eigenschaften, dann Farben und Faltung.
    func setzeSprache(_ neu: Sprache) {
        sprache = neu
        let regel = Sprachregel.fuer(neu)
        // Scintilla übernimmt den Lexer und gibt den alten frei. Unbekannt oder
        // «null»: ohne Lexer, also ohne Farben und Faltung.
        let lexer = neu.istNormalerText ? nil : CreateLexer(regel.lexer)
        ansicht.setReferenceProperty(SCI_SETILEXER, parameter: 0, value: lexer)
        for (name, wert) in regel.eigenschaften { eigenschaft(name, wert) }
        let rand = Int(Self.randFaltung)
        sci(SCI_SETMARGINWIDTHN, rand, lexer == nil ? 0 : 16)
        wendeDarstellungAn()
    }

    // MARK: Darstellung

    /// Farbschema, Schlüsselwörter und sichtbare Symbole, für die jetzige
    /// Sprache. Läuft auch bei jedem Wechsel des Schemas oder von hell/dunkel.
    func wendeDarstellungAn() {
        // Nach macOS, nicht nach der Ansicht: Die trägt unten das Aussehen des Schemas.
        let name = Einstellungen.schemaName(fuer: NSApp.effectiveAppearance)
        let schema = Sprachdaten.gemeinsam.farbschema(name)
        let regel = Sprachregel.fuer(sprache)
        let global = schema.global

        // Ein dunkles Schema zeichnet Rollbalken und Ecken dunkel, auch bei hellem macOS.
        let grund = global["Default Style"]?.hinten ?? 0xFFFFFF
        let helligkeit = 0.299 * Double(grund >> 16 & 0xFF) + 0.587 * Double(grund >> 8 & 0xFF)
            + 0.114 * Double(grund & 0xFF)
        ansicht.appearance = NSAppearance(named: helligkeit < 128 ? .darkAqua : .aqua)

        // Erst der Standardstil, dann erben alle anderen von ihm. Die Schrift
        // aus dem Schema (meist Courier New 10) gilt nicht; auf dem Mac Menlo 13.
        sci(SCI_STYLESETFONT, Int(STYLE_DEFAULT), "Menlo")
        sci(SCI_STYLESETSIZE, Int(STYLE_DEFAULT), 13)
        sci(SCI_STYLESETFORE, Int(STYLE_DEFAULT), scintillaFarbe(global["Default Style"]?.vorne ?? 0x000000))
        sci(SCI_STYLESETBACK, Int(STYLE_DEFAULT), scintillaFarbe(global["Default Style"]?.hinten ?? 0xFFFFFF))
        if let standard = global["Default Style"] { setzeSchrift(Int(STYLE_DEFAULT), standard.schrift) }
        sci(SCI_STYLECLEARALL)

        // Zeilennummern, Klammern, Steuerzeichen, Einrückungshilfen.
        for stil in global.values where (33...37).contains(stil.id) { setze(stil) }
        for abschnitt in regel.farben {
            for stil in schema.lexer[abschnitt] ?? [] { setze(stil) }
        }

        func farbe(_ name: String, _ teil: KeyPath<Stil, Int?>) -> Int? {
            global[name]?[keyPath: teil].map(scintillaFarbe)
        }
        if let f = farbe("Current line background colour", \.hinten) { sci(SCI_SETCARETLINEBACK, f) }
        if let f = farbe("Selected text colour", \.hinten) { sci(SCI_SETSELBACK, 1, f) }
        if let f = farbe("Multi-selected text color", \.hinten) { sci(SCI_SETADDITIONALSELBACK, f) }
        if let f = farbe("Caret colour", \.vorne) { sci(SCI_SETCARETFORE, f) }
        if let f = farbe("Multi-edit carets color", \.vorne) { sci(SCI_SETADDITIONALCARETFORE, f) }
        if let f = farbe("White space symbol", \.vorne) { sci(SCI_SETWHITESPACEFORE, 1, f) }

        // Faltung: Rand, Linien und Kästchen. Notepad++ vertauscht Vorder- und
        // Hintergrund von «Fold» (getFoldColor), darum hier ebenso.
        if let f = farbe("Fold margin", \.hinten) { sci(SCI_SETFOLDMARGINCOLOUR, 1, f) }
        if let f = farbe("Fold margin", \.vorne) { sci(SCI_SETFOLDMARGINHICOLOUR, 1, f) }
        let fuellung = farbe("Fold", \.hinten) ?? scintillaFarbe(0xFFFFFF)
        let linie = farbe("Fold", \.vorne) ?? scintillaFarbe(0x808080)
        let aktiv = farbe("Fold active", \.vorne) ?? scintillaFarbe(0xFF0000)
        for marke in SC_MARKNUM_FOLDEREND...SC_MARKNUM_FOLDEROPEN {
            sci(SCI_MARKERSETFORE, Int(marke), fuellung)
            sci(SCI_MARKERSETBACK, Int(marke), linie)
            sci(SCI_MARKERSETBACKSELECTED, Int(marke), aktiv)
        }

        // Markierungen: abgerundete Kästchen unter dem Text, wie setSpecialIndicator in Notepad++.
        let indikatoren: [(Int32, String, Int)] = [
            (Self.indikatorMarkiert, "Find Mark Style", 0xFF0000),
            (Self.indikatorSmart, "Smart Highlighting", 0x00FF00),
            (Self.indikatorSuche, "Find matches highlight all", 0x0080FF),
        ]
        for (indikator, name, vorgabe) in indikatoren {
            sci(SCI_INDICSETSTYLE, Int(indikator), Int(INDIC_ROUNDBOX))
            sci(SCI_INDICSETALPHA, Int(indikator), 100)
            sci(SCI_INDICSETUNDER, Int(indikator), 1)
            sci(SCI_INDICSETFORE, Int(indikator), scintillaFarbe(global[name]?.hinten ?? vorgabe))
        }

        for (liste, quelle, klasse) in regel.listen {
            sci(SCI_SETKEYWORDS, liste, Sprachregel.woerter(sprache: quelle, klasse: klasse, schema: schema))
        }

        sci(SCI_SETVIEWWS, Int(Einstellungen.leerzeichenZeigen ? SCWS_VISIBLEALWAYS : SCWS_INVISIBLE))
        sci(SCI_SETVIEWEOL, Einstellungen.zeilenendenZeigen ? 1 : 0)
        sci(SCI_SETINDENTATIONGUIDES, Int(Einstellungen.einrueckungshilfen ? SC_IV_LOOKBOTH : SC_IV_NONE))

        zeilennummernStellen = 0
        passeZeilennummernAn()
        sci(SCI_COLOURISE, 0, -1)
    }

    private func setze(_ stil: Stil) {
        if let vorne = stil.vorne { sci(SCI_STYLESETFORE, stil.id, scintillaFarbe(vorne)) }
        if let hinten = stil.hinten { sci(SCI_STYLESETBACK, stil.id, scintillaFarbe(hinten)) }
        setzeSchrift(stil.id, stil.schrift)
    }

    private func setzeSchrift(_ id: Int, _ schrift: Int?) {
        guard let schrift, schrift >= 0 else { return }
        sci(SCI_STYLESETBOLD, id, schrift & 1 != 0 ? 1 : 0)
        sci(SCI_STYLESETITALIC, id, schrift & 2 != 0 ? 1 : 0)
        sci(SCI_STYLESETUNDERLINE, id, schrift & 4 != 0 ? 1 : 0)
    }

    /// Der Rand ist so breit wie die höchste Zeilennummer, mindestens drei Stellen.
    private func passeZeilennummernAn() {
        let stellen = max(3, String(sci(SCI_GETLINECOUNT)).count)
        guard stellen != zeilennummernStellen else { return }
        zeilennummernStellen = stellen
        let breite = sci(SCI_TEXTWIDTH, Int(STYLE_LINENUMBER), "_" + String(repeating: "9", count: stellen))
        sci(SCI_SETMARGINWIDTHN, 0, breite + 6)
    }

    // MARK: Klammerpaare

    private static let klammern = Set("()[]{}".utf8.map(Int.init))

    /// Steht die Einfügemarke an einer Klammer, leuchten sie und ihr Gegenstück;
    /// fehlt das Gegenstück, leuchtet sie als falsch.
    private func markiereKlammern() {
        let marke = sci(SCI_GETCURRENTPOS)
        let zeichen = { (stelle: Int) in self.sci(SCI_GETCHARAT, stelle) & 0xFF }
        var stelle = -1
        if marke > 0, Self.klammern.contains(zeichen(marke - 1)) {
            stelle = marke - 1
        } else if Self.klammern.contains(zeichen(marke)) {
            stelle = marke
        }
        guard stelle >= 0 else {
            if klammerMarkiert {
                sci(SCI_BRACEHIGHLIGHT, -1, -1)
                sci(SCI_SETHIGHLIGHTGUIDE, 0)
                klammerMarkiert = false
            }
            return
        }
        let gegenstueck = sci(SCI_BRACEMATCH, stelle, 0)
        if gegenstueck < 0 {
            sci(SCI_BRACEBADLIGHT, stelle)
            sci(SCI_SETHIGHLIGHTGUIDE, 0)
        } else {
            sci(SCI_BRACEHIGHLIGHT, stelle, gegenstueck)
            let spalte = min(sci(SCI_GETCOLUMN, stelle), sci(SCI_GETCOLUMN, gegenstueck))
            sci(SCI_SETHIGHLIGHTGUIDE, spalte)
        }
        klammerMarkiert = true
    }

    // MARK: Text

    func lade(_ datei: Textdatei) {
        sci(SCI_SETUNDOCOLLECTION, 0)
        sci(SCI_CLEARALL)
        datei.utf8.withUnsafeBytes { bytes in
            if let anfang = bytes.baseAddress {
                _ = sci(SCI_ADDTEXT, bytes.count, Int(bitPattern: anfang))
            }
        }
        sci(SCI_SETEOLMODE, datei.zeilenende.rawValue)
        sci(SCI_SETUNDOCOLLECTION, 1)
        sci(SCI_EMPTYUNDOBUFFER)
        sci(SCI_SETSAVEPOINT)
        sci(SCI_GOTOPOS, 0)
    }

    /// Der Text, wie er im Editor steht: UTF-8, mit den Zeilenenden der Datei.
    var utf8: Data {
        let laenge = sci(SCI_GETLENGTH)
        guard laenge > 0, let anfang = UnsafeRawPointer(bitPattern: sci(SCI_GETCHARACTERPOINTER)) else {
            return Data()
        }
        return Data(bytes: anfang, count: laenge)
    }

    /// Stellt jedes Zeilenende des Textes um (ein Schritt für «Widerrufen») und
    /// lässt neue Zeilen gleich enden.
    func wandleZeilenendenUm(in zeilenende: Textdatei.Zeilenende) {
        sci(SCI_CONVERTEOLS, zeilenende.rawValue)
        sci(SCI_SETEOLMODE, zeilenende.rawValue)
    }

    /// Wo die Einfügemarke steht (Byte im UTF-8-Text) und welche Zeile oben ist.
    var position: Int {
        get { sci(SCI_GETCURRENTPOS) }
        set { sci(SCI_GOTOPOS, min(max(0, newValue), sci(SCI_GETLENGTH))) }
    }

    var ersteZeile: Int {
        get { sci(SCI_GETFIRSTVISIBLELINE) }
        set { sci(SCI_SETFIRSTVISIBLELINE, max(0, newValue)) }
    }

    /// Der jetzige Stand gilt als gesichert.
    func merkeGesichert() {
        sci(SCI_SETSAVEPOINT)
    }

    // MARK: Suchen

    /// Indikatoren wie in Notepad++ (SCE_UNIVERSAL_*): 31 «Alle markieren»,
    /// 29 Smart Highlighting, 28 alle Treffer der Suchleiste.
    static let indikatorMarkiert: Int32 = 31
    static let indikatorSmart: Int32 = 29
    static let indikatorSuche: Int32 = 28

    var suchtext: Suchtext { Suchtext(utf8: utf8) }

    /// Die Hauptauswahl in Bytes.
    var auswahl: Range<Int> {
        let a = sci(SCI_GETSELECTIONSTART)
        return a..<max(a, sci(SCI_GETSELECTIONEND))
    }

    /// Wählt aus, klappt auf, was den Bereich verdeckt, und rollt ihn ins Bild.
    func waehleAus(_ bereich: Range<Int>) {
        let zeile = sci(SCI_LINEFROMPOSITION, bereich.lowerBound)
        sci(SCI_ENSUREVISIBLEENFORCEPOLICY, zeile)
        sci(SCI_SETSEL, bereich.lowerBound, bereich.upperBound)
        sci(SCI_SCROLLRANGE, bereich.upperBound, bereich.lowerBound)
    }

    /// Ersetzt Bereiche (Bytes, aufsteigend, ohne Überlappung) in einem
    /// einzigen Schritt für «Widerrufen».
    func ersetze(_ aenderungen: [(bereich: Range<Int>, text: String)]) {
        guard !aenderungen.isEmpty else { return }
        sci(SCI_BEGINUNDOACTION)
        for (bereich, text) in aenderungen.reversed() {
            sci(SCI_SETTARGETRANGE, bereich.lowerBound, bereich.upperBound)
            let bytes = Array(text.utf8)
            bytes.withUnsafeBufferPointer { zeiger in
                _ = sci(SCI_REPLACETARGET, bytes.count, Int(bitPattern: zeiger.baseAddress))
            }
        }
        sci(SCI_ENDUNDOACTION)
    }

    func markiere(_ bereiche: [Range<Int>], indikator: Int32) {
        sci(SCI_SETINDICATORCURRENT, Int(indikator))
        for bereich in bereiche where !bereich.isEmpty {
            sci(SCI_INDICATORFILLRANGE, bereich.lowerBound, bereich.count)
        }
    }

    func loescheMarkierungen(_ indikator: Int32) {
        sci(SCI_SETINDICATORCURRENT, Int(indikator))
        sci(SCI_INDICATORCLEARRANGE, 0, sci(SCI_GETLENGTH))
    }

    func markierungenLoeschenFuerProbe() {
        for indikator in [Self.indikatorMarkiert, Self.indikatorSuche, Self.indikatorSmart] { loescheMarkierungen(indikator) }
    }

    /// Wie viele Stellen ein Indikator gerade trägt.
    func anzahlMarkierungen(_ indikator: Int32) -> Int {
        var anzahl = 0
        var stelle = 0
        let laenge = sci(SCI_GETLENGTH)
        while stelle < laenge {
            let ende = sci(SCI_INDICATOREND, Int(indikator), stelle)
            if sci(SCI_INDICATORVALUEAT, Int(indikator), stelle) != 0 { anzahl += 1 }
            guard ende > stelle else { break }
            stelle = ende
        }
        return anzahl
    }

    /// Smart Highlighting wie in Notepad++: Ist ein ganzes Wort ausgewählt,
    /// leuchten seine übrigen Vorkommen im sichtbaren Teil (ganzes Wort, ohne
    /// Gross-/Kleinschreibung).
    private func hebeAuswahlHervor() {
        loescheMarkierungen(Self.indikatorSmart)
        guard sci(SCI_GETSELECTIONS) == 1 else { return }
        let bereich = auswahl
        guard !bereich.isEmpty, bereich.count < 200,
            sci(SCI_LINEFROMPOSITION, bereich.lowerBound) == sci(SCI_LINEFROMPOSITION, bereich.upperBound),
            sci(SCI_WORDSTARTPOSITION, bereich.lowerBound, 1) == bereich.lowerBound,
            sci(SCI_WORDENDPOSITION, bereich.lowerBound, 1) == bereich.upperBound,
            let wort = text(bereich)
        else { return }

        // Nur der sichtbare Teil, wie Notepad++: grosse Dateien bleiben schnell.
        let oben = sci(SCI_DOCLINEFROMVISIBLE, sci(SCI_GETFIRSTVISIBLELINE))
        let unten = sci(SCI_DOCLINEFROMVISIBLE, sci(SCI_GETFIRSTVISIBLELINE) + sci(SCI_LINESONSCREEN) + 1)
        let von = sci(SCI_POSITIONFROMLINE, oben)
        let bis = sci(SCI_GETLINEENDPOSITION, unten)
        guard bis > von, let sichtbar = text(von..<bis) else { return }

        var optionen = SuchOptionen()
        optionen.text = wort
        optionen.ganzesWort = true
        guard let muster = try? Suchmuster(optionen) else { return }
        let treffer = muster.alle(in: Suchtext(sichtbar))
            .map { ($0.bereich.lowerBound + von)..<($0.bereich.upperBound + von) }
            .filter { $0 != bereich }
        markiere(treffer, indikator: Self.indikatorSmart)
    }

    /// Ein Stück Text als String, ohne den ganzen Text zu kopieren.
    func text(_ bereich: Range<Int>) -> String? {
        guard let zeiger = UnsafeRawPointer(bitPattern: sci(SCI_GETRANGEPOINTER, bereich.lowerBound, bereich.count))
        else { return nil }
        return String(decoding: UnsafeRawBufferPointer(start: zeiger, count: bereich.count), as: UTF8.self)
    }

    // MARK: Springen

    var zeilenanzahl: Int { sci(SCI_GETLINECOUNT) }
    var aktuelleZeile: Int { sci(SCI_LINEFROMPOSITION, sci(SCI_GETCURRENTPOS)) + 1 }

    /// Zeile ab 1, an ihren Anfang.
    func geheZuZeile(_ zeile: Int) {
        let index = min(max(1, zeile), zeilenanzahl) - 1
        sci(SCI_ENSUREVISIBLEENFORCEPOLICY, index)
        sci(SCI_GOTOLINE, index)
        sci(SCI_VERTICALCENTRECARET)
    }

    /// Zur passenden Klammer, wie Ctrl+B in Notepad++. Mit Auswahl: alles dazwischen auswählen.
    func geheZurPassendenKlammer(auswaehlen: Bool) {
        let marke = sci(SCI_GETCURRENTPOS)
        let zeichen = { (stelle: Int) in self.sci(SCI_GETCHARAT, stelle) & 0xFF }
        var stelle = -1
        if marke > 0, Self.klammern.contains(zeichen(marke - 1)) {
            stelle = marke - 1
        } else if Self.klammern.contains(zeichen(marke)) {
            stelle = marke
        }
        guard stelle >= 0 else { return }
        let gegen = sci(SCI_BRACEMATCH, stelle, 0)
        guard gegen >= 0 else { return }
        if auswaehlen {
            sci(SCI_SETSEL, min(stelle, gegen), max(stelle, gegen) + 1)
        } else {
            sci(SCI_GOTOPOS, gegen)
        }
    }

    // MARK: Darstellung je Fenster

    var umbruch: Bool {
        get { sci(SCI_GETWRAPMODE) != Int(SC_WRAP_NONE) }
        set { sci(SCI_SETWRAPMODE, Int(newValue ? SC_WRAP_WORD : SC_WRAP_NONE)) }
    }

    func vergroessere() { sci(SCI_ZOOMIN) }
    func verkleinere() { sci(SCI_ZOOMOUT) }
    func originalgroesse() { sci(SCI_SETZOOM, 0) }

    /// Alle Blöcke ein- oder ausklappen. Scintilla faltet erst, wenn der Text
    /// eingefärbt ist; darum zuerst bis ans Ende färben.
    func klappeAlles(ein: Bool) {
        sci(SCI_COLOURISE, 0, -1)
        sci(SCI_FOLDALL, Int(ein ? SC_FOLDACTION_CONTRACT : SC_FOLDACTION_EXPAND))
    }

    /// Wie viele Zeilen gerade sichtbar sind (für die Selbstprüfung).
    var sichtbareZeilen: Int {
        (0..<sci(SCI_GETLINECOUNT)).filter { sci(SCI_GETLINEVISIBLE, $0) != 0 }.count
    }

    // MARK: ScintillaNotificationProtocol

    func notification(_ meldung: UnsafeMutablePointer<SCNotification>!) {
        switch Int32(meldung.pointee.nmhdr.code) {
        case SCN_SAVEPOINTLEFT:
            geaendert?(true)
        case SCN_SAVEPOINTREACHED:
            geaendert?(false)
        case SCN_MODIFIED:
            if meldung.pointee.linesAdded != 0 { passeZeilennummernAn() }
        case SCN_UPDATEUI:
            markiereKlammern()
            if meldung.pointee.updated & Int32(SC_UPDATE_SELECTION | SC_UPDATE_V_SCROLL) != 0 {
                hebeAuswahlHervor()
            }
        case SCN_ZOOM:
            zeilennummernStellen = 0
            passeZeilennummernAn()
        default:
            break
        }
    }
}

/// Scintilla erwartet Farben als 0xBBGGRR; Notepad++ schreibt sie als RRGGBB.
func scintillaFarbe(_ rgb: Int) -> Int {
    ((rgb & 0xFF) << 16) | (rgb & 0xFF00) | ((rgb >> 16) & 0xFF)
}
