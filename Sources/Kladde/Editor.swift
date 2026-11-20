import AppKit
import ScintillaBruecke

/// Eine ScintillaView samt ihrer Einrichtung. Alles, was die App vom
/// Editor-Kern will, geht hier durch.
final class Editor: NSObject, ScintillaNotificationProtocol {
    let ansicht = KladdeScintillaView(frame: NSRect(x: 0, y: 0, width: 900, height: 650))
    /// Das Kontextmenü beim Rechtsklick (das von Notepad++, nicht das von Scintilla).
    var kontextmenue: (() -> NSMenu?)? {
        get { ansicht.kontextmenue }
        set { ansicht.kontextmenue = newValue }
    }

    /// Der Text weicht vom gesicherten Stand ab (true) oder stimmt wieder (false).
    var geaendert: ((Bool) -> Void)?
    /// Auswahl, Text oder Modus haben sich geändert (für die Statusleiste).
    var zustandGeaendert: (() -> Void)?
    /// Diese Ansicht hat den Fokus bekommen (für die geteilte Ansicht).
    var fokussiert: (() -> Void)?
    /// Die Sprache ist eine andere (für die zweite Ansicht desselben Dokuments).
    var spracheGewechselt: ((Sprache) -> Void)?
    /// Ein Schritt der Makro-Aufnahme: Nachricht, wParam, lParam.
    var makroSchritt: ((UInt32, UInt, Int) -> Void)?

    private(set) var sprache = Sprachdaten.gemeinsam.normal
    /// Miniaturansicht: ohne Ränder, stark verkleinert, ohne Rollbalken.
    var istKarte = false
    private var zeilennummernStellen = 0
    private var klammerMarkiert = false
    private var beobachter: NSObjectProtocol?

    /// Rand 0 Zeilennummern, Rand 1 Lesezeichen, Rand 2 Faltung.
    private static let randLesezeichen = 1
    private static let randFaltung: UInt = 2
    /// Marke für Lesezeichen, wie MARK_BOOKMARK in Notepad++.
    static let markeLesezeichen = 20

    override init() {
        super.init()
        ansicht.delegate = self
        richteEin()
        setzeSprache(sprache)
        beobachte()
    }

    /// Eine zweite Ansicht auf denselben Text (geteilte Ansicht): Text,
    /// Widerrufen, Lexer, Lesezeichen und Markierungen teilen beide.
    init(teiltMit erster: Editor) {
        super.init()
        ansicht.delegate = self
        richteEin()
        let dokument = erster.sci(SCI_GETDOCPOINTER)
        sci(SCI_SETDOCPOINTER, 0, dokument)
        uebernimmSprache(erster.sprache)
        beobachte()
    }

    private func beobachte() {
        beobachter = NotificationCenter.default.addObserver(
            forName: Einstellungen.geaendert, object: nil, queue: .main
        ) { [weak self] _ in self?.wendeDarstellungAn() }
    }

    deinit {
        if let beobachter { NotificationCenter.default.removeObserver(beobachter) }
        // Die Ansicht kann den Editor überleben (AppKit hält sie bis zum nächsten
        // Zeichnen); ohne das ruft Scintilla einen freigegebenen Delegate.
        ansicht.delegate = nil
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
        sci(SCI_SETTABWIDTH, Einstellungen.tabbreite)
        sci(SCI_SETUSETABS, Einstellungen.tabsAlsLeerzeichen ? 0 : 1)
        sci(SCI_SETSCROLLWIDTH, 1)
        sci(SCI_SETSCROLLWIDTHTRACKING, 1)

        // Mehrere Einfügemarken und Spaltenauswahl (Wahltaste + Ziehen) wie in Notepad++.
        sci(SCI_SETMULTIPLESELECTION, 1)
        sci(SCI_SETADDITIONALSELECTIONTYPING, 1)
        sci(SCI_SETMULTIPASTE, Int(SC_MULTIPASTE_EACH))
        sci(SCI_SETVIRTUALSPACEOPTIONS, Int(SCVS_RECTANGULARSELECTION))

        sci(SCI_SETMARGINTYPEN, 0, Int(SC_MARGIN_NUMBER))

        // Lesezeichen: blaues Lesezeichen im Rand 1, Klick setzt und entfernt es.
        let lesezeichen = Self.randLesezeichen
        sci(SCI_SETMARGINTYPEN, lesezeichen, Int(SC_MARGIN_SYMBOL))
        sci(SCI_SETMARGINMASKN, lesezeichen, 1 << Self.markeLesezeichen)
        sci(SCI_SETMARGINWIDTHN, lesezeichen, 14)
        sci(SCI_SETMARGINSENSITIVEN, lesezeichen, 1)
        sci(SCI_MARKERDEFINE, Self.markeLesezeichen, Int(SC_MARK_BOOKMARK))
        sci(SCI_MARKERSETFORE, Self.markeLesezeichen, scintillaFarbe(0x1E5AA8))
        sci(SCI_MARKERSETBACK, Self.markeLesezeichen, scintillaFarbe(0x3C8CE6))
        sci(SCI_SETCARETLINEVISIBLE, 1)
        sci(SCI_SETCARETLINEVISIBLEALWAYS, 1)

        // Faltung wie in Notepad++ («Box tree»): Kästchen mit Plus und Minus, verbunden durch Linien.
        let rand = Int(Self.randFaltung)
        sci(SCI_SETMARGINTYPEN, rand, Int(SC_MARGIN_SYMBOL))
        sci(SCI_SETMARGINMASKN, rand, Int(bitPattern: UInt(SC_MASK_FOLDERS)))
        sci(SCI_SETMARGINSENSITIVEN, rand, 1)
        setzeFaltStil()
        sci(SCI_MARKERENABLEHIGHLIGHT, 1)
        sci(SCI_SETFOLDFLAGS, Int(SC_FOLDFLAG_LINEAFTER_CONTRACTED))
        // Klick auf ein Kästchen klappt; Änderungen am Text halten gefaltete Blöcke sichtbar.
        sci(SCI_SETAUTOMATICFOLD, Int(SC_AUTOMATICFOLD_SHOW | SC_AUTOMATICFOLD_CLICK | SC_AUTOMATICFOLD_CHANGE))
    }

    // MARK: Sprache

    /// Neuer Lexer, seine Wörter und Eigenschaften, dann Farben und Faltung.
    func setzeSprache(_ neu: Sprache) {
        let regel = Sprachregel.fuer(neu)
        // Scintilla übernimmt den Lexer und gibt den alten frei. Unbekannt oder
        // «null»: ohne Lexer, also ohne Farben und Faltung. Der Lexer gehört zum
        // Text, nicht zur Ansicht: Eine zweite Ansicht übernimmt ihn.
        let lexer = neu.istNormalerText ? nil : CreateLexer(regel.lexer)
        ansicht.setReferenceProperty(SCI_SETILEXER, parameter: 0, value: lexer)
        for (name, wert) in regel.eigenschaften { eigenschaft(name, wert) }
        if let udl = Sprachdaten.gemeinsam.benutzersprache(fuer: neu) { richteBenutzerspracheEin(udl) }
        textwoerter = nil
        uebernimmSprache(neu)
        spracheGewechselt?(neu)
    }

