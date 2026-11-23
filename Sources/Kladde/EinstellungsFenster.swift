import AppKit

/// Der Dialog «Optionen» (Einstellungen → Optionen …, ⌘,) wie in Notepad++:
/// Rahmen und alle 23 Seiten aus preference.rc, mit den deutschen Texten.
/// Was NoteMac++ einstellen kann, ist verdrahtet und gilt sofort; alles andere
/// steht ausgegraut da, wie nicht umgesetzte Befehle in den Menüs.
final class EinstellungsFenster: NSWindowController, NSWindowDelegate {
    static let gemeinsam = EinstellungsFenster()

    /// Wie ein Element mit einer Einstellung verbunden ist.
    enum Bindung {
        case haken(() -> Bool, (Bool) -> Void)
        case optionen([String], () -> Int, (Int) -> Void)
        case zahl(ClosedRange<Int>, () -> Int, (Int) -> Void)
        case text(() -> String, (String) -> Void)
        case regler(ClosedRange<Int>, () -> Int, (Int) -> Void, anzeige: String?)
        case auswahl([String], () -> Int, (Int) -> Void)
        case liste([String], () -> Int)
        case knopf(() -> Void)
    }

    private let rahmen = WinFormular()
    private var seiten: [Oberflaeche.Dialog] = []
    private var formulare: [Int: WinFormular] = [:]
    private var flaechen: [Int: WinFlaeche] = [:]
    private var gewaehlt = 0
    private var seitenRechteck = NSRect.zero