    /// Farben und Faltungsrand für eine Sprache, deren Lexer der Text schon hat.
    func uebernimmSprache(_ neu: Sprache) {
        sprache = neu
        wendeDarstellungAn()
        zustandGeaendert?()
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
        // aus dem Schema (meist Courier New 10) gilt nicht; sie kommt aus den Einstellungen.
        // Ohne eigene Wahl die Schrift des Farbschemas, wie in Notepad++ (dort meist
        // Courier New 10). 10 Punkt unter Windows (96 dpi) sind auf dem Mac gut 13.
        let standardStil = global["Default Style"]
        let schriftart = Einstellungen.schriftName.isEmpty
            ? (standardStil?.schriftart.flatMap { NSFont(name: $0, size: 12) != nil ? $0 : nil } ?? "Menlo")
            : Einstellungen.schriftName
        let groesse = Einstellungen.schriftName.isEmpty
            ? Int((Double(standardStil?.groesse ?? 10) * 4 / 3).rounded())
            : Einstellungen.schriftGroesse
        sci(SCI_STYLESETFONT, Int(STYLE_DEFAULT), schriftart)
        sci(SCI_STYLESETSIZE, Int(STYLE_DEFAULT), groesse)
        sci(SCI_STYLESETFORE, Int(STYLE_DEFAULT), scintillaFarbe(global["Default Style"]?.vorne ?? 0x000000))
        sci(SCI_STYLESETBACK, Int(STYLE_DEFAULT), scintillaFarbe(global["Default Style"]?.hinten ?? 0xFFFFFF))
        if let standard = global["Default Style"] { setzeSchrift(Int(STYLE_DEFAULT), standard.schrift) }
        sci(SCI_STYLECLEARALL)

        // Zeilennummern, Klammern, Steuerzeichen, Einrückungshilfen.
        for stil in global.values where (33...37).contains(stil.id) { setze(stil) }
        for abschnitt in regel.farben {
            for stil in schema.lexer[abschnitt] ?? [] { setze(stil) }
        }
        // Benutzerdefinierte Sprachen bringen ihre Farben selbst mit.
        for stil in Sprachdaten.gemeinsam.benutzersprache(fuer: sprache)?.stile ?? [] {
            if let v = stil.vorne { sci(SCI_STYLESETFORE, stil.id, scintillaFarbe(v)) }
            if let h = stil.hinten { sci(SCI_STYLESETBACK, stil.id, scintillaFarbe(h)) }
            setzeSchrift(stil.id, stil.schrift)
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
        if let f = farbe("Bookmark margin", \.hinten) { sci(SCI_SETMARGINBACKN, Self.randLesezeichen, f) }
        sci(SCI_SETMARGINTYPEN, Self.randLesezeichen, Int(SC_MARGIN_COLOUR))
        sci(SCI_SETTABWIDTH, Einstellungen.tabbreite)
        sci(SCI_SETUSETABS, Einstellungen.tabsAlsLeerzeichen ? 0 : 1)

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
        ] + Self.indikatorenStil.enumerated().map { i, ind in
            (ind, "Mark Style \(i + 1)", [0x00FFFF, 0xFF8000, 0xFFFF00, 0x8000FF, 0x008000][i])
        }
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
        sci(SCI_SETWRAPVISUALFLAGS, Int(Einstellungen.umbruchSymbol ? SC_WRAPVISUALFLAG_END : SC_WRAPVISUALFLAG_NONE))
        sci(SCI_SETVIEWEOL, Einstellungen.zeilenendenZeigen ? 1 : 0)
        sci(SCI_SETINDENTATIONGUIDES, Int(Einstellungen.einrueckungshilfen ? SC_IV_LOOKBOTH : SC_IV_NONE))
        wendeVerhaltenAn(schema: schema)

        zeilennummernStellen = 0
        passeZeilennummernAn()
        if istKarte {
            for rand in 0...2 { sci(SCI_SETMARGINWIDTHN, rand, 0) }
            sci(SCI_SETZOOM, -10)
            sci(SCI_SETCARETLINEVISIBLE, 0)
            sci(SCI_SETHSCROLLBAR, 0)
            sci(SCI_SETVSCROLLBAR, 0)
            sci(SCI_SETINDENTATIONGUIDES, Int(SC_IV_NONE))
            sci(SCI_SETVIEWWS, Int(SCWS_INVISIBLE))
            sci(SCI_SETVIEWEOL, 0)
        }
        sci(SCI_COLOURISE, 0, -1)
    }

    /// Die Optionen aus «Bearbeiten 1/2», «Ränder/Rahmen/Umrandung» und «Einrückungen»,
    /// wie ScintillaEditView sie in Notepad++ setzt.
    private func wendeVerhaltenAn(schema: Farbschema) {
        // Aktuelle Zeile: keine, Hintergrund oder Rahmen mit Breite 1–6.
        let zeile = Einstellungen.aktuelleZeile
        sci(SCI_SETCARETLINEVISIBLE, zeile == 0 ? 0 : 1)
        sci(SCI_SETCARETLINEFRAME, zeile == 2 ? Einstellungen.aktuelleZeileRahmen : 0)
        // Cursor: Breite 0–3 oder Block; Blinkfrequenz.
        let breite = Einstellungen.cursorBreite
        sci(SCI_SETCARETSTYLE, Int(breite == 4 ? CARETSTYLE_BLOCK : CARETSTYLE_LINE))
        if breite < 4 { sci(SCI_SETCARETWIDTH, breite) }
        sci(SCI_SETCARETPERIOD, Einstellungen.cursorBlinken)
        // Zeilenumbruch: Standard, ausgerichtet, eingerückt.
        sci(SCI_SETWRAPINDENTMODE, Int([SC_WRAPINDENT_FIXED, SC_WRAPINDENT_SAME, SC_WRAPINDENT_INDENT][Einstellungen.umbruchArt]))
        sci(SCI_SETVIRTUALSPACEOPTIONS, Int(SCVS_RECTANGULARSELECTION | (Einstellungen.virtuellerRaum ? SCVS_USERACCESSIBLE : 0)))
        sci(SCI_SETENDATLASTLINE, Einstellungen.ueberLetzteZeile ? 0 : 1)
        sci(SCI_SETMULTIPLESELECTION, Einstellungen.mehrfachBearbeitung ? 1 : 0)
        sci(SCI_SETADDITIONALSELECTIONTYPING, Einstellungen.mehrfachBearbeitung ? 1 : 0)
        sci(SCI_SETBACKSPACEUNINDENTS, Einstellungen.rueckLoeschtEinzug ? 1 : 0)
        guard !istKarte else { return }
        // Ränder: Lesezeichen, Faltung, Abstand links und rechts.
        sci(SCI_SETMARGINWIDTHN, Self.randLesezeichen, Einstellungen.lesezeichenRand ? 14 : 0)
        setzeFaltStil()
        sci(SCI_SETMARGINLEFT, 0, Einstellungen.randLinks)
        sci(SCI_SETMARGINRIGHT, 0, Einstellungen.randRechts)
        // Senkrechte Kanten: mehrere Spalten als Linien, eine Spalte auch als Hintergrund.
        let spalten = Einstellungen.kanten.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.filter { $0 > 0 }
        let kantenfarbe = scintillaFarbe(schema.global["Edge colour"]?.vorne ?? 0x80FFFF)
        sci(SCI_MULTIEDGECLEARALL)
        if spalten.isEmpty {
            sci(SCI_SETEDGEMODE, Int(EDGE_NONE))
        } else if spalten.count == 1, Einstellungen.kanteHintergrund {
            sci(SCI_SETEDGEMODE, Int(EDGE_BACKGROUND))
            sci(SCI_SETEDGECOLUMN, spalten[0])
            sci(SCI_SETEDGECOLOUR, kantenfarbe)
        } else {
            sci(SCI_SETEDGEMODE, Int(EDGE_MULTILINE))
            for s in spalten { sci(SCI_MULTIEDGEADDLINE, s, kantenfarbe) }
        }
        // Änderungshistorie: Rand 3 mit den Markern von Scintilla, auf Wunsch im Text.
        sci(SCI_SETMARGINTYPEN, Self.randAenderungen, Int(SC_MARGIN_SYMBOL))
        sci(SCI_SETMARGINMASKN, Self.randAenderungen,
            (1 << SC_MARKNUM_HISTORY_REVERTED_TO_ORIGIN) | (1 << SC_MARKNUM_HISTORY_SAVED)
                | (1 << SC_MARKNUM_HISTORY_MODIFIED) | (1 << SC_MARKNUM_HISTORY_REVERTED_TO_MODIFIED))
        sci(SCI_SETMARGINWIDTHN, Self.randAenderungen, Einstellungen.aenderungenAmRand ? 9 : 0)
        passeAenderungshistorieAn()
    }

    static let randAenderungen = 3

    /// Scintilla führt die Historie nur, wenn sie eingeschaltet war, bevor geändert
    /// wurde; beim Laden und für neue Dokumente gilt sie darum sofort, sonst ab dem
    /// nächsten Öffnen (wie in Notepad++).
    func passeAenderungshistorieAn() {
        var flags = 0
        if Einstellungen.aenderungenAmRand || Einstellungen.aenderungenImText {
            flags = Int(SC_CHANGE_HISTORY_ENABLED)
            if Einstellungen.aenderungenAmRand { flags |= Int(SC_CHANGE_HISTORY_MARKERS) }
            if Einstellungen.aenderungenImText { flags |= Int(SC_CHANGE_HISTORY_INDICATORS) }
        }
        sci(SCI_SETCHANGEHISTORY, flags)
    }

    /// Die Marker des Faltungsrands wie ScintillaEditView::_markersArray in Notepad++.
    private func setzeFaltStil() {
        let nummern: [Int32] = [SC_MARKNUM_FOLDEROPEN, SC_MARKNUM_FOLDER, SC_MARKNUM_FOLDERSUB, SC_MARKNUM_FOLDERTAIL,
                                SC_MARKNUM_FOLDEREND, SC_MARKNUM_FOLDEROPENMID, SC_MARKNUM_FOLDERMIDTAIL]
        let stile: [[Int32]] = [
            [SC_MARK_MINUS, SC_MARK_PLUS, SC_MARK_EMPTY, SC_MARK_EMPTY, SC_MARK_EMPTY, SC_MARK_EMPTY, SC_MARK_EMPTY],
            [SC_MARK_ARROWDOWN, SC_MARK_ARROW, SC_MARK_EMPTY, SC_MARK_EMPTY, SC_MARK_EMPTY, SC_MARK_EMPTY, SC_MARK_EMPTY],
            [SC_MARK_CIRCLEMINUS, SC_MARK_CIRCLEPLUS, SC_MARK_VLINE, SC_MARK_LCORNERCURVE, SC_MARK_CIRCLEPLUSCONNECTED,
             SC_MARK_CIRCLEMINUSCONNECTED, SC_MARK_TCORNERCURVE],
            [SC_MARK_BOXMINUS, SC_MARK_BOXPLUS, SC_MARK_VLINE, SC_MARK_LCORNER, SC_MARK_BOXPLUSCONNECTED,
             SC_MARK_BOXMINUSCONNECTED, SC_MARK_TCORNER],
        ]
        let stil = Einstellungen.faltStil
        if stil < 4 { for (n, f) in zip(nummern, stile[stil]) { sci(SCI_MARKERDEFINE, Int(n), Int(f)) } }
        sci(SCI_SETMARGINWIDTHN, Int(Self.randFaltung), sprache.istNormalerText || stil == 4 || istKarte ? 0 : 16)
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
        guard !istKarte else { return }
        guard Einstellungen.zeilennummern else {
            sci(SCI_SETMARGINWIDTHN, 0, 0)
            zeilennummernStellen = -1
            return
        }
        // Dynamisch: so breit wie die grösste sichtbare Nummer; konstant: wie die letzte Zeile.
        let bis = Einstellungen.zeilennummernDynamisch
            ? sci(SCI_DOCLINEFROMVISIBLE, sci(SCI_GETFIRSTVISIBLELINE) + sci(SCI_LINESONSCREEN)) + 1
            : sci(SCI_GETLINECOUNT)
        let stellen = max(Einstellungen.zeilennummernDynamisch ? 1 : 3, String(bis).count)
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
        sci(SCI_SETCHANGEHISTORY, 0)
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
        passeAenderungshistorieAn()
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

    /// Wie weit waagrecht gescrollt ist (Pixel).
    var waagrechteLage: Int {
        get { sci(SCI_GETXOFFSET) }
        set { sci(SCI_SETXOFFSET, max(0, newValue)) }
    }

    /// Direkter Zugang für die Befehle des Hauptfensters.
    @discardableResult
    func nachricht(_ n: Int32, _ w: Int = 0, _ l: Int = 0) -> Int { sci(n, w, l) }

    @discardableResult
    func nachricht(_ n: Int32, _ w: Int, text: String) -> Int { sci(n, w, text) }

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
    /// «Alle Treffer hervorheben» mit Stil 1–5 (Mark Style 1–5 in Notepad++).
    static let indikatorenStil: [Int32] = [25, 24, 23, 22, 21]

    /// Das Wort an der Marke (oder die Auswahl) mit Stil 1–5 hervorheben, überall oder nur hier.
    func hebeHervor(stil: Int, alle: Bool) {
        var a = auswahl
        if a.isEmpty {
            let m = sci(SCI_GETCURRENTPOS)
            a = sci(SCI_WORDSTARTPOSITION, m, 1)..<sci(SCI_WORDENDPOSITION, m, 1)
        }
        guard !a.isEmpty, let wort = text(a) else { return }
        let indikator = Self.indikatorenStil[stil - 1]
        guard alle else { return markiere([a], indikator: indikator) }
        var o = SuchOptionen()
        o.text = wort
        o.grossKlein = true
        o.ganzesWort = sci(SCI_WORDSTARTPOSITION, a.lowerBound, 1) == a.lowerBound && sci(SCI_WORDENDPOSITION, a.lowerBound, 1) == a.upperBound
        guard let muster = try? Suchmuster(o) else { return }
        markiere(muster.alle(in: suchtext).map(\.bereich), indikator: indikator)
    }

    /// Zur nächsten oder vorherigen Stelle mit Stil (nil: irgendein Stil 1–5).
    func springeZuMarkierung(stil: Int?, weiter: Bool) {
        let liste = stil.map { [Self.indikatorenStil[$0 - 1]] } ?? Self.indikatorenStil
        let marke = sci(SCI_GETCURRENTPOS)
        var beste: Int?
        for ind in liste {
            var stelle = 0
            let laenge = sci(SCI_GETLENGTH)
            while stelle < laenge {
                let ende = sci(SCI_INDICATOREND, Int(ind), stelle)
                if sci(SCI_INDICATORVALUEAT, Int(ind), stelle) != 0 {
                    let obergrenze = beste ?? Int.max
                    let untergrenze = beste ?? -1
                    if weiter && marke < stelle && stelle < obergrenze { beste = stelle }
                    if !weiter && stelle < marke && untergrenze < stelle { beste = stelle }
                }
                guard ende > stelle else { break }
                stelle = ende
            }
        }
        guard let ziel = beste else { return NSSound.beep() }
        waehleAus(ziel..<sci(SCI_INDICATOREND, Int(liste.first { sci(SCI_INDICATORVALUEAT, Int($0), ziel) != 0 } ?? liste[0]), ziel))
    }

    /// Der Text aller Stellen mit diesen Indikatoren, je Stelle eine Zeile.
    func markierterText(_ indikatoren: [Int32]) -> String {
        var stuecke: [(Int, String)] = []
        for ind in indikatoren {
            var stelle = 0
            let laenge = sci(SCI_GETLENGTH)
            while stelle < laenge {
                let ende = sci(SCI_INDICATOREND, Int(ind), stelle)
                if sci(SCI_INDICATORVALUEAT, Int(ind), stelle) != 0, ende > stelle, let t = text(stelle..<ende) { stuecke.append((stelle, t)) }
                guard ende > stelle else { break }
                stelle = ende
            }
        }
        return stuecke.sorted { $0.0 < $1.0 }.map(\.1).joined(separator: zeilenende)
    }

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
        guard Einstellungen.smartHighlighting, sci(SCI_GETSELECTIONS) == 1 else { return }
        let bereich = auswahl
        let ganzesWort = Einstellungen.smartGanzesWort
        guard !bereich.isEmpty, bereich.count < 200,
            sci(SCI_LINEFROMPOSITION, bereich.lowerBound) == sci(SCI_LINEFROMPOSITION, bereich.upperBound),
            !ganzesWort || sci(SCI_WORDSTARTPOSITION, bereich.lowerBound, 1) == bereich.lowerBound,
            !ganzesWort || sci(SCI_WORDENDPOSITION, bereich.lowerBound, 1) == bereich.upperBound,
            let wort = text(bereich), !wort.allSatisfy(\.isWhitespace)
        else { return }

        // Nur der sichtbare Teil, wie Notepad++: grosse Dateien bleiben schnell.
        let oben = sci(SCI_DOCLINEFROMVISIBLE, sci(SCI_GETFIRSTVISIBLELINE))
        let unten = sci(SCI_DOCLINEFROMVISIBLE, sci(SCI_GETFIRSTVISIBLELINE) + sci(SCI_LINESONSCREEN) + 1)
        let von = sci(SCI_POSITIONFROMLINE, oben)
        let bis = sci(SCI_GETLINEENDPOSITION, unten)
        guard bis > von, let sichtbar = text(von..<bis) else { return }

        var optionen = SuchOptionen()
        optionen.text = wort
        optionen.ganzesWort = ganzesWort
        optionen.grossKlein = Einstellungen.smartGrossKlein
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

    // MARK: Zustand

    private var zustandAngemeldet = false

    /// Höchstens einmal je Durchlauf der Ereignisschleife, auch bei vielen Änderungen.
    private func meldeZustand() {
        guard zustandGeaendert != nil, !zustandAngemeldet else { return }
        zustandAngemeldet = true
        DispatchQueue.main.async { [weak self] in
            self?.meldeZustandJetzt()
        }
    }

    private func meldeZustandJetzt() {
        zustandAngemeldet = false
        zustandGeaendert?()
    }

    /// Zahlen für die Statusleiste.
    struct Stand {
        var laenge: Int
        var zeilen: Int
        var zeile: Int
        var spalte: Int
        var ausgewaehlteZeichen: Int
        var ausgewaehlteZeilen: Int
        var auswahlen: Int
        var ueberschreiben: Bool
    }

    var stand: Stand {
        let marke = sci(SCI_GETCURRENTPOS)
        var zeichen = 0
        var zeilen = 0
        let anzahl = sci(SCI_GETSELECTIONS)
        for i in 0..<anzahl {
            let von = sci(SCI_GETSELECTIONNSTART, i)
            let bis = sci(SCI_GETSELECTIONNEND, i)
            guard bis > von else { continue }
            zeichen += sci(SCI_COUNTCHARACTERS, von, bis)
            zeilen += sci(SCI_LINEFROMPOSITION, bis) - sci(SCI_LINEFROMPOSITION, von) + 1
        }
        return Stand(
            laenge: sci(SCI_COUNTCHARACTERS, 0, sci(SCI_GETLENGTH)), zeilen: sci(SCI_GETLINECOUNT),
            zeile: sci(SCI_LINEFROMPOSITION, marke) + 1, spalte: sci(SCI_GETCOLUMN, marke) + 1,
            ausgewaehlteZeichen: zeichen, ausgewaehlteZeilen: zeilen, auswahlen: anzahl,
            ueberschreiben: sci(SCI_GETOVERTYPE) != 0)
    }

    func schalteUeberschreiben() {
        sci(SCI_EDITTOGGLEOVERTYPE)
        zustandGeaendert?()
    }

    // MARK: Zeilen

    /// Das Zeilenende, das neue Zeilen bekommen.
    var zeilenende: String {
        switch Int32(sci(SCI_GETEOLMODE)) {
        case SC_EOL_CRLF: return "\r\n"
        case SC_EOL_CR: return "\r"
        default: return "\n"
        }
    }

    /// Die Zeilen, auf die ein Zeilenbefehl wirkt: die der Auswahl (endet sie
    /// am Anfang einer Zeile, zählt diese nicht mit), ohne Auswahl über mehrere
    /// Zeilen der ganze Text. Ein Zeilenende ganz am Schluss bleibt draussen.
    func zeilenFuerBefehl() -> (bereich: Range<Int>, zeilen: [String]) {
        let a = auswahl
        let ersteZeile = sci(SCI_LINEFROMPOSITION, a.lowerBound)
        var letzteZeile = sci(SCI_LINEFROMPOSITION, a.upperBound)
        if letzteZeile > ersteZeile, sci(SCI_POSITIONFROMLINE, letzteZeile) == a.upperBound { letzteZeile -= 1 }
        var bereich: Range<Int>
        if letzteZeile > ersteZeile {
            bereich = sci(SCI_POSITIONFROMLINE, ersteZeile)..<sci(SCI_GETLINEENDPOSITION, letzteZeile)
        } else {
            let letzte = sci(SCI_GETLINECOUNT) - 1
            var ende = sci(SCI_GETLENGTH)
            if letzte > 0, sci(SCI_POSITIONFROMLINE, letzte) == ende { ende = sci(SCI_GETLINEENDPOSITION, letzte - 1) }
            bereich = 0..<ende
        }
        let text = self.text(bereich) ?? ""
        return (bereich, text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init))
    }