    private init() {
        let d = Oberflaeche.gemeinsam.dialoge?["optionen"]
        let breite = CGFloat(d?.groesse[0] ?? 580) * WinFormular.sx + 4
        let hoehe = CGFloat(d?.groesse[1] ?? 235) * WinFormular.sy + 4
        let fenster = NSPanel(contentRect: NSRect(x: 0, y: 0, width: breite, height: hoehe), styleMask: [.titled, .closable],
                              backing: .buffered, defer: true)
        fenster.title = d?.titel ?? "Optionen"
        fenster.isRestorable = false
        fenster.isReleasedWhenClosed = false
        super.init(window: fenster)
        fenster.delegate = self
        let flaeche = WinFlaeche(frame: NSRect(x: 0, y: 0, width: breite, height: hoehe))
        fenster.contentView = flaeche
        rahmen.baue(d?.elemente ?? [], in: flaeche)
        seiten = (Oberflaeche.gemeinsam.optionen ?? []).filter { !$0.elemente.isEmpty }
        // Die Seiten liegen im Rahmen bei (115, 10) Dialogeinheiten, wie die Unterdialoge in preference.rc.
        seitenRechteck = NSRect(x: 115 * WinFormular.sx, y: 10 * WinFormular.sy,
                                width: 460 * WinFormular.sx, height: 205 * WinFormular.sy)
        let liste = rahmen.liste("IDC_LIST_DLGTITLE")
        liste?.eintraege = seiten.map { Mac.text($0.titel) }
        rahmen.gedrueckt = { [weak self] id in
            guard let self else { return }
            if id == "IDC_BUTTON_CLOSE" { self.close() }
            if id == "IDC_LIST_DLGTITLE", let i = liste?.gewaehlt { self.zeigeSeite(i) }
        }
        (rahmen.elemente["IDC_BUTTON_CLOSE"] as? NSButton)?.keyEquivalent = "\u{1b}"
        zeigeSeite(UserDefaults.standard.integer(forKey: "OptionenSeite"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func zeige() {
        window?.backgroundColor = Win.grund
        // Werte können sich ausserhalb geändert haben (Menü, Rechtsklick auf die Symbolleiste).
        for (i, f) in formulare { lies(f, seite: seiten[i]) }
        zeigeSeite(gewaehlt)
        window?.contentView?.needsDisplay = true
        if window?.isVisible != true, let haupt = Hauptfenster.gemeinsam.window, let f = window?.frame {
            window?.setFrameOrigin(NSPoint(x: haupt.frame.midX - f.width / 2, y: haupt.frame.midY - f.height / 2 + 40))
        }
        showWindow(nil)
    }

    /// Die Seite mit diesem Index zeigen (in der Reihenfolge von Notepad++).
    func zeigeSeite(_ i: Int) {
        let i = seiten.indices.contains(i) ? i : 0
        gewaehlt = i
        rahmen.liste("IDC_LIST_DLGTITLE")?.gewaehlt = i
        UserDefaults.standard.set(i, forKey: "OptionenSeite")
        for (j, f) in flaechen { f.isHidden = j != i }
        if flaechen[i] == nil { baueSeite(i) }
        flaechen[i]?.isHidden = false
        flaechen[i]?.needsDisplay = true
    }

    /// Die Seite «Dateireiter» usw. nach ihrer Kennung aus german.xml.
    func zeigeSeite(kennung: String) {
        if let i = seiten.firstIndex(where: { $0.kennung == kennung }) { zeigeSeite(i) }
    }

    var seitenKennungen: [String] { seiten.map { $0.kennung ?? "" } }

    /// Das Formular einer Seite (für die Selbstprüfung), bei Bedarf gebaut.
    func formular(_ kennung: String) -> WinFormular? {
        guard let i = seiten.firstIndex(where: { $0.kennung == kennung }) else { return nil }
        if formulare[i] == nil { baueSeite(i); flaechen[i]?.isHidden = i != gewaehlt }
        return formulare[i]
    }

    private func baueSeite(_ i: Int) {
        let seite = seiten[i]
        let flaeche = WinFlaeche(frame: seitenRechteck)
        window?.contentView?.addSubview(flaeche)
        let f = WinFormular()
        f.baue(seite.elemente, in: flaeche)
        f.gedrueckt = { [weak self, weak f] id in
            guard let self, let f else { return }
            self.uebernimm(id, aus: f, bindung: Self.bindungen[id])
            // Abhängige Elemente neu freigeben, auf allen gebauten Seiten.
            for (j, g) in self.formulare { self.schalteFrei(g, seite: self.seiten[j]) }
        }
        for (id, tipp) in Self.tipps { f.elemente[id]?.toolTip = tipp }
        formulare[i] = f
        flaechen[i] = flaeche
        lies(f, seite: seite)
    }

    // MARK: Werte lesen und schreiben

    private func lies(_ f: WinFormular, seite: Oberflaeche.Dialog) {
        for e in seite.elemente {
            guard let bindung = Self.bindungen[e.id] else { continue }
            switch bindung {
            case let .haken(get, _): f.setzeHaken(e.id, get())
            case let .optionen(ids, get, _): f.setzeHaken(e.id, ids.firstIndex(of: e.id) == get())
            case let .zahl(_, get, _): if f.text(e.id) != "\(get())" { f.setzeText(e.id, "\(get())") }
            case let .text(get, _): if f.text(e.id) != get() { f.setzeText(e.id, get()) }
            case let .regler(bereich, get, _, anzeige):
                f.regler(e.id)?.bereich = Double(bereich.lowerBound)...Double(bereich.upperBound)
                f.regler(e.id)?.wert = Double(get())
                if let anzeige { f.setzeText(anzeige, "\(get())") }
            case let .auswahl(werte, get, _):
                f.auswahl(e.id)?.eintraege = werte
                f.auswahl(e.id)?.gewaehlt = get()
            case let .liste(werte, get):
                f.liste(e.id)?.eintraege = werte
                f.liste(e.id)?.gewaehlt = get()
            case .knopf: break
            }
        }
        schalteFrei(f, seite: seite)
    }

    private func uebernimm(_ id: String, aus f: WinFormular, bindung: Bindung?) {
        guard let bindung else { return }
        switch bindung {
        case let .haken(_, set): set(f.haken(id))
        case let .optionen(ids, _, set):
            if let n = ids.firstIndex(of: id) {
                for o in ids { f.setzeHaken(o, o == id) }
                set(n)
            }
        case let .zahl(bereich, _, set): if let n = f.zahl(id), bereich.contains(n) { set(n) }
        case let .text(_, set): set(f.text(id))
        case let .regler(_, _, set, anzeige):
            let n = Int((f.regler(id)?.wert ?? 0).rounded())
            set(n)
            if let anzeige { f.setzeText(anzeige, "\(n)") }
        case let .auswahl(_, _, set): set(f.auswahl(id)?.gewaehlt ?? 0)
        case .liste: break
        case let .knopf(tun): tun()
        }
    }

    /// Verdrahtete Elemente sind frei (sofern ihre Bedingung gilt), andere bedienbare ausgegraut.
    private func schalteFrei(_ f: WinFormular, seite: Oberflaeche.Dialog) {
        for e in seite.elemente where !["GROUPBOX", "LTEXT", "RTEXT", "CTEXT"].contains(e.art) {
            var an = Self.bindungen[e.id] != nil && !Self.immerAus.contains(e.id)
            if an, let bedingung = Self.aktivWenn[e.id] { an = bedingung() }
            if f.istAktiv(e.id) != an { f.aktiv(e.id, an) }
        }
        // Beschriftungen ausgegrauter Elemente ebenfalls grau, wie unter Windows.
        for (text, feld) in Self.beschriftungen {
            guard let t = f.elemente[text] as? WinText, f.elemente[feld] != nil else { continue }
            t.textColor = f.istAktiv(feld) ? Win.text : Win.textAus
            t.needsDisplay = true
        }
    }

    // MARK: Was verdrahtet ist

    private static func radios(_ ids: [String], _ get: @escaping () -> Int, _ set: @escaping (Int) -> Void) -> [String: Bindung] {
        Dictionary(uniqueKeysWithValues: ids.map { ($0, Bindung.optionen(ids, get, set)) })
    }

    private static let sprachenListe: [Sprache] = Sprachdaten.gemeinsam.sprachen.filter { !$0.istNormalerText }

    static let bindungen: [String: Bindung] = {
        let e = Einstellungen.self
        var b: [String: Bindung] = [:]
        func h(_ id: String, _ get: @escaping () -> Bool, _ set: @escaping (Bool) -> Void) { b[id] = .haken(get, set) }
        // Allgemein
        b["IDC_COMBO_LOCALIZATION"] = .auswahl(["Deutsch"], { 0 }, { _ in })
        b["IDC_COMBO_DIALOG_FONT_SIZE"] = .auswahl(["8"], { 0 }, { _ in })
        b["IDC_COMBO_DIALOG_FONT_NAME"] = .auswahl(["MS Shell Dlg"], { 0 }, { _ in })
        h("IDC_CHECK_HIDESTATUSBAR", { e.statusleisteAusblenden }, { e.statusleisteAusblenden = $0 })
        // Symbolleiste
        h("IDC_CHECK_HIDE", { e.symbolleisteAusblenden }, { e.symbolleisteAusblenden = $0 })
        let saetze = ["fluent", "fluentGross", "fluentGefuellt", "fluentGefuelltGross", "standard"]
        b.merge(radios(["IDC_RADIO_SMALLICON", "IDC_RADIO_BIGICON", "IDC_RADIO_SMALLICON2", "IDC_RADIO_BIGICON2", "IDC_RADIO_STANDARD"],
                       { saetze.firstIndex(of: e.symbolsatz) ?? 4 }, { e.symbolsatz = saetze[$0] })) { $1 }
        // Dateireiter
        h("IDC_CHECK_TAB_HIDE", { e.tabsAusblenden }, { e.tabsAusblenden = $0 })
        h("IDC_CHECK_LOCK", { e.tabsSperren }, { e.tabsSperren = $0 })
        h("IDC_CHECK_DBCLICK2CLOSE", { e.tabDoppelklickSchliesst }, { e.tabDoppelklickSchliesst = $0 })
        h("IDC_CHECK_TAB_LAST_EXIT", { e.letzterTabBeendet }, { e.letzterTabBeendet = $0 })
        b["IDC_EDIT_TABCOMPACTLABELLEN"] = .zahl(0...200, { e.tabNameMax }, { e.tabNameMax = $0 })
        h("IDC_CHECK_REDUCE", { e.tabsVerkleinert }, { e.tabsVerkleinert = $0 })
        h("IDC_CHECK_TAB_ALTICONS", { e.tabAlternativeSymbole }, { e.tabAlternativeSymbole = $0 })
        h("IDC_CHECK_DRAWINACTIVE", { e.tabInaktivFarbe }, { e.tabInaktivFarbe = $0 })
        h("IDC_CHECK_ORANGE", { e.tabBalken }, { e.tabBalken = $0 })
        h("IDC_CHECK_ENABLETABCLOSE", { e.tabSchliessen }, { e.tabSchliessen = $0 })
        h("IDC_CHECK_ENABLETABPIN", { e.tabPin }, { e.tabPin = $0 })
        h("IDC_CHECK_SHOWONLYPINNEDBUTTON", { e.tabNurAngeheftete }, { e.tabNurAngeheftete = $0 })
        h("IDC_CHECK_INACTTABDRAWBUTTON", { e.tabKnoepfeInaktiv }, { e.tabKnoepfeInaktiv = $0 })
        // Bearbeiten 1
        b.merge(radios(["IDC_RADIO_CLM_NONE", "IDC_RADIO_CLM_HILITE", "IDC_RADIO_CLM_FRAME"],
                       { e.aktuelleZeile }, { e.aktuelleZeile = $0 })) { $1 }
        b["IDC_CARETLINEFRAME_WIDTH_SLIDER"] = .regler(1...6, { e.aktuelleZeileRahmen }, { e.aktuelleZeileRahmen = $0 },
                                                       anzeige: "IDC_CARETLINEFRAME_WIDTH_DISPLAY")
        b["IDC_WIDTH_COMBO"] = .auswahl(["0", "1", "2", "3", "Block"], { e.cursorBreite }, { e.cursorBreite = $0 })
        b["IDC_CARETBLINKRATE_SLIDER"] = .regler(50...2500, { e.cursorBlinken }, { e.cursorBlinken = $0 }, anzeige: nil)
        b.merge(radios(["IDC_RADIO_LWDEF", "IDC_RADIO_LWALIGN", "IDC_RADIO_LWINDENT"], { e.umbruchArt }, { e.umbruchArt = $0 })) { $1 }
        h("IDC_CHECK_VIRTUALSPACE", { e.virtuellerRaum }, { e.virtuellerRaum = $0 })
        h("IDC_CHECK_LINECUTCOPYWITHOUTSELECTION", { e.zeileOhneAuswahl }, { e.zeileOhneAuswahl = $0 })
        h("IDC_CHECK_SCROLLBEYONDLASTLINE", { e.ueberLetzteZeile }, { e.ueberLetzteZeile = $0 })
        // Bearbeiten 2
        h("IDC_CHECK_MULTISELECTION", { e.mehrfachBearbeitung }, { e.mehrfachBearbeitung = $0 })
        // Dunkler Modus
        b.merge(radios(["IDC_RADIO_DARKMODE_LIGHTMODE", "IDC_RADIO_DARKMODE_DARKMODE", "IDC_RADIO_DARKMODE_FOLLOWWINDOWS"],
                       { e.modus }, { e.modus = $0 })) { $1 }
        // Ränder/Rahmen/Umrandung
        b.merge(radios(["IDC_RADIO_SIMPLE", "IDC_RADIO_ARROW", "IDC_RADIO_CIRCLE", "IDC_RADIO_BOX", "IDC_RADIO_FOLDMARGENONE"],
                       { e.faltStil }, { e.faltStil = $0 })) { $1 }
        b["IDC_COLUMNPOS_EDIT"] = .text({ e.kanten }, { e.kanten = $0 })
        h("IDC_CHECK_EDGEBGMODE", { e.kanteHintergrund }, { e.kanteHintergrund = $0 })
        h("IDC_CHECK_CHANGHISTORYMARGIN", { e.aenderungenAmRand }, { e.aenderungenAmRand = $0 })
        h("IDC_CHECK_CHANGHISTORYINDICATOR", { e.aenderungenImText }, { e.aenderungenImText = $0 })
        h("IDC_CHECK_LINENUMBERMARGE", { e.zeilennummern }, { e.zeilennummern = $0 })
        b.merge(radios(["IDC_RADIO_DYNAMIC", "IDC_RADIO_CONSTANT"], { e.zeilennummernDynamisch ? 0 : 1 },
                       { e.zeilennummernDynamisch = $0 == 0 })) { $1 }
        b["IDC_PADDINGLEFT_SLIDER"] = .regler(0...9, { e.randLinks }, { e.randLinks = $0 }, anzeige: "IDC_PADDINGLEFTVAL_STATIC")
        b["IDC_PADDINGRIGHT_SLIDER"] = .regler(0...9, { e.randRechts }, { e.randRechts = $0 }, anzeige: "IDC_PADDINGRIGHTVAL_STATIC")
        h("IDC_CHECK_BOOKMARKMARGE", { e.lesezeichenRand }, { e.lesezeichenRand = $0 })
        // Neues Dokument
        b.merge(radios(["IDC_RADIO_F_WIN", "IDC_RADIO_F_UNIX", "IDC_RADIO_F_MAC"], { e.neuZeilenende }, { e.neuZeilenende = $0 })) { $1 }
        b.merge(radios(["IDC_RADIO_ANSI", "IDC_RADIO_UTF8_NO_BOM", "IDC_RADIO_UTF8", "IDC_RADIO_UTF16BIG", "IDC_RADIO_UTF16SMALL"],
                       { e.neuKodierung }, { e.neuKodierung = $0 })) { $1 }
        let namen = [""] + sprachenListe.map(\.name)
        b["IDC_COMBO_DEFAULTLANG"] = .auswahl(["Normaler Text"] + sprachenListe.map(\.lang),
                                              { namen.firstIndex(of: e.neuSprache) ?? 0 }, { e.neuSprache = namen[$0] })
        // Sprache: nur zur Ansicht (NoteMac++ ordnet das Sprachmenü immer nach Buchstaben)
        b["IDC_LIST_ENABLEDLANG"] = .liste(sprachenListe.map(\.lang), { 0 })
        b["IDC_LIST_DISABLEDLANG"] = .liste([], { 0 })
        // Einrückungen
        b["IDC_LIST_TABSETTNG"] = .liste(["[Standard]"] + sprachenListe.map(\.lang), { 0 })
        b["IDC_EDIT_TABSIZEVAL"] = .zahl(1...16, { e.tabbreite }, { e.tabbreite = $0 })
        b.merge(radios(["IDC_RADIO_USINGTAB", "IDC_RADIO_REPLACEBYSPACE"], { e.tabsAlsLeerzeichen ? 1 : 0 },
                       { e.tabsAlsLeerzeichen = $0 == 1 })) { $1 }
        h("IDC_CHECK_BACKSPACEUNINDENT", { e.rueckLoeschtEinzug }, { e.rueckLoeschtEinzug = $0 })
        b.merge(radios(["IDC_RADIO_AUTOINDENT_NONE", "IDC_RADIO_AUTOINDENT_BASIC", "IDC_RADIO_AUTOINDENT_ADVANCED"],
                       { e.autoEinzugArt }, { e.autoEinzugArt = $0 })) { $1 }
        // Hervorhebung
        h("IDC_CHECK_ENABLSMARTHILITE", { e.smartHighlighting }, { e.smartHighlighting = $0 })
        h("IDC_CHECK_SMARTHILITECASESENSITIVE", { e.smartGrossKlein }, { e.smartGrossKlein = $0 })
        h("IDC_CHECK_SMARTHILITEWHOLEWORDONLY", { e.smartGanzesWort }, { e.smartGanzesWort = $0 })
        // Suche
        h("IDC_CHECK_FILL_FIND_FIELD_WITH_SELECTED", { e.suchfeldAusAuswahl }, { e.suchfeldAusAuswahl = $0 })
        h("IDC_CHECK_MONOSPACEDFONT_FINDDLG", { e.suchenFestbreite }, { e.suchenFestbreite = $0 })
        // Sicherheitskopien
        h("IDC_CHECK_REMEMBERSESSION", { e.sitzungMerken }, { e.sitzungMerken = $0 })
        h("IDC_BACKUPDIR_RESTORESESSION_CHECK", { e.zwischensicherung }, { e.zwischensicherung = $0 })
        b["IDC_BACKUPDIR_RESTORESESSION_EDIT"] = .zahl(1...3600, { e.zwischensicherungSekunden }, { e.zwischensicherungSekunden = $0 })
        b["IDD_BACKUPDIR_RESTORESESSION_PATH_EDIT"] = .text({ (Sitzung.ordner.path as NSString).abbreviatingWithTildeInPath }, { _ in })
        // Autovervollständigung
        h("IDD_AUTOC_ENABLECHECK", { e.vervollstaendigenAn }, { e.vervollstaendigenAn = $0 })
        b.merge(radios(["IDD_AUTOC_FUNCRADIO", "IDD_AUTOC_WORDRADIO", "IDD_AUTOC_BOTHRADIO"],
                       { e.vervollstaendigenArt }, { e.vervollstaendigenArt = $0 })) { $1 }
        b["IDC_AUTOC_CHAR_SLIDER"] = .regler(1...9, { max(1, e.vervollstaendigenAb) }, { e.vervollstaendigenAb = $0 },
                                             anzeige: "IDD_AUTOC_STATIC_N")
        h("IDD_FUNC_CHECK", { e.aufrufhilfeAn }, { e.aufrufhilfeAn = $0 })
        for (id, z) in [("IDD_AUTOCPARENTHESES_CHECK", "("), ("IDD_AUTOCBRACKET_CHECK", "["), ("IDD_AUTOCCURLYBRACKET_CHECK", "{"),
                        ("IDD_AUTOC_DOUBLEQUOTESCHECK", "\""), ("IDD_AUTOC_QUOTESCHECK", "'")] {
            let zeichen = Character(z)
            h(id, { e.schliesst(zeichen) }, { e.setzeSchliesst(zeichen, $0) })
        }
        // Diverses
        h("IDC_CHECK_SHORTTITLE", { e.kurzerTitel }, { e.kurzerTitel = $0 })
        return b
    }()

    /// Mit Wert, aber nicht änderbar (NoteMac++ kennt nur das eine).
    static let immerAus: Set<String> = [
        "IDC_COMBO_LOCALIZATION", "IDC_COMBO_DIALOG_FONT_SIZE", "IDC_COMBO_DIALOG_FONT_NAME", "IDC_LIST_ENABLEDLANG",
        "IDC_LIST_DISABLEDLANG", "IDC_LIST_TABSETTNG", "IDD_BACKUPDIR_RESTORESESSION_PATH_EDIT",
    ]

    /// Abhängigkeiten wie in Notepad++: was nur mit einer anderen Option Sinn ergibt.
    static let aktivWenn: [String: () -> Bool] = {
        let e = Einstellungen.self
        return [
            "IDC_CHECK_SHOWONLYPINNEDBUTTON": { e.tabPin },
            "IDC_CHECK_INACTTABDRAWBUTTON": { e.tabPin || e.tabSchliessen },
            "IDC_CARETLINEFRAME_WIDTH_SLIDER": { e.aktuelleZeile == 2 },
            "IDC_RADIO_DYNAMIC": { e.zeilennummern },
            "IDC_RADIO_CONSTANT": { e.zeilennummern },
            "IDC_CHECK_EDGEBGMODE": { Einstellungen.kanten.split(whereSeparator: { !$0.isNumber }).count == 1 },
            "IDC_CHECK_SMARTHILITECASESENSITIVE": { e.smartHighlighting },
            "IDC_CHECK_SMARTHILITEWHOLEWORDONLY": { e.smartHighlighting },
            "IDC_BACKUPDIR_RESTORESESSION_CHECK": { e.sitzungMerken },
            "IDC_BACKUPDIR_RESTORESESSION_EDIT": { e.sitzungMerken && e.zwischensicherung },
            "IDD_AUTOC_FUNCRADIO": { e.vervollstaendigenAn },
            "IDD_AUTOC_WORDRADIO": { e.vervollstaendigenAn },
            "IDD_AUTOC_BOTHRADIO": { e.vervollstaendigenAn },
            "IDC_AUTOC_CHAR_SLIDER": { e.vervollstaendigenAn },
        ]
    }()

    /// Beschriftung → Feld: Die Beschriftung wird grau, wenn das Feld es ist.
    static let beschriftungen: [(String, String)] = [
        ("IDC_CARETLINEFRAME_WIDTH_STATIC", "IDC_CARETLINEFRAME_WIDTH_SLIDER"),
        ("IDC_CARETLINEFRAME_WIDTH_DISPLAY", "IDC_CARETLINEFRAME_WIDTH_SLIDER"),
        ("IDC_TABCOMPACTLABELLEN_STATIC", "IDC_EDIT_TABCOMPACTLABELLEN"), ("IDC_DEFAULTLANG_STATIC", "IDC_COMBO_DEFAULTLANG"),
        ("IDD_BACKUPDIR_RESTORESESSION_STATIC1", "IDC_BACKUPDIR_RESTORESESSION_EDIT"),
        ("IDD_BACKUPDIR_RESTORESESSION_STATIC2", "IDC_BACKUPDIR_RESTORESESSION_EDIT"),
        ("IDD_AUTOC_STATIC_FROM", "IDC_AUTOC_CHAR_SLIDER"), ("IDD_AUTOC_STATIC_N", "IDC_AUTOC_CHAR_SLIDER"),
        ("IDD_AUTOC_STATIC_CHAR", "IDC_AUTOC_CHAR_SLIDER"), ("IDD_AUTOC_SLIDER_MIN_STATIC", "IDC_AUTOC_CHAR_SLIDER"),
        ("IDD_AUTOC_SLIDER_MAX_STATIC", "IDC_AUTOC_CHAR_SLIDER"),
        ("IDC_BORDERWIDTHVAL_STATIC", "IDC_BORDERWIDTH_SLIDER"), ("IDC_DISTRACTIONFREE_STATIC", "IDC_DISTRACTIONFREE_SLIDER"),
        ("IDC_DISTRACTIONFREEVAL_STATIC", "IDC_DISTRACTIONFREE_SLIDER"),
        ("IDC_WIDTH_STATIC", "IDC_WIDTH_COMBO"), ("IDC_BLINKRATE_STATIC", "IDC_CARETBLINKRATE_SLIDER"),
        ("IDC_CARETBLINKRATE_S_STATIC", "IDC_CARETBLINKRATE_SLIDER"), ("IDC_CARETBLINKRATE_F_STATIC", "IDC_CARETBLINKRATE_SLIDER"),
        ("IDC_TABSIZE_STATIC", "IDC_EDIT_TABSIZEVAL"), ("IDC_INSELECTION_THRESHOLD_STATIC", "IDC_INSELECTION_THRESHOLD_EDIT"),
        ("IDC_FILLFINDWHAT_THRESHOLD_STATIC", "IDC_FILLFINDWHAT_THRESHOLD_EDIT"), ("IDD_BACKUPDIR_STATIC", "IDC_BACKUPDIR_EDIT"),
        ("IDC_SESSIONFILEEXT_STATIC", "IDC_EDIT_SESSIONFILEEXT"), ("IDC_WORKSPACEFILEEXT_STATIC", "IDC_EDIT_WORKSPACEFILEEXT"),
        ("IDC_SYSTRAY_STATIC", "IDC_COMBO_SYSTRAY_ACTION_CHOICE"), ("IDC_SC_TECHNOLOGY_STATIC", "IDC_COMBO_SC_TECHNOLOGY_CHOICE"),
        ("IDC_AUTOUPDATE_STATIC", "IDC_COMBO_AUTOUPDATE"),
    ]

    /// Die «(?)» von Notepad++ als Tooltip.
    static let tipps: [String: String] = [
        "IDC_TABCOMPACTLABELLEN_TIP_STATIC": "Längere Namen werden nach so vielen Zeichen mit «…» gekürzt. 0 zeigt den ganzen Namen.",
        "IDC_BUTTON_VES_TIP": "Spalten für senkrechte Linien, durch Leerzeichen getrennt, etwa «80 120». Mit genau einer Spalte und «Hintergrundmodus» wird der Text dahinter eingefärbt.",
        "IDD_ACCENT_TIP_STATIC": "Die Einfärbung der Symbole kennt NoteMac++ nicht.",
        "IDC_INSELECTION_THRESH_QUESTION_BUTTON": "NoteMac++ setzt «In Auswahl» nicht selbst.",
        "IDC_FILLFINDWHAT_THRESH_QUESTION_BUTTON": "NoteMac++ setzt eine Auswahl bis 200 Zeichen ein.",
    ]
}