    /// Ersetzt den Bereich durch die Zeilen (mit dem Zeilenende des Textes) und wählt sie aus.
    func ersetzeZeilen(_ bereich: Range<Int>, durch zeilen: [String]) {
        let neu = zeilen.joined(separator: zeilenende)
        guard text(bereich) != neu else { return }
        ersetze([(bereich, neu)])
        sci(SCI_SETSEL, bereich.lowerBound, bereich.lowerBound + neu.utf8.count)
    }

    /// Ersetzt die Auswahl (ohne Auswahl: das Wort an der Marke) durch eine Umwandlung.
    func wandleAuswahl(_ umwandlung: (String) -> String) {
        var a = auswahl
        if a.isEmpty {
            let marke = sci(SCI_GETCURRENTPOS)
            a = sci(SCI_WORDSTARTPOSITION, marke, 1)..<sci(SCI_WORDENDPOSITION, marke, 1)
        }
        guard !a.isEmpty, let alt = text(a) else { return }
        let neu = umwandlung(alt)
        guard neu != alt else { return }
        ersetze([(a, neu)])
        sci(SCI_SETSEL, a.lowerBound, a.lowerBound + neu.utf8.count)
    }

    func dupliziere() { sci(auswahl.isEmpty ? SCI_LINEDUPLICATE : SCI_SELECTIONDUPLICATE) }
    func zeilenHoch() { sci(SCI_MOVESELECTEDLINESUP) }
    func zeilenRunter() { sci(SCI_MOVESELECTEDLINESDOWN) }

    /// Löscht alle Zeilen, die die Auswahl berührt, samt Zeilenende.
    func loescheZeilen() {
        let a = auswahl
        let erste = sci(SCI_LINEFROMPOSITION, a.lowerBound)
        var letzte = sci(SCI_LINEFROMPOSITION, a.upperBound)
        if letzte > erste, sci(SCI_POSITIONFROMLINE, letzte) == a.upperBound { letzte -= 1 }
        let von = sci(SCI_POSITIONFROMLINE, erste)
        var bis = sci(SCI_POSITIONFROMLINE, letzte + 1)
        if letzte + 1 >= sci(SCI_GETLINECOUNT) { bis = sci(SCI_GETLENGTH) }
        var anfang = von
        // Letzte Zeile ohne Zeilenende: das Ende der Zeile davor mitnehmen.
        if letzte + 1 >= sci(SCI_GETLINECOUNT), erste > 0 { anfang = sci(SCI_GETLINEENDPOSITION, erste - 1) }
        ersetze([(anfang..<bis, "")])
    }

    func verbindeZeilen() {
        let a = auswahl
        let erste = sci(SCI_LINEFROMPOSITION, a.lowerBound)
        var letzte = sci(SCI_LINEFROMPOSITION, a.upperBound)
        if letzte == erste { letzte = min(erste + 1, sci(SCI_GETLINECOUNT) - 1) }
        sci(SCI_SETTARGETRANGE, sci(SCI_POSITIONFROMLINE, erste), sci(SCI_GETLINEENDPOSITION, letzte))
        sci(SCI_BEGINUNDOACTION)
        sci(SCI_LINESJOIN)
        sci(SCI_ENDUNDOACTION)
    }

    /// Kommentar umschalten nach den Zeichen der Sprache aus langs.model.xml.
    /// Ohne Zeilenkommentar (etwa HTML) umschliesst ein Blockkommentar die Auswahl.
    func schalteKommentar(block: Bool, art: Kommentar.Art = .umschalten) {
        if !block, let zeichen = sprache.kommentarZeile {
            let (bereich, zeilen) = zeilenFuerBefehlOhneGanzenText()
            ersetzeZeilen(bereich, durch: Kommentar.zeilenUmschalten(zeilen, zeichen: zeichen, art: art))
            return
        }
        guard let anfang = sprache.kommentarAnfang, let ende = sprache.kommentarEnde else { return NSSound.beep() }
        if auswahl.isEmpty {
            let zeile = sci(SCI_LINEFROMPOSITION, sci(SCI_GETCURRENTPOS))
            sci(SCI_SETSEL, sci(SCI_POSITIONFROMLINE, zeile), sci(SCI_GETLINEENDPOSITION, zeile))
        }
        wandleAuswahl { Kommentar.blockUmschalten($0, anfang: anfang, ende: ende) }
    }

    /// Wie zeilenFuerBefehl, aber ohne Auswahl nur die Zeile der Marke.
    private func zeilenFuerBefehlOhneGanzenText() -> (bereich: Range<Int>, zeilen: [String]) {
        let a = auswahl
        let erste = sci(SCI_LINEFROMPOSITION, a.lowerBound)
        var letzte = sci(SCI_LINEFROMPOSITION, a.upperBound)
        if letzte > erste, sci(SCI_POSITIONFROMLINE, letzte) == a.upperBound { letzte -= 1 }
        let bereich = sci(SCI_POSITIONFROMLINE, erste)..<sci(SCI_GETLINEENDPOSITION, letzte)
        let text = self.text(bereich) ?? ""
        return (bereich, text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init))
    }

    // MARK: Spalteneditor

    /// Fügt je Zeile einen Text ein, in derselben Spalte. Mit Rechteck- oder
    /// Mehrfachauswahl in deren Zeilen, sonst von der Zeile der Marke bis zum
    /// Ende (wie «Column Editor» in Notepad++). Kurze Zeilen werden mit
    /// Leerzeichen aufgefüllt. Antwort: wie viele Zeilen.
    func fuegeInSpalteEin(_ texte: (Int) -> [String]) -> Int {
        let modus = Int32(sci(SCI_GETSELECTIONMODE))
        let erste: Int
        let letzte: Int
        let spalte: Int
        if modus == SC_SEL_RECTANGLE || modus == SC_SEL_THIN {
            let anker = sci(SCI_GETRECTANGULARSELECTIONANCHOR)
            let marke = sci(SCI_GETRECTANGULARSELECTIONCARET)
            let a = sci(SCI_LINEFROMPOSITION, anker)
            let m = sci(SCI_LINEFROMPOSITION, marke)
            erste = min(a, m)
            letzte = max(a, m)
            spalte = min(
                sci(SCI_GETCOLUMN, anker) + sci(SCI_GETRECTANGULARSELECTIONANCHORVIRTUALSPACE),
                sci(SCI_GETCOLUMN, marke) + sci(SCI_GETRECTANGULARSELECTIONCARETVIRTUALSPACE))
        } else if sci(SCI_GETSELECTIONS) > 1 {
            let zeilen = (0..<sci(SCI_GETSELECTIONS)).map { sci(SCI_LINEFROMPOSITION, sci(SCI_GETSELECTIONNCARET, $0)) }
            erste = zeilen.min() ?? 0
            letzte = zeilen.max() ?? 0
            spalte = sci(SCI_GETCOLUMN, sci(SCI_GETSELECTIONNCARET, sci(SCI_GETMAINSELECTION)))
        } else {
            let marke = sci(SCI_GETCURRENTPOS)
            erste = sci(SCI_LINEFROMPOSITION, marke)
            letzte = sci(SCI_GETLINECOUNT) - 1
            spalte = sci(SCI_GETCOLUMN, marke)
        }
        let liste = texte(letzte - erste + 1)
        sci(SCI_BEGINUNDOACTION)
        for zeile in stride(from: letzte, through: erste, by: -1) {
            let stelle = sci(SCI_FINDCOLUMN, zeile, spalte)
            let fehlt = spalte - sci(SCI_GETCOLUMN, stelle)
            let einfuegen = String(repeating: " ", count: max(0, fehlt)) + liste[zeile - erste]
            einfuegen.withCString { _ = sci(SCI_INSERTTEXT, stelle, Int(bitPattern: $0)) }
        }
        sci(SCI_ENDUNDOACTION)
        sci(SCI_SETEMPTYSELECTION, sci(SCI_FINDCOLUMN, erste, spalte))
        return letzte - erste + 1
    }

    // MARK: Lesezeichen

    func schalteLesezeichen(zeile: Int? = nil) {
        let z = zeile ?? sci(SCI_LINEFROMPOSITION, sci(SCI_GETCURRENTPOS))
        if sci(SCI_MARKERGET, z) & (1 << Self.markeLesezeichen) != 0 {
            sci(SCI_MARKERDELETE, z, Self.markeLesezeichen)
        } else {
            sci(SCI_MARKERADD, z, Self.markeLesezeichen)
        }
    }

    /// Zum nächsten oder vorherigen Lesezeichen, am Ende rundherum.
    func springeZuLesezeichen(rueckwaerts: Bool) {
        let maske = 1 << Self.markeLesezeichen
        let zeile = sci(SCI_LINEFROMPOSITION, sci(SCI_GETCURRENTPOS))
        var ziel = rueckwaerts ? sci(SCI_MARKERPREVIOUS, zeile - 1, maske) : sci(SCI_MARKERNEXT, zeile + 1, maske)
        if ziel < 0 {
            ziel = rueckwaerts ? sci(SCI_MARKERPREVIOUS, sci(SCI_GETLINECOUNT), maske) : sci(SCI_MARKERNEXT, 0, maske)
        }
        guard ziel >= 0 else { return NSSound.beep() }
        geheZuZeile(ziel + 1)
    }

    /// Die Zeilen mit Lesezeichen, ab 0.
    var lesezeichen: [Int] {
        get {
            var zeilen: [Int] = []
            var z = sci(SCI_MARKERNEXT, 0, 1 << Self.markeLesezeichen)
            while z >= 0 {
                zeilen.append(z)
                z = sci(SCI_MARKERNEXT, z + 1, 1 << Self.markeLesezeichen)
            }
            return zeilen
        }
        set {
            sci(SCI_MARKERDELETEALL, Self.markeLesezeichen)
            for z in newValue where z < sci(SCI_GETLINECOUNT) { sci(SCI_MARKERADD, z, Self.markeLesezeichen) }
        }
    }

    func setzeLesezeichen(fuer bereiche: [Range<Int>]) {
        for bereich in bereiche { sci(SCI_MARKERADD, sci(SCI_LINEFROMPOSITION, bereich.lowerBound), Self.markeLesezeichen) }
    }

    /// Lesezeichen umkehren: wo eines ist, keins mehr, und umgekehrt.
    func kehreLesezeichenUm() {
        let alt = Set(lesezeichen)
        lesezeichen = (0..<sci(SCI_GETLINECOUNT)).filter { !alt.contains($0) }
    }

    /// Der Text der Zeilen mit Lesezeichen (mit Zeilenende), etwa zum Kopieren.
    func lesezeichenText() -> String {
        lesezeichen.compactMap { z in text(sci(SCI_POSITIONFROMLINE, z)..<sci(SCI_GETLINEENDPOSITION, z)) }
            .map { $0 + zeilenende }.joined()
    }

    /// Löscht die Zeilen mit Lesezeichen (oder alle ohne) in einem Schritt.
    func loescheZeilenMitLesezeichen(ohne: Bool = false) {
        let mit = Set(lesezeichen)
        let zeilen = (0..<sci(SCI_GETLINECOUNT)).filter { ohne ? !mit.contains($0) : mit.contains($0) }
        let bereiche = zeilen.map { z -> Range<Int> in
            let von = sci(SCI_POSITIONFROMLINE, z)
            let bis = z + 1 < sci(SCI_GETLINECOUNT) ? sci(SCI_POSITIONFROMLINE, z + 1) : sci(SCI_GETLENGTH)
            return von..<bis
        }
        ersetze(bereiche.map { ($0, "") })
    }

    // MARK: Makros

    func starteAufnahme() { sci(SCI_STARTRECORD) }
    func beendeAufnahme() { sci(SCI_STOPRECORD) }

    /// Spielt Schritte ab. Text liegt in den Schritten als String; der Zeiger
    /// gilt nur während des Aufrufs.
    func spiele(_ schritte: [Makroschritt]) {
        for schritt in schritte {
            if let text = schritt.text {
                let bytes = Array(text.utf8) + [0]
                bytes.withUnsafeBufferPointer { zeiger in
                    let w = schritt.wMitLaenge ? UInt(bytes.count - 1) : schritt.w
                    _ = ansicht.message(schritt.nachricht, wParam: w, lParam: Int(bitPattern: zeiger.baseAddress))
                }
            } else {
                _ = ansicht.message(schritt.nachricht, wParam: schritt.w, lParam: schritt.l)
            }
        }
    }

    /// Text ab einem Zeiger von Scintilla: mit Länge, oder bis zum Nullbyte.
    static func text(zeiger: Int, laenge: Int?) -> String? {
        guard let p = UnsafeRawPointer(bitPattern: zeiger) else { return nil }
        if let laenge { return String(decoding: UnsafeRawBufferPointer(start: p, count: laenge), as: UTF8.self) }
        return String(cString: p.assumingMemoryBound(to: CChar.self))
    }

    var marke: Int { sci(SCI_GETCURRENTPOS) }
    var laenge: Int { sci(SCI_GETLENGTH) }

    func beginneSchritt() { sci(SCI_BEGINUNDOACTION) }
    func beendeSchritt() { sci(SCI_ENDUNDOACTION) }

    // MARK: Tippen

    /// Neue Zeile mit der Einrückung der vorherigen (Auto-Einzug in Notepad++).
    private func ruecke() {
        let zeile = sci(SCI_LINEFROMPOSITION, sci(SCI_GETCURRENTPOS))
        guard zeile > 0 else { return }
        let einzug = sci(SCI_GETLINEINDENTATION, zeile - 1)
        guard einzug > 0 else { return }
        sci(SCI_SETLINEINDENTATION, zeile, einzug)
        sci(SCI_GOTOPOS, sci(SCI_GETLINEINDENTPOSITION, zeile))
    }

    /// Schliesst Klammern und Anführungszeichen (Notepad++: «Auto-Insert»).
    private func schliesseKlammer(_ zeichen: Int32) {
        let paare: [Int32: String] = [0x28: ")", 0x5B: "]", 0x7B: "}", 0x22: "\"", 0x27: "'"]
        guard sci(SCI_GETSELECTIONS) == 1, let zu = paare[zeichen],
              let auf = UnicodeScalar(UInt32(zeichen)).map(Character.init), Einstellungen.schliesst(auf) else { return }
        let marke = sci(SCI_GETCURRENTPOS)
        // Anführungszeichen nur, wenn danach kein Wortzeichen folgt und davor keins steht.
        if zeichen == 0x22 || zeichen == 0x27 {
            let davor = marke >= 2 ? sci(SCI_GETCHARAT, marke - 2) & 0xFF : 0
            if davor != 0, (UInt8(davor) as UInt8).isWortzeichen { return }
        }
        let danach = sci(SCI_GETCHARAT, marke) & 0xFF
        if danach != 0, (UInt8(danach) as UInt8).isWortzeichen { return }
        zu.withCString { _ = sci(SCI_INSERTTEXT, marke, Int(bitPattern: $0)) }
    }

    // MARK: Benutzerdefinierte Sprache

    /// Wie setUserLexer in Notepad++: Schalter und einige Listen als
    /// Eigenschaften, die übrigen Listen der Reihe nach mit SCI_SETKEYWORDS,
    /// dazu die Verschachtelung der Stile.
    private func richteBenutzerspracheEin(_ udl: Benutzersprache) {
        eigenschaft("fold", "1")
        eigenschaft("userDefine.isCaseIgnored", udl.ohneGrossKlein ? "1" : "0")
        eigenschaft("userDefine.allowFoldOfComments", udl.kommentareFalten ? "1" : "0")
        eigenschaft("userDefine.foldCompact", udl.kompaktFalten ? "1" : "0")
        for (i, praefix) in udl.praefix.enumerated() { eigenschaft("userDefine.prefixKeywords\(i + 1)", praefix ? "1" : "0") }
        var liste = 0
        for (i, woerter) in udl.listen.enumerated() {
            if let name = Benutzersprache.eigenschaften[i] {
                eigenschaft(name, woerter)
            } else {
                sci(SCI_SETKEYWORDS, liste, Benutzersprache.aufbereitet(woerter))
                liste += 1
            }
        }
        eigenschaft("userDefine.forcePureLC", "\(udl.reinesLC)")
        eigenschaft("userDefine.decimalSeparator", "\(udl.dezimaltrenner)")
        // Der Lexer merkt sich Zustand je Sprache und Text; beides braucht eine feste Zahl.
        eigenschaft("userDefine.udlName", "\(UInt(bitPattern: udl.name.hashValue))")
        eigenschaft("userDefine.currentBufferID", "\(UInt(bitPattern: ObjectIdentifier(self).hashValue))")
        for stil in udl.stile { eigenschaft(String(format: "userDefine.nesting.%02d", stil.id), "\(stil.verschachtelung)") }
    }

    // MARK: Vorschläge und Aufrufhilfe

    /// Zählt jede Änderung am Text (für die Funktionsliste).
    private(set) var aenderungszahl = 0

    /// Die Wörter des Textes, neu gezählt nach jeder Änderung (bei grossen Texten keine).
    private var textwoerter: Set<String>?
    /// Wo die Klammer der Aufrufhilfe steht, solange sie offen ist.
    private var aufrufStelle: Int?
    private var aufrufName = ""

    /// Nach jedem getippten Zeichen: Aufrufhilfe bei «(», «,» und «)», sonst Vorschläge.
    private func hilf(nach zeichen: Int32) {
        let schatz = Sprachdaten.gemeinsam.wortschatz(fuer: sprache)
        let z = UnicodeScalar(UInt32(max(0, zeichen))).map(Character.init)
        if let z, z == schatz.aufrufAnfang {
            if Einstellungen.aufrufhilfeAn { zeigeAufrufhilfe(schatz) }
            return
        }
        if let z, z == schatz.aufrufEnde {
            sci(SCI_CALLTIPCANCEL)
            aufrufStelle = nil
            return
        }
        if let z, z == schatz.trenner, aufrufStelle != nil {
            aktualisiereAufrufhilfe(schatz)
            return
        }
        schlageVor(schatz, zeichen: z)
    }

    /// Vorschläge auf Befehl (Bearbeiten → Autovervollständigung), auch ab einem Zeichen.
    func schlageVorJetzt(nurText: Bool) {
        let schatz = nurText ? Wortschatz.leer : Sprachdaten.gemeinsam.wortschatz(fuer: sprache)
        schlageVor(schatz, zeichen: "a", ab: 1)
    }

    func zeigeAufrufhilfeJetzt() {
        // Die Klammer vor der Marke suchen und dort die Hilfe zeigen.
        let marke = sci(SCI_GETCURRENTPOS)
        var stelle = marke - 1
        var tiefe = 0
        while stelle > 0 {
            let z = sci(SCI_GETCHARAT, stelle) & 0xFF
            if z == 0x29 { tiefe += 1 } else if z == 0x28 { if tiefe == 0 { break } else { tiefe -= 1 } }
            if z == 0x0A { stelle = 0; break }
            stelle -= 1
        }
        guard stelle > 0 else { return NSSound.beep() }
        sci(SCI_GOTOPOS, stelle + 1)
        zeigeAufrufhilfe(Sprachdaten.gemeinsam.wortschatz(fuer: sprache))
        sci(SCI_GOTOPOS, marke)
    }

    private func schlageVor(_ schatz: Wortschatz, zeichen: Character?, ab vorgabe: Int? = nil) {
        let ab = vorgabe ?? (Einstellungen.vervollstaendigenAn ? max(1, Einstellungen.vervollstaendigenAb) : 0)
        guard ab > 0, let zeichen, zeichen.isLetter || zeichen.isNumber || zeichen == "_" else { return }
        let marke = sci(SCI_GETCURRENTPOS)
        let anfang = sci(SCI_WORDSTARTPOSITION, marke, 1)
        guard marke > anfang, let wort = text(anfang..<marke), wort.count >= ab else { return }
        if textwoerter == nil, sci(SCI_GETLENGTH) < 2_000_000 {
            textwoerter = Wortschatz.woerter(in: String(decoding: utf8, as: UTF8.self))
        }
        // «Funktionsvervollständigung», «Wortvervollständigung» oder beides.
        let art = vorgabe == nil ? Einstellungen.vervollstaendigenArt : 2
        let liste = (art == 1 ? Wortschatz.leer : schatz).vorschlaege(fuer: wort, ausText: art == 0 ? [] : textwoerter ?? [])
        guard !liste.isEmpty else {
            if sci(SCI_AUTOCACTIVE) != 0 { sci(SCI_AUTOCCANCEL) }
            return
        }
        sci(SCI_AUTOCSETSEPARATOR, 10)
        sci(SCI_AUTOCSETIGNORECASE, 1)
        sci(SCI_AUTOCSETORDER, Int(SC_ORDER_PERFORMSORT))
        sci(SCI_AUTOCSETMAXHEIGHT, 10)
        sci(SCI_AUTOCSHOW, marke - anfang, liste.joined(separator: "\n"))
    }

    private func zeigeAufrufhilfe(_ schatz: Wortschatz) {
        let klammer = sci(SCI_GETCURRENTPOS) - 1
        guard klammer > 0 else { return }
        let anfang = sci(SCI_WORDSTARTPOSITION, klammer, 1)
        guard anfang < klammer, let name = text(anfang..<klammer), let hilfe = schatz.aufrufhilfe(fuer: name, aktiv: 0) else {
            return
        }
        aufrufStelle = klammer
        aufrufName = name
        sci(SCI_CALLTIPSHOW, anfang, hilfe.text)
        if let h = hilfe.hervorheben { sci(SCI_CALLTIPSETHLT, h.lowerBound, h.upperBound) }
    }

    /// Der wievielte Parameter: Trenner seit der Klammer, ohne die in inneren Klammern.
    private func aktualisiereAufrufhilfe(_ schatz: Wortschatz) {
        guard let stelle = aufrufStelle, sci(SCI_CALLTIPACTIVE) != 0,
            let zwischen = text((stelle + 1)..<sci(SCI_GETCURRENTPOS))
        else { aufrufStelle = nil; return }
        var tiefe = 0
        var nummer = 0
        for z in zwischen {
            if z == schatz.aufrufAnfang { tiefe += 1 } else if z == schatz.aufrufEnde { tiefe -= 1 } else if z == schatz.trenner, tiefe == 0 { nummer += 1 }
        }
        guard let hilfe = schatz.aufrufhilfe(fuer: aufrufName, aktiv: nummer) else { return }
        if let h = hilfe.hervorheben {
            sci(SCI_CALLTIPSETHLT, h.lowerBound, h.upperBound)
        } else {
            sci(SCI_CALLTIPSETHLT, 0, 0)
        }
    }

    /// Für die Selbstprüfung: der Stil an einer Stelle.
    func stil(bei stelle: Int) -> Int { sci(SCI_GETSTYLEAT, stelle) }

    /// Für die Selbstprüfung: was die Liste der Vorschläge gerade zeigt.
    var vorschlagOffen: Bool { sci(SCI_AUTOCACTIVE) != 0 }
    var aufrufhilfeOffen: Bool { sci(SCI_CALLTIPACTIVE) != 0 }

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
    /// Den Block an der Marke ein- oder ausklappen.
    func klappeAktuellen(ein: Bool) {
        var zeile = sci(SCI_LINEFROMPOSITION, sci(SCI_GETCURRENTPOS))
        if sci(SCI_GETFOLDLEVEL, zeile) & Int(SC_FOLDLEVELHEADERFLAG) == 0 { zeile = sci(SCI_GETFOLDPARENT, zeile) }
        guard zeile >= 0 else { return }
        sci(SCI_FOLDLINE, zeile, Int(ein ? SC_FOLDACTION_CONTRACT : SC_FOLDACTION_EXPAND))
    }

    /// Alle Blöcke einer Ebene (1 = äusserste) ein- oder ausklappen.
    func klappeEbene(_ ebene: Int, ein: Bool) {
        sci(SCI_COLOURISE, 0, -1)
        let ziel = Int(SC_FOLDLEVELBASE) + ebene - 1
        for z in 0..<sci(SCI_GETLINECOUNT) {
            let stufe = sci(SCI_GETFOLDLEVEL, z)
            if stufe & Int(SC_FOLDLEVELHEADERFLAG) != 0, stufe & Int(SC_FOLDLEVELNUMBERMASK) == ziel {
                sci(SCI_FOLDLINE, z, Int(ein ? SC_FOLDACTION_CONTRACT : SC_FOLDACTION_EXPAND))
            }
        }
    }

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
            if meldung.pointee.modificationType & Int32(SC_MOD_INSERTTEXT | SC_MOD_DELETETEXT) != 0 {
                textwoerter = nil
                aenderungszahl += 1
            }
            meldeZustand()
        case SCN_UPDATEUI:
            markiereKlammern()
            if meldung.pointee.updated & Int32(SC_UPDATE_SELECTION | SC_UPDATE_V_SCROLL) != 0 {
                hebeAuswahlHervor()
            }
            if Einstellungen.zeilennummernDynamisch, meldung.pointee.updated & Int32(SC_UPDATE_V_SCROLL) != 0 {
                passeZeilennummernAn()
            }
            meldeZustand()
        case SCN_MARGINCLICK where Int(meldung.pointee.margin) == Self.randLesezeichen:
            schalteLesezeichen(zeile: sci(SCI_LINEFROMPOSITION, meldung.pointee.position))
        case SCN_MACRORECORD:
            makroSchritt?(UInt32(bitPattern: meldung.pointee.message), meldung.pointee.wParam, meldung.pointee.lParam)
        case SCN_FOCUSIN:
            fokussiert?()
        case SCN_CHARADDED:
            let zeichen = meldung.pointee.ch
            if (zeichen == 0x0A || zeichen == 0x0D), Einstellungen.autoEinzug { ruecke() }
            schliesseKlammer(zeichen)
            hilf(nach: zeichen)
        case SCN_ZOOM:
            zeilennummernStellen = 0
            passeZeilennummernAn()
        default:
            break
        }
    }
}

/// Scintilla erwartet Farben als 0xBBGGRR; Notepad++ schreibt sie als RRGGBB.
extension UInt8 {
    var isWortzeichen: Bool {
        (0x30...0x39).contains(self) || (0x41...0x5A).contains(self) || (0x61...0x7A).contains(self) || self == 0x5F
            || self >= 0x80
    }
}

func scintillaFarbe(_ rgb: Int) -> Int {
    ((rgb & 0xFF) << 16) | (rgb & 0xFF00) | ((rgb >> 16) & 0xFF)
}

/// ScintillaView mit eigenem Kontextmenü: Die Inhaltsansicht von Scintilla
/// fragt zuerst ihre ScintillaView (menuForEvent).
final class KladdeScintillaView: ScintillaView {
    var kontextmenue: (() -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        kontextmenue?() ?? super.menu(for: event)
    }
}
