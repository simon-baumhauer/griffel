import AppKit
import CryptoKit
import ScintillaBruecke

/// Die Befehle von Notepad++ (IDM_…) und was Kladde für sie tut. Menüs,
/// Werkzeugleiste und Kontextmenüs rufen alle hierher. Was hier fehlt, steht
/// im Menü ausgegraut.
extension Hauptfenster: NSMenuItemValidation {
    /// Befehle, die Kladde ausführen kann.
    static let befehle: Set<String> = {
        var s: Set<String> = [
            // Datei
            "FILE_NEW", "FILE_OPEN", "FILE_OPEN_FOLDER", "FILE_OPEN_CMD", "FILE_CONTAININGFOLDERASWORKSPACE",
            "FILE_OPEN_DEFAULT_VIEWER", "FILE_OPENFOLDERASWORKSPACE", "FILE_RELOAD", "FILE_SAVE", "FILE_SAVEAS",
            "FILE_SAVECOPYAS", "FILE_SAVEALL", "FILE_RENAME", "FILE_CLOSE", "FILE_CLOSEALL",
            "FILE_CLOSEALL_BUT_CURRENT", "FILE_CLOSEALL_BUT_PINNED", "FILE_CLOSEALL_TOLEFT", "FILE_CLOSEALL_TORIGHT",
            "FILE_CLOSEALL_UNCHANGED", "FILE_DELETE", "FILE_LOADSESSION", "FILE_SAVESESSION", "FILE_PRINT",
            "FILE_PRINTNOW", "FILE_EXIT",
            // Bearbeiten
            "EDIT_UNDO", "EDIT_REDO", "EDIT_CUT", "EDIT_COPY", "EDIT_PASTE", "EDIT_DELETE", "EDIT_SELECTALL",
            "EDIT_BEGINENDSELECT", "EDIT_BEGINENDSELECT_COLUMNMODE", "EDIT_INSERT_DATETIME_SHORT",
            "EDIT_INSERT_DATETIME_LONG", "EDIT_INSERT_DATETIME_CUSTOMIZED", "EDIT_FULLPATHTOCLIP",
            "EDIT_FILENAMETOCLIP", "EDIT_CURRENTDIRTOCLIP", "EDIT_COPY_ALL_NAMES", "EDIT_COPY_ALL_PATHS",
            "EDIT_INS_TAB", "EDIT_RMV_TAB", "EDIT_UPPERCASE", "EDIT_LOWERCASE", "EDIT_PROPERCASE_FORCE",
            "EDIT_PROPERCASE_BLEND", "EDIT_SENTENCECASE_FORCE", "EDIT_SENTENCECASE_BLEND", "EDIT_INVERTCASE",
            "EDIT_RANDOMCASE", "EDIT_DUP_LINE", "EDIT_REMOVE_ANY_DUP_LINES", "EDIT_REMOVE_CONSECUTIVE_DUP_LINES",
            "EDIT_SPLIT_LINES", "EDIT_JOIN_LINES", "EDIT_LINE_UP", "EDIT_LINE_DOWN", "EDIT_REMOVEEMPTYLINES",
            "EDIT_REMOVEEMPTYLINESWITHBLANK", "EDIT_BLANKLINEABOVECURRENT", "EDIT_BLANKLINEBELOWCURRENT",
            "EDIT_BLOCK_COMMENT", "EDIT_BLOCK_COMMENT_SET", "EDIT_BLOCK_UNCOMMENT", "EDIT_STREAM_COMMENT",
            "EDIT_STREAM_UNCOMMENT", "EDIT_AUTOCOMPLETE", "EDIT_AUTOCOMPLETE_CURRENTFILE", "EDIT_FUNCCALLTIP",
            "FORMAT_TODOS", "FORMAT_TOUNIX", "FORMAT_TOMAC", "EDIT_TRIMTRAILING", "EDIT_TRIMLINEHEAD",
            "EDIT_TRIM_BOTH", "EDIT_EOL2WS", "EDIT_TRIMALL", "EDIT_TAB2SW", "EDIT_SW2TAB_ALL",
            "EDIT_SW2TAB_LEADING", "EDIT_OPENSELECTEDFILETOEDIT", "EDIT_OPENSELECTEDFILEFOLDERINEXPLORER",
            "EDIT_REDACT_SELECTION", "EDIT_SEARCHONINTERNET", "EDIT_MULTISELECTALL",
            "EDIT_MULTISELECTALLMATCHCASE", "EDIT_MULTISELECTALLWHOLEWORD", "EDIT_MULTISELECTALLMATCHCASEWHOLEWORD",
            "EDIT_MULTISELECTNEXT", "EDIT_MULTISELECTNEXTMATCHCASE", "EDIT_MULTISELECTNEXTWHOLEWORD",
            "EDIT_MULTISELECTNEXTMATCHCASEWHOLEWORD", "EDIT_MULTISELECTUNDO", "EDIT_MULTISELECTSSKIP",
            "EDIT_COLUMNMODETIP", "EDIT_COLUMNMODE", "EDIT_TOGGLEREADONLY", "EDIT_SETREADONLYFORALLDOCS",
            "EDIT_CLEARREADONLYFORALLDOCS",
            // Suchen
            "SEARCH_FIND", "SEARCH_FINDINFILES", "SEARCH_FINDNEXT", "SEARCH_FINDPREV", "SEARCH_SETANDFINDNEXT",
            "SEARCH_SETANDFINDPREV", "SEARCH_VOLATILE_FINDNEXT", "SEARCH_VOLATILE_FINDPREV", "SEARCH_REPLACE",
            "SEARCH_FINDINCREMENT", "FOCUS_ON_FOUND_RESULTS", "SEARCH_GOTONEXTFOUND", "SEARCH_GOTOPREVFOUND",
            "SEARCH_GOTOLINE", "SEARCH_GOTOMATCHINGBRACE", "SEARCH_SELECTMATCHINGBRACES", "SEARCH_MARK",
            "SEARCH_CLEARALLMARKS", "SEARCH_MARKEDTOCLIP", "SEARCH_TOGGLE_BOOKMARK", "SEARCH_NEXT_BOOKMARK",
            "SEARCH_PREV_BOOKMARK", "SEARCH_CLEAR_BOOKMARKS", "SEARCH_CUTMARKEDLINES", "SEARCH_COPYMARKEDLINES",
            "SEARCH_DELETEMARKEDLINES", "SEARCH_DELETEUNMARKEDLINES", "SEARCH_INVERSEMARKS",
            // Ansicht
            "VIEW_ALWAYSONTOP", "VIEW_FULLSCREENTOGGLE", "VIEW_POSTIT", "VIEW_DISTRACTIONFREE", "VIEW_IN_FIREFOX",
            "VIEW_IN_CHROME", "VIEW_IN_EDGE", "VIEW_TAB_SPACE", "VIEW_EOL", "VIEW_ALL_CHARACTERS",
            "VIEW_INDENT_GUIDE", "VIEW_WRAP_SYMBOL", "VIEW_ZOOMIN", "VIEW_ZOOMOUT", "VIEW_ZOOMRESTORE",
            "VIEW_CLONE_TO_ANOTHER_VIEW", "VIEW_TAB_START", "VIEW_TAB_END", "VIEW_TAB_NEXT", "VIEW_TAB_PREV",
            "VIEW_GOTO_START", "VIEW_GOTO_END", "VIEW_TAB_MOVEFORWARD", "VIEW_TAB_MOVEBACKWARD",
            "VIEW_TAB_COLOUR_NONE", "VIEW_WRAP", "VIEW_SWITCHTO_OTHER_VIEW", "VIEW_FOLDALL", "VIEW_UNFOLDALL",
            "VIEW_FOLD_CURRENT", "VIEW_UNFOLD_CURRENT", "VIEW_SUMMARY", "VIEW_FILEBROWSER", "VIEW_DOC_MAP",
            "VIEW_DOCLIST", "VIEW_FUNC_LIST", "VIEW_SYNSCROLLV", "VIEW_SYNSCROLLH", "VIEW_MONITORING",
            // Codierung
            "FORMAT_ANSI", "FORMAT_AS_UTF_8", "FORMAT_UTF_8", "FORMAT_UTF_16BE", "FORMAT_UTF_16LE", "FORMAT_WIN_1252",
            "FORMAT_CONV2_ANSI", "FORMAT_CONV2_AS_UTF_8", "FORMAT_CONV2_UTF_8", "FORMAT_CONV2_UTF_16BE",
            "FORMAT_CONV2_UTF_16LE",
            // Sprache, Einstellungen, Werkzeuge, Makros, Ausführen, ?
            "LANG_USER_DLG", "LANG_OPENUDLDIR", "LANG_UDLCOLLECTION_PROJECT_SITE", "SETTING_PREFERENCE",
            "LANGSTYLE_CONFIG_DLG", "MACRO_STARTRECORDINGMACRO", "MACRO_STOPRECORDINGMACRO",
            "MACRO_PLAYBACKRECORDEDMACRO", "MACRO_SAVECURRENTMACRO", "MACRO_RUNMULTIMACRODLG", "EXECUTE",
            "WINDOW_WINDOWS", "CMDLINEARGUMENTS", "HOMESWEETHOME", "PROJECTPAGE", "ONLINEDOCUMENT", "FORUM",
            "UPDATE_NPP", "DEBUGINFO", "ABOUT",
        ]
        for i in 1...9 { s.insert("VIEW_TAB\(i)") }
        for i in 1...5 {
            for v in ["SEARCH_MARKALLEXT", "SEARCH_MARKONEEXT", "SEARCH_UNMARKALLEXT", "SEARCH_GOPREVMARKER",
                "SEARCH_GONEXTMARKER", "SEARCH_STYLE", "VIEW_TAB_COLOUR_"]
            {
                s.insert(v == "SEARCH_STYLE" ? "SEARCH_STYLE\(i)TOCLIP" : "\(v)\(i)")
            }
        }
        for i in 1...8 { s.insert("VIEW_FOLD_\(i)"); s.insert("VIEW_UNFOLD_\(i)") }
        for v in ["SEARCH_GOPREVMARKER_DEF", "SEARCH_GONEXTMARKER_DEF", "SEARCH_ALLSTYLESTOCLIP"] { s.insert(v) }
        for art in ["MD5", "SHA1", "SHA256", "SHA512"] {
            for teil in ["GENERATE", "GENERATEFROMFILE", "GENERATEINTOCLIPBOARD"] { s.insert("TOOL_\(art)_\(teil)") }
        }
        for a in ["FN", "FP", "FT", "FS", "FD"] { s.insert("WINDOW_SORT_\(a)_ASC"); s.insert("WINDOW_SORT_\(a)_DSC") }
        return Set(s.map { "IDM_" + $0 })
    }()

    @objc func befehl(_ sender: Any?) {
        guard let id = (sender as? NSMenuItem)?.representedObject as? String else { return }
        fuehreAus(id)
    }

    // MARK: Zustand

    /// Ausführbar? Eingeschaltet (Haken, gedrückter Knopf)?
    func zustand(_ voll: String) -> (moeglich: Bool, an: Bool) {
        guard Self.befehle.contains(voll) else { return (false, false) }
        let id = String(voll.dropFirst(4))
        let e = aktiv
        let d = aktivesDokument
        switch id {
        case "EDIT_UNDO": return (e?.nachricht(SCI_CANUNDO) ?? 0 != 0, false)
        case "EDIT_REDO": return (e?.nachricht(SCI_CANREDO) ?? 0 != 0, false)
        case "EDIT_CUT", "EDIT_COPY", "EDIT_DELETE": return (!(e?.auswahl.isEmpty ?? true), false)
        case "FILE_SAVE": return (d?.isDocumentEdited ?? false || d?.fileURL == nil, false)
        case "FILE_SAVEALL": return (tabs.contains { $0.isDocumentEdited }, false)
        case "FILE_RELOAD", "FILE_OPEN_FOLDER", "FILE_OPEN_CMD", "FILE_CONTAININGFOLDERASWORKSPACE",
            "FILE_OPEN_DEFAULT_VIEWER", "FILE_DELETE", "EDIT_FULLPATHTOCLIP", "EDIT_CURRENTDIRTOCLIP", "VIEW_IN_FIREFOX",
            "VIEW_IN_CHROME", "VIEW_IN_EDGE", "VIEW_MONITORING":
            if id == "VIEW_MONITORING" { return (d?.fileURL != nil, d?.ueberwacht ?? false) }
            if id.hasPrefix("VIEW_IN_") { return (d?.fileURL != nil && Werkzeuge.browser(id) != nil, false) }
            return (d?.fileURL != nil, false)
        case "VIEW_WRAP": return (true, editor?.umbruch ?? false)
        case "VIEW_TAB_SPACE": return (true, Einstellungen.leerzeichenZeigen)
        case "VIEW_EOL": return (true, Einstellungen.zeilenendenZeigen)
        case "VIEW_ALL_CHARACTERS": return (true, Einstellungen.leerzeichenZeigen && Einstellungen.zeilenendenZeigen)
        case "VIEW_INDENT_GUIDE": return (true, Einstellungen.einrueckungshilfen)
        case "VIEW_WRAP_SYMBOL": return (true, Einstellungen.umbruchSymbol)
        case "VIEW_ALWAYSONTOP": return (true, window?.level == .floating)
        case "VIEW_FULLSCREENTOGGLE": return (true, window?.styleMask.contains(.fullScreen) ?? false)
        case "VIEW_POSTIT": return (true, postIt)
        case "VIEW_DISTRACTIONFREE": return (true, ablenkungsfrei)
        case "VIEW_FUNC_LIST": return (true, Einstellungen.funktionslisteSichtbar)
        case "VIEW_DOCLIST": return (true, Einstellungen.dokumentenlisteSichtbar)
        case "VIEW_DOC_MAP": return (true, Einstellungen.miniaturansichtSichtbar)
        case "VIEW_FILEBROWSER": return (true, Einstellungen.arbeitsbereichSichtbar)
        case "VIEW_CLONE_TO_ANOTHER_VIEW": return (true, geteilt)
        case "VIEW_SWITCHTO_OTHER_VIEW": return (geteilt, false)
        case "VIEW_SYNSCROLLV": return (geteilt, synchronVertikal)
        case "VIEW_SYNSCROLLH": return (geteilt, synchronHorizontal)
        case "EDIT_TOGGLEREADONLY": return (true, d?.schreibgeschuetzt ?? false)
        case "MACRO_STARTRECORDINGMACRO": return (!Makros.gemeinsam.nimmtAuf, false)
        case "MACRO_STOPRECORDINGMACRO": return (Makros.gemeinsam.nimmtAuf, false)
        case "MACRO_PLAYBACKRECORDEDMACRO", "MACRO_RUNMULTIMACRODLG", "MACRO_SAVECURRENTMACRO":
            return (!Makros.gemeinsam.nimmtAuf && !Makros.gemeinsam.aktuelles.isEmpty, false)
        case "SEARCH_FINDNEXT", "SEARCH_FINDPREV": return (!SuchZustand.gemeinsam.optionen.text.isEmpty, false)
        case "SEARCH_GOTONEXTFOUND", "SEARCH_GOTOPREVFOUND", "FOCUS_ON_FOUND_RESULTS":
            return (Suchergebnisse.gemeinsam.hatTreffer, false)
        case "EDIT_BEGINENDSELECT": return (true, beginnAuswahl != nil && !beginnSpalte)
        case "EDIT_BEGINENDSELECT_COLUMNMODE": return (true, beginnAuswahl != nil && beginnSpalte)
        default:
            if id.hasPrefix("FORMAT_") && !id.hasPrefix("FORMAT_CONV2") && !id.hasPrefix("FORMAT_TO") {
                return (true, d.map { Befehlsmenue.kodierung(id) == $0.datei.kodierung } ?? false)
            }
            if id.hasPrefix("FORMAT_TO") {
                let ende: Textdatei.Zeilenende = id == "FORMAT_TODOS" ? .crlf : id == "FORMAT_TOUNIX" ? .lf : .cr
                return (d?.datei.zeilenende != ende, false)
            }
            if id.hasPrefix("VIEW_TAB_COLOUR_") {
                return (true, id.hasSuffix("NONE") ? d?.tabFarbe == nil : d?.tabFarbe == Int(id.suffix(1)))
            }
            return (true, false)
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let id = menuItem.representedObject as? String else { return true }
        let z = zustand(id)
        menuItem.state = z.an ? .on : .off
        return z.moeglich
    }

    // MARK: Ausführen

    func fuehreAus(_ voll: String) {
        let id = voll.hasPrefix("IDM_") ? String(voll.dropFirst(4)) : voll
        let e = aktiv
        let d = aktivesDokument
        let dokumente = NSDocumentController.shared

        switch id {
        // Datei
        case "FILE_NEW": dokumente.newDocument(nil)
        case "FILE_OPEN": dokumente.openDocument(nil)
        case "FILE_OPEN_FOLDER": if let u = d?.fileURL { NSWorkspace.shared.activateFileViewerSelecting([u]) }
        case "FILE_OPEN_CMD": if let u = d?.fileURL { Werkzeuge.terminal(in: u.deletingLastPathComponent()) }
        case "FILE_CONTAININGFOLDERASWORKSPACE":
            if let u = d?.fileURL { Panels.gemeinsam.arbeitsbereichHinzu(u.deletingLastPathComponent()) }
        case "FILE_OPEN_DEFAULT_VIEWER": if let u = d?.fileURL { NSWorkspace.shared.open(u) }
        case "FILE_OPENFOLDERASWORKSPACE": Panels.gemeinsam.arbeitsbereichWaehlen()
        case "FILE_RELOAD": neuLaden(d)
        case "FILE_SAVE": d?.save(nil)
        case "FILE_SAVEAS": d?.saveAs(nil)
        case "FILE_SAVECOPYAS": d?.saveTo(nil)
        case "FILE_SAVEALL": for t in tabs where t.isDocumentEdited { t.save(nil) }
        case "FILE_RENAME": umbenennen(d)
        case "FILE_CLOSE": if let d { schliesse([d]) }
        case "FILE_CLOSEALL": schliesse(tabs)
        case "FILE_CLOSEALL_BUT_CURRENT": schliesse(tabs.filter { $0 !== d })
        case "FILE_CLOSEALL_BUT_PINNED": schliesse(tabs.filter { !$0.angeheftet })
        case "FILE_CLOSEALL_TOLEFT", "FILE_CLOSEALL_TORIGHT":
            guard let d, let i = tabs.firstIndex(where: { $0 === d }) else { return }
            schliesse(Array(id.hasSuffix("LEFT") ? tabs[..<i] : tabs[(i + 1)...]))
        case "FILE_CLOSEALL_UNCHANGED": schliesse(tabs.filter { !$0.isDocumentEdited })
        case "FILE_DELETE": inPapierkorb(d)
        case "FILE_LOADSESSION": Sitzung.ladeAusDatei()
        case "FILE_SAVESESSION": Sitzung.sichereInDatei()
        case "FILE_PRINT": if let e, let d { Werkzeuge.drucke(e, titel: d.tabTitel, mitDialog: true) }
        case "FILE_PRINTNOW": if let e, let d { Werkzeuge.drucke(e, titel: d.tabTitel, mitDialog: false) }
        case "FILE_EXIT": NSApp.terminate(nil)

        // Bearbeiten: die Standardbefehle an den Ersten Antwortenden
        case "EDIT_UNDO": NSApp.sendAction(Selector(("undo:")), to: nil, from: self)
        case "EDIT_REDO": NSApp.sendAction(Selector(("redo:")), to: nil, from: self)
        case "EDIT_CUT": NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self)
        case "EDIT_COPY": NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self)
        case "EDIT_PASTE": NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self)
        case "EDIT_DELETE": e?.nachricht(SCI_CLEAR)
        case "EDIT_SELECTALL": e?.nachricht(SCI_SELECTALL)
        case "EDIT_BEGINENDSELECT", "EDIT_BEGINENDSELECT_COLUMNMODE": beginnEndeAuswahl(spalte: id.hasSuffix("COLUMNMODE"))
        case "EDIT_INSERT_DATETIME_SHORT", "EDIT_INSERT_DATETIME_LONG", "EDIT_INSERT_DATETIME_CUSTOMIZED":
            let f = DateFormatter()
            if id.hasSuffix("SHORT") { f.dateStyle = .short; f.timeStyle = .short }
            else if id.hasSuffix("LONG") { f.dateStyle = .full; f.timeStyle = .short }
            else { f.dateFormat = "yyyy-MM-dd HH:mm:ss" }
            e?.nachricht(SCI_REPLACESEL, 0, text: f.string(from: Date()))
        case "EDIT_FULLPATHTOCLIP": Werkzeuge.zwischenablage(d?.fileURL?.path ?? d?.tabTitel ?? "")
        case "EDIT_FILENAMETOCLIP": Werkzeuge.zwischenablage(d?.tabTitel ?? "")
        case "EDIT_CURRENTDIRTOCLIP": Werkzeuge.zwischenablage(d?.fileURL?.deletingLastPathComponent().path ?? "")
        case "EDIT_COPY_ALL_NAMES": Werkzeuge.zwischenablage(tabs.map(\.tabTitel).joined(separator: "\n"))
        case "EDIT_COPY_ALL_PATHS": Werkzeuge.zwischenablage(tabs.map { $0.fileURL?.path ?? $0.tabTitel }.joined(separator: "\n"))
        case "EDIT_INS_TAB": e?.nachricht(SCI_TAB)
        case "EDIT_RMV_TAB": e?.nachricht(SCI_BACKTAB)
        case "EDIT_UPPERCASE": e?.wandleAuswahl(Schreibung.gross.wende(an:))
        case "EDIT_LOWERCASE": e?.wandleAuswahl(Schreibung.klein.wende(an:))
        case "EDIT_PROPERCASE_FORCE": e?.wandleAuswahl(Schreibung.woerterGross.wende(an:))
        case "EDIT_PROPERCASE_BLEND": e?.wandleAuswahl(Schreibung.woerterGrossBelassen.wende(an:))
        case "EDIT_SENTENCECASE_FORCE": e?.wandleAuswahl(Schreibung.satzanfang.wende(an:))
        case "EDIT_SENTENCECASE_BLEND": e?.wandleAuswahl(Schreibung.satzanfangBelassen.wende(an:))
        case "EDIT_INVERTCASE": e?.wandleAuswahl(Schreibung.umkehren.wende(an:))
        case "EDIT_RANDOMCASE": e?.wandleAuswahl(Schreibung.zufaellig.wende(an:))
        case "EDIT_DUP_LINE": e?.dupliziere()
        case "EDIT_REMOVE_ANY_DUP_LINES": zeilen(e, Zeilenwerkzeug.ohneDoppelte)
        case "EDIT_REMOVE_CONSECUTIVE_DUP_LINES": zeilen(e, Zeilenwerkzeug.ohneAufeinanderfolgendeDoppelte)
        case "EDIT_SPLIT_LINES":
            guard let e else { return }
            e.nachricht(SCI_TARGETFROMSELECTION)
            e.nachricht(SCI_LINESSPLIT)
        case "EDIT_JOIN_LINES": e?.verbindeZeilen()
        case "EDIT_LINE_UP": e?.zeilenHoch()
        case "EDIT_LINE_DOWN": e?.zeilenRunter()
        case "EDIT_REMOVEEMPTYLINES": zeilen(e) { Zeilenwerkzeug.ohneLeere($0, auchNurLeerzeichen: false) }
        case "EDIT_REMOVEEMPTYLINESWITHBLANK": zeilen(e) { Zeilenwerkzeug.ohneLeere($0, auchNurLeerzeichen: true) }
        case "EDIT_BLANKLINEABOVECURRENT", "EDIT_BLANKLINEBELOWCURRENT":
            guard let e else { return }
            let zeile = e.aktuelleZeile - 1
            let stelle = id.hasSuffix("ABOVECURRENT")
                ? e.nachricht(SCI_POSITIONFROMLINE, zeile) : e.nachricht(SCI_GETLINEENDPOSITION, zeile)
            e.nachricht(SCI_INSERTTEXT, stelle, text: e.zeilenende)
            if !id.hasSuffix("ABOVECURRENT") { e.nachricht(SCI_GOTOPOS, stelle + e.zeilenende.utf8.count) }
        case let s where s.hasPrefix("EDIT_SORTLINES_"):
            let tabelle: [String: Zeilenwerkzeug.Sortierung] = [
                "LEXICOGRAPHIC_ASCENDING": .aufsteigend, "LEXICOGRAPHIC_DESCENDING": .absteigend,
                "LEXICO_CASE_INSENS_ASCENDING": .ohneGrossKleinAuf, "LEXICO_CASE_INSENS_DESCENDING": .ohneGrossKleinAb,
                "LOCALE_ASCENDING": .gebietsschemaAuf, "LOCALE_DESCENDING": .gebietsschemaAb,
                "INTEGER_ASCENDING": .ganzzahlAuf, "INTEGER_DESCENDING": .ganzzahlAb,
                "DECIMALCOMMA_ASCENDING": .dezimalKommaAuf, "DECIMALCOMMA_DESCENDING": .dezimalKommaAb,
                "DECIMALDOT_ASCENDING": .dezimalPunktAuf, "DECIMALDOT_DESCENDING": .dezimalPunktAb,
                "LENGTH_ASCENDING": .laengeAuf, "LENGTH_DESCENDING": .laengeAb,
                "REVERSE_ORDER": .umkehren, "RANDOMLY": .zufaellig,
            ]
            if let art = tabelle[String(s.dropFirst("EDIT_SORTLINES_".count))] { zeilen(e) { Zeilenwerkzeug.sortiere($0, art) } }
        case "EDIT_BLOCK_COMMENT": e?.schalteKommentar(block: false)
        case "EDIT_BLOCK_COMMENT_SET": e?.schalteKommentar(block: false, art: .setzen)
        case "EDIT_BLOCK_UNCOMMENT": e?.schalteKommentar(block: false, art: .entfernen)
        case "EDIT_STREAM_COMMENT", "EDIT_STREAM_UNCOMMENT": e?.schalteKommentar(block: true)
        case "EDIT_AUTOCOMPLETE", "EDIT_AUTOCOMPLETE_CURRENTFILE": e?.schlageVorJetzt(nurText: id.hasSuffix("CURRENTFILE"))
        case "EDIT_FUNCCALLTIP": e?.zeigeAufrufhilfeJetzt()
        case "FORMAT_TODOS": d?.setzeZeilenende(.crlf)
        case "FORMAT_TOUNIX": d?.setzeZeilenende(.lf)
        case "FORMAT_TOMAC": d?.setzeZeilenende(.cr)
        case "EDIT_TRIMTRAILING": zeilen(e) { Zeilenwerkzeug.kuerze($0, .ende) }
        case "EDIT_TRIMLINEHEAD": zeilen(e) { Zeilenwerkzeug.kuerze($0, .anfang) }
        case "EDIT_TRIM_BOTH": zeilen(e) { Zeilenwerkzeug.kuerze($0, .beide) }
        case "EDIT_EOL2WS": zeilen(e) { [$0.joined(separator: " ")] }
        case "EDIT_TRIMALL": zeilen(e) { [Zeilenwerkzeug.kuerze($0, .beide).joined(separator: " ")] }
        case "EDIT_TAB2SW": zeilen(e) { Zeilenwerkzeug.tabsZuLeerzeichen($0, breite: Einstellungen.tabbreite) }
        case "EDIT_SW2TAB_ALL": zeilen(e) { Zeilenwerkzeug.leerzeichenZuTabs($0, breite: Einstellungen.tabbreite) }
        case "EDIT_SW2TAB_LEADING": zeilen(e) { Zeilenwerkzeug.fuehrendeLeerzeichenZuTabs($0, breite: Einstellungen.tabbreite) }
        case "EDIT_OPENSELECTEDFILETOEDIT", "EDIT_OPENSELECTEDFILEFOLDERINEXPLORER":
            guard let e, let text = e.text(e.auswahl)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
            let basis = d?.fileURL?.deletingLastPathComponent() ?? FileManager.default.homeDirectoryForCurrentUser
            let url = text.hasPrefix("/") ? URL(fileURLWithPath: text) : basis.appendingPathComponent(text)
            guard FileManager.default.fileExists(atPath: url.path) else { return NSSound.beep() }
            if id.hasSuffix("TOEDIT") {
                dokumente.openDocument(withContentsOf: url, display: true) { _, _, _ in }
            } else {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        case "EDIT_REDACT_SELECTION": e?.wandleAuswahl { String(repeating: "█", count: $0.count) }
        case "EDIT_SEARCHONINTERNET":
            guard let e, let text = e.text(e.auswahl), !text.isEmpty,
                let q = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                let url = URL(string: "https://duckduckgo.com/?q=\(q)")
            else { return }
            NSWorkspace.shared.open(url)
        case let s where s.hasPrefix("EDIT_MULTISELECTALL"): mehrfachauswahl(e, alle: true, id: s)
        case let s where s.hasPrefix("EDIT_MULTISELECTNEXT"): mehrfachauswahl(e, alle: false, id: s)
        case "EDIT_MULTISELECTUNDO":
            if let e, e.nachricht(SCI_GETSELECTIONS) > 1 { e.nachricht(SCI_DROPSELECTIONN, e.nachricht(SCI_GETSELECTIONS) - 1) }
        case "EDIT_MULTISELECTSSKIP":
            guard let e else { return }
            let haupt = e.nachricht(SCI_GETMAINSELECTION)
            e.nachricht(SCI_MULTIPLESELECTADDNEXT)
            if e.nachricht(SCI_GETSELECTIONS) > 1 { e.nachricht(SCI_DROPSELECTIONN, haupt) }
        case "EDIT_COLUMNMODETIP":
            let hinweis = NSAlert()
            hinweis.messageText = Oberflaeche.gemeinsam.titel(voll).replacingOccurrences(of: " …", with: "")
            hinweis.informativeText = "Spaltenauswahl: ⌥ (Wahltaste) gedrückt halten und mit der Maus ziehen, oder ⌥⇧ mit den Pfeiltasten. Dann tippen, einfügen oder den Block-Editor (⌥⌘C) nutzen."
            hinweis.beginSheetModal(for: window!)
        case "EDIT_COLUMNMODE": if let e, let w = window { Spalteneditor.zeige(in: w, editor: e) }
        case "EDIT_TOGGLEREADONLY": d?.schreibgeschuetzt.toggle()
        case "EDIT_SETREADONLYFORALLDOCS": tabs.forEach { $0.schreibgeschuetzt = true }
        case "EDIT_CLEARREADONLYFORALLDOCS": tabs.forEach { $0.schreibgeschuetzt = false }

        // Suchen
        case "SEARCH_FIND": SuchenDialog.gemeinsam.zeige(.suchen)
        case "SEARCH_REPLACE": SuchenDialog.gemeinsam.zeige(.ersetzen)
        case "SEARCH_FINDINFILES": SuchenDialog.gemeinsam.zeige(.inDateien)
        case "SEARCH_MARK": SuchenDialog.gemeinsam.zeige(.markieren)
        case "SEARCH_FINDNEXT", "SEARCH_FINDPREV":
            if let e { melde(Suchaktion.weiter(in: e, rueckwaerts: id.hasSuffix("PREV"))) }
        case "SEARCH_SETANDFINDNEXT", "SEARCH_SETANDFINDPREV", "SEARCH_VOLATILE_FINDNEXT", "SEARCH_VOLATILE_FINDPREV":
            guard let e else { return }
            var a = e.auswahl
            if a.isEmpty {
                let m = e.marke
                a = e.nachricht(SCI_WORDSTARTPOSITION, m, 1)..<e.nachricht(SCI_WORDENDPOSITION, m, 1)
            }
            guard let text = e.text(a), !text.isEmpty else { return NSSound.beep() }
            let vorher = SuchZustand.gemeinsam.optionen
            var o = vorher
            o.text = text
            o.modus = .normal
            SuchZustand.gemeinsam.optionen = o
            e.waehleAus(a)
            melde(Suchaktion.weiter(in: e, rueckwaerts: id.hasSuffix("PREV")))
            if id.contains("VOLATILE") { SuchZustand.gemeinsam.optionen = vorher }
        case "SEARCH_FINDINCREMENT": inkrementell.zeige(editor: { [weak self] in self?.aktiv })
        case "FOCUS_ON_FOUND_RESULTS": Suchergebnisse.gemeinsam.fokussiere()
        case "SEARCH_GOTONEXTFOUND": Suchergebnisse.gemeinsam.springe(weiter: true)
        case "SEARCH_GOTOPREVFOUND": Suchergebnisse.gemeinsam.springe(weiter: false)
        case "SEARCH_GOTOLINE": geheZuZeile()
        case "SEARCH_GOTOMATCHINGBRACE": e?.geheZurPassendenKlammer(auswaehlen: false)
        case "SEARCH_SELECTMATCHINGBRACES": e?.geheZurPassendenKlammer(auswaehlen: true)
        case "SEARCH_CLEARALLMARKS":
            guard let e else { return }
            for i in [Editor.indikatorMarkiert, Editor.indikatorSuche] + Editor.indikatorenStil { e.loescheMarkierungen(i) }
        case let s where s.hasPrefix("SEARCH_MARKALLEXT"): e?.hebeHervor(stil: Int(s.suffix(1))!, alle: true)
        case let s where s.hasPrefix("SEARCH_MARKONEEXT"): e?.hebeHervor(stil: Int(s.suffix(1))!, alle: false)
        case let s where s.hasPrefix("SEARCH_UNMARKALLEXT"): e?.loescheMarkierungen(Editor.indikatorenStil[Int(s.suffix(1))! - 1])
        case let s where s.hasPrefix("SEARCH_GONEXTMARKER") || s.hasPrefix("SEARCH_GOPREVMARKER"):
            let stil = s.hasSuffix("_DEF") ? nil : Int(s.suffix(1))
            e?.springeZuMarkierung(stil: stil, weiter: s.contains("NEXT"))
        case let s where s.hasPrefix("SEARCH_STYLE") || s == "SEARCH_ALLSTYLESTOCLIP" || s == "SEARCH_MARKEDTOCLIP":
            guard let e else { return }
            let indikatoren: [Int32] = s == "SEARCH_MARKEDTOCLIP" ? [Editor.indikatorMarkiert]
                : s == "SEARCH_ALLSTYLESTOCLIP" ? Editor.indikatorenStil
                : [Editor.indikatorenStil[Int(String(s.dropFirst(12).prefix(1)))! - 1]]
            let text = e.markierterText(indikatoren)
            if text.isEmpty { NSSound.beep() } else { Werkzeuge.zwischenablage(text) }
        case "SEARCH_TOGGLE_BOOKMARK": e?.schalteLesezeichen()
        case "SEARCH_NEXT_BOOKMARK": e?.springeZuLesezeichen(rueckwaerts: false)
        case "SEARCH_PREV_BOOKMARK": e?.springeZuLesezeichen(rueckwaerts: true)
        case "SEARCH_CLEAR_BOOKMARKS": e?.lesezeichen = []
        case "SEARCH_COPYMARKEDLINES", "SEARCH_CUTMARKEDLINES":
            guard let e else { return }
            let text = e.lesezeichenText()
            guard !text.isEmpty else { return NSSound.beep() }
            Werkzeuge.zwischenablage(text)
            if id == "SEARCH_CUTMARKEDLINES" { e.loescheZeilenMitLesezeichen() }
        case "SEARCH_DELETEMARKEDLINES": e?.loescheZeilenMitLesezeichen()
        case "SEARCH_DELETEUNMARKEDLINES": e?.loescheZeilenMitLesezeichen(ohne: true)
        case "SEARCH_INVERSEMARKS": e?.kehreLesezeichenUm()

        // Ansicht
        case "VIEW_ALWAYSONTOP": window?.level = window?.level == .floating ? .normal : .floating
        case "VIEW_FULLSCREENTOGGLE": window?.toggleFullScreen(nil)
        case "VIEW_POSTIT": postIt.toggle()
        case "VIEW_DISTRACTIONFREE": ablenkungsfrei.toggle()
        case "VIEW_IN_FIREFOX", "VIEW_IN_CHROME", "VIEW_IN_EDGE":
            if let u = d?.fileURL, let app = Werkzeuge.browser(id) {
                NSWorkspace.shared.open([u], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
            }
        case "VIEW_TAB_SPACE": Einstellungen.leerzeichenZeigen.toggle()
        case "VIEW_EOL": Einstellungen.zeilenendenZeigen.toggle()
        case "VIEW_ALL_CHARACTERS":
            let an = !(Einstellungen.leerzeichenZeigen && Einstellungen.zeilenendenZeigen)
            Einstellungen.leerzeichenZeigen = an
            Einstellungen.zeilenendenZeigen = an
        case "VIEW_INDENT_GUIDE": Einstellungen.einrueckungshilfen.toggle()
        case "VIEW_WRAP_SYMBOL": Einstellungen.umbruchSymbol.toggle()
        case "VIEW_ZOOMIN": e?.vergroessere()
        case "VIEW_ZOOMOUT": e?.verkleinere()
        case "VIEW_ZOOMRESTORE": e?.originalgroesse()
        case "VIEW_CLONE_TO_ANOTHER_VIEW": teile(nebeneinander: geteilt ? nil : true)
        case "VIEW_SWITCHTO_OTHER_VIEW":
            if let z = zweiterEditor, let h = editor { window?.makeFirstResponder((aktiv === z ? h : z).ansicht.content()) }
        case let s where s.hasPrefix("VIEW_TAB") && Int(s.suffix(1)) != nil && !s.contains("COLOUR"):
            let i = Int(s.suffix(1))! - 1
            if i < tabs.count { aktiviere(tabs[i]) }
        case "VIEW_TAB_NEXT", "VIEW_TAB_PREV", "VIEW_TAB_START", "VIEW_TAB_END":
            guard let d, let i = tabs.firstIndex(where: { $0 === d }), !tabs.isEmpty else { return }
            let ziel = id == "VIEW_TAB_NEXT" ? (i + 1) % tabs.count : id == "VIEW_TAB_PREV" ? (i - 1 + tabs.count) % tabs.count
                : id == "VIEW_TAB_START" ? 0 : tabs.count - 1
            aktiviere(tabs[ziel])
        case "VIEW_GOTO_START": verschiebeAktiven(nach: 0)
        case "VIEW_GOTO_END": verschiebeAktiven(nach: tabs.count)
        case "VIEW_TAB_MOVEFORWARD", "VIEW_TAB_MOVEBACKWARD":
            guard let d, let i = tabs.firstIndex(where: { $0 === d }) else { return }
            verschiebeAktiven(nach: id.hasSuffix("FORWARD") ? i + 1 : max(0, i - 1))
        case let s where s.hasPrefix("VIEW_TAB_COLOUR_"):
            d?.tabFarbe = s.hasSuffix("NONE") ? nil : Int(s.suffix(1))
            tabsGeaendert()
        case "VIEW_WRAP":
            let an = !(editor?.umbruch ?? false)
            editor?.umbruch = an
            zweiterEditor?.umbruch = an
        case "VIEW_FOLDALL": e?.klappeAlles(ein: true)
        case "VIEW_UNFOLDALL": e?.klappeAlles(ein: false)
        case "VIEW_FOLD_CURRENT", "VIEW_UNFOLD_CURRENT": e?.klappeAktuellen(ein: id == "VIEW_FOLD_CURRENT")
        case let s where s.hasPrefix("VIEW_FOLD_") || s.hasPrefix("VIEW_UNFOLD_"):
            e?.klappeEbene(Int(s.suffix(1))!, ein: s.hasPrefix("VIEW_FOLD_"))
        case "VIEW_SUMMARY": zeigeZusammenfassung()
        case "VIEW_FILEBROWSER": Einstellungen.arbeitsbereichSichtbar.toggle()
        case "VIEW_DOC_MAP": Einstellungen.miniaturansichtSichtbar.toggle()
        case "VIEW_DOCLIST", "WINDOW_WINDOWS": Einstellungen.dokumentenlisteSichtbar.toggle()
        case "VIEW_FUNC_LIST": Einstellungen.funktionslisteSichtbar.toggle()
        case "VIEW_SYNSCROLLV": synchronVertikal.toggle(); werkzeugleiste.aktualisiere()
        case "VIEW_SYNSCROLLH": synchronHorizontal.toggle(); werkzeugleiste.aktualisiere()
        case "VIEW_MONITORING": d?.ueberwacht.toggle()

        // Codierung: «Kodieren in» deutet die Datei neu, «Konvertieren zu» wandelt beim Sichern.
        case let s where s.hasPrefix("FORMAT_CONV2_"):
            if let k = Befehlsmenue.kodierung("FORMAT_" + s.dropFirst("FORMAT_CONV2_".count)) { d?.wandleUm(in: k) }
        case let s where s.hasPrefix("FORMAT_"):
            if let k = Befehlsmenue.kodierung(s) { d?.oeffneNeu(als: k) }

        // Sprache, Einstellungen, Werkzeuge
        case "LANG_USER_DLG": BenutzersprachenMenue.gemeinsam.importiere()
        case "LANG_OPENUDLDIR": BenutzersprachenMenue.gemeinsam.zeigeOrdnerOeffentlich()
        case "LANG_UDLCOLLECTION_PROJECT_SITE": oeffne("https://github.com/notepad-plus-plus/userDefinedLanguages")
        case "SETTING_PREFERENCE", "LANGSTYLE_CONFIG_DLG": EinstellungsFenster.gemeinsam.zeige()
        case let s where s.hasPrefix("TOOL_"): Werkzeuge.hash(s, editor: e, fenster: window)

        // Makros, Ausführen, Fenster
        case "MACRO_STARTRECORDINGMACRO": if let e { Makros.gemeinsam.starte(in: e) }; werkzeugleiste.aktualisiere()
        case "MACRO_STOPRECORDINGMACRO": Makros.gemeinsam.beende(); werkzeugleiste.aktualisiere()
        case "MACRO_PLAYBACKRECORDEDMACRO": if let e { Makros.gemeinsam.spiele(Makros.gemeinsam.aktuelles, in: e) }
        case "MACRO_SAVECURRENTMACRO": MakroDialoge.sichern(fenster: window)
        case "MACRO_RUNMULTIMACRODLG": if let e { MakroDialoge.mehrfach(fenster: window, editor: e) }
        case "EXECUTE": Werkzeuge.ausfuehren(dokument: d, editor: e, fenster: window)
        case let s where s.hasPrefix("WINDOW_SORT_"):
            let art = s.dropFirst("WINDOW_SORT_".count).prefix(2)
            let ab = s.hasSuffix("DSC")
            func wert(_ d: Dokument) -> String {
                switch art {
                case "FP": return d.fileURL?.path ?? d.tabTitel
                case "FT": return (d.fileURL?.pathExtension ?? "") + d.tabTitel
                case "FS": return String(format: "%020d", d.editor?.laenge ?? 0)
                case "FD":
                    let datum = (try? d.fileURL?.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    return String(format: "%020.0f", datum?.timeIntervalSince1970 ?? 0)
                default: return d.tabTitel
                }
            }
            sortiereTabs { ab ? wert($0).localizedStandardCompare(wert($1)) == .orderedDescending : wert($0).localizedStandardCompare(wert($1)) == .orderedAscending }

        // ?
        case "CMDLINEARGUMENTS":
            let hinweis = NSAlert()
            hinweis.messageText = "Kommandozeile"
            hinweis.informativeText = "kladde [datei …]\n\nÖffnet die Dateien in Kladde; fehlende Dateien legt der Befehl leer an. Installieren: Kladde → Einstellungen → Terminal."
            hinweis.beginSheetModal(for: window!)
        case "HOMESWEETHOME", "PROJECTPAGE": oeffne("https://github.com/simon-baumhauer/kladde")
        case "ONLINEDOCUMENT": oeffne("https://github.com/simon-baumhauer/kladde#readme")
        case "FORUM": oeffne("https://github.com/simon-baumhauer/kladde/issues")
        case "UPDATE_NPP": oeffne("https://github.com/simon-baumhauer/kladde/releases")
        case "DEBUGINFO": zeigeDebugInfo()
        case "ABOUT": (NSApp.delegate as? AppDelegate)?.zeigeUeber(nil)
        default:
            NSSound.beep()
        }
        werkzeugleiste.aktualisiere()
        statusleiste.aktualisiere()
    }

    // MARK: Helfer

    private func oeffne(_ adresse: String) {
        if let u = URL(string: adresse) { NSWorkspace.shared.open(u) }
    }

    /// Ein Zeilenbefehl auf die Zeilen der Auswahl oder des ganzen Textes.
    private func zeilen(_ e: Editor?, _ wandle: ([String]) -> [String]) {
        guard let e else { return }
        let (bereich, z) = e.zeilenFuerBefehl()
        e.ersetzeZeilen(bereich, durch: wandle(z))
    }

    /// Antwort einer Suche: ein Ton, wenn nichts gefunden wurde, und die Statusleiste.
    func melde(_ antwort: Suchaktion.Antwort) {
        if antwort.fehler { NSSound.beep() }
        SuchenDialog.gemeinsam.zeigeStatus(antwort)
        statusleiste.meldung(antwort.text)
    }

    private func mehrfachauswahl(_ e: Editor?, alle: Bool, id: String) {
        guard let e else { return }
        var schalter: Int32 = 0
        if id.contains("MATCHCASE") { schalter |= SCFIND_MATCHCASE }
        if id.contains("WHOLEWORD") { schalter |= SCFIND_WHOLEWORD }
        e.nachricht(SCI_SETSEARCHFLAGS, Int(schalter))
        e.nachricht(SCI_TARGETWHOLEDOCUMENT)
        e.nachricht(alle ? SCI_MULTIPLESELECTADDEACH : SCI_MULTIPLESELECTADDNEXT)
    }

    func geheZuZeile() {
        guard let e = aktiv, let w = window else { return }
        let o = Oberflaeche.gemeinsam
        let frage = NSAlert()
        frage.messageText = o.texte["GoToLine.title"] ?? "Gehe zu"
        frage.informativeText = "Zeile 1 bis \(e.zeilenanzahl), jetzt \(e.aktuelleZeile)"
        let feld = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        feld.placeholderString = "\(e.aktuelleZeile)"
        frage.accessoryView = feld
        frage.addButton(withTitle: o.texte["GoToLine.1"] ?? "Los")
        frage.addButton(withTitle: o.texte["GoToLine.2"] ?? "Abbrechen")
        frage.window.initialFirstResponder = feld
        frage.beginSheetModal(for: w) { antwort in
            guard antwort == .alertFirstButtonReturn, let z = Int(feld.stringValue.trimmingCharacters(in: .whitespaces)) else { return }
            e.geheZuZeile(z)
            w.makeFirstResponder(e.ansicht.content())
        }
    }

    private func neuLaden(_ d: Dokument?) {
        guard let d, let url = d.fileURL else { return }
        let laden = {
            try? d.revert(toContentsOf: url, ofType: d.fileType ?? "public.plain-text")
            Hauptfenster.gemeinsam.tabsGeaendert()
        }
        guard d.isDocumentEdited, let w = window else { return laden() }
        let frage = NSAlert()
        frage.messageText = "«\(d.tabTitel)» neu laden?"
        frage.informativeText = "Die Änderungen seit dem letzten Speichern gehen verloren."
        frage.addButton(withTitle: "Neu laden")
        frage.addButton(withTitle: "Abbrechen")
        frage.beginSheetModal(for: w) { if $0 == .alertFirstButtonReturn { laden() } }
    }

    private func umbenennen(_ d: Dokument?) {
        guard let d, let w = window else { return }
        let frage = NSAlert()
        frage.messageText = Oberflaeche.gemeinsam.titel("IDM_FILE_RENAME").replacingOccurrences(of: " …", with: "")
        let feld = NSTextField(string: d.tabTitel)
        feld.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        frage.accessoryView = feld
        frage.addButton(withTitle: "Umbenennen")
        frage.addButton(withTitle: "Abbrechen")
        frage.window.initialFirstResponder = feld
        frage.beginSheetModal(for: w) { antwort in
            let name = feld.stringValue.trimmingCharacters(in: .whitespaces)
            guard antwort == .alertFirstButtonReturn, !name.isEmpty, !name.contains("/") else { return }
            if let alt = d.fileURL {
                let neu = alt.deletingLastPathComponent().appendingPathComponent(name)
                do {
                    try FileManager.default.moveItem(at: alt, to: neu)
                    d.fileURL = neu
                } catch {
                    d.presentError(error)
                }
            } else {
                d.saveAs(nil)
            }
            Hauptfenster.gemeinsam.tabsGeaendert()
        }
    }

    private func inPapierkorb(_ d: Dokument?) {
        guard let d, let url = d.fileURL, let w = window else { return }
        let frage = NSAlert()
        frage.messageText = "«\(d.tabTitel)» in den Papierkorb verschieben?"
        frage.informativeText = "Der Tab wird geschlossen. Aus dem Papierkorb lässt sich die Datei zurückholen."
        frage.alertStyle = .warning
        frage.addButton(withTitle: "In den Papierkorb")
        frage.addButton(withTitle: "Abbrechen")
        frage.beginSheetModal(for: w) { antwort in
            guard antwort == .alertFirstButtonReturn else { return }
            NSWorkspace.shared.recycle([url]) { _, fehler in
                if let fehler { d.presentError(fehler); return }
                d.updateChangeCount(.changeCleared)
                Hauptfenster.gemeinsam.entferne(d)
                d.close()
            }
        }
    }

    private func zeigeZusammenfassung() {
        guard let d = aktivesDokument, let e = editor, let w = window else { return }
        let s = e.stand
        let text = String(decoding: e.utf8, as: UTF8.self)
        let woerter = text.split { $0.isWhitespace || $0.isNewline }.count
        var zeilen = [String]()
        if let u = d.fileURL {
            zeilen.append("Vollständiger Dateipfad: \(u.path)")
            if let werte = try? u.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey]) {
                let f = DateFormatter()
                f.dateStyle = .medium
                f.timeStyle = .medium
                if let c = werte.creationDate { zeilen.append("Erstellt: \(f.string(from: c))") }
                if let m = werte.contentModificationDate { zeilen.append("Geändert: \(f.string(from: m))") }
            }
        }
        zeilen += [
            "", "Zeichen (ohne Zeilenenden): \(s.laenge - (s.zeilen - 1) * e.zeilenende.count)",
            "Wörter: \(woerter)", "Zeilen: \(s.zeilen)", "Dokumentlänge: \(e.laenge) Bytes",
            "\(s.ausgewaehlteZeichen) ausgewählte Zeichen (\(e.auswahl.count) Bytes) in \(s.ausgewaehlteZeilen) Zeilen",
        ]
        let hinweis = NSAlert()
        hinweis.messageText = Oberflaeche.gemeinsam.titel("IDM_VIEW_SUMMARY").replacingOccurrences(of: " …", with: "")
        hinweis.informativeText = zeilen.joined(separator: "\n")
        hinweis.beginSheetModal(for: w)
    }

    private func zeigeDebugInfo() {
        let info = Bundle.main.infoDictionary ?? [:]
        let text = """
            Kladde \(info["CFBundleShortVersionString"] as? String ?? "?") (\(info["CFBundleVersion"] as? String ?? "?"))
            macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
            Architektur: \(Werkzeuge.architektur)
            Farbschema: \(Einstellungen.schemaName(fuer: NSApp.effectiveAppearance))
            Offene Dokumente: \(tabs.count)
            """
        let hinweis = NSAlert()
        hinweis.messageText = "Debug-Info"
        hinweis.informativeText = text
        hinweis.addButton(withTitle: "In die Zwischenablage")
        hinweis.addButton(withTitle: "Schliessen")
        hinweis.beginSheetModal(for: window!) { if $0 == .alertFirstButtonReturn { Werkzeuge.zwischenablage(text) } }
    }
}

// MARK: - Menüs aus den Daten

enum Befehlsmenue {
    /// Kodierung zu einem Befehl FORMAT_…
    static func kodierung(_ id: String) -> Textdatei.Kodierung? {
        switch id.hasPrefix("IDM_") ? String(id.dropFirst(4)) : id {
        case "FORMAT_ANSI", "FORMAT_WIN_1252": return .windows1252
        case "FORMAT_AS_UTF_8": return .utf8
        case "FORMAT_UTF_8": return .utf8MitBOM
        case "FORMAT_UTF_16BE": return .utf16BE
        case "FORMAT_UTF_16LE": return .utf16LE
        default: return nil
        }
    }

    /// Die Menüleiste: zuerst das App-Menü des Mac, dann die Menüs von Notepad++.
    static func baue() -> NSMenu {
        let leiste = NSMenu()
        leiste.addItem(appMenue())
        for m in Oberflaeche.gemeinsam.menues {
            let kopf = NSMenuItem(title: Mac.text(m.titel), action: nil, keyEquivalent: "")
            let menue = NSMenu(title: kopf.title)
            switch m.kennung {
            case "language": sprachen(in: menue, aus: m.eintraege)
            case "macro":
                eintraege(m.eintraege).forEach(menue.addItem)
                menue.delegate = MakroMenue.gemeinsam
                MakroMenue.gemeinsam.festeEintraege = menue.items.count
            case "Window":
                eintraege(m.eintraege).forEach(menue.addItem)
                menue.delegate = FensterMenue.gemeinsam
                FensterMenue.gemeinsam.festeEintraege = menue.items.count
                NSApp.windowsMenu = menue
            default:
                eintraege(m.eintraege).forEach(menue.addItem)
            }
            if m.kennung == "?" { NSApp.helpMenu = menue }
            kopf.submenu = menue
            leiste.addItem(kopf)
        }
        return leiste
    }

    static func tabmenue() -> NSMenu {
        let menue = NSMenu()
        eintraege(Oberflaeche.gemeinsam.tabmenue).forEach(menue.addItem)
        return menue
    }

    /// Das Kontextmenü im Editor, wie das von Notepad++ (contextMenu.xml).
    static func editormenue() -> NSMenu {
        let menue = NSMenu()
        func befehl(_ id: String) -> NSMenuItem { eintrag(id: "IDM_" + id, titel: Oberflaeche.gemeinsam.titel("IDM_" + id), kuerzel: nil) }
        let o = Oberflaeche.gemeinsam
        func gruppe(_ titel: String, _ ids: [String]) -> NSMenuItem {
            let kopf = NSMenuItem(title: titel, action: nil, keyEquivalent: "")
            let unter = NSMenu(title: titel)
            ids.map(befehl).forEach(unter.addItem)
            kopf.submenu = unter
            return kopf
        }
        for e in [
            befehl("EDIT_CUT"), befehl("EDIT_COPY"), befehl("EDIT_PASTE"), befehl("EDIT_DELETE"), befehl("EDIT_SELECTALL"),
            befehl("EDIT_BEGINENDSELECT"), .separator(),
            gruppe(o.texte["contextMenu-styleAlloccurrencesOfToken"] ?? "Alle Treffer hervorheben", (1...5).map { "SEARCH_MARKALLEXT\($0)" }),
            gruppe(o.texte["contextMenu-styleOneToken"] ?? "Diesen Treffer hervorheben", (1...5).map { "SEARCH_MARKONEEXT\($0)" }),
            gruppe(o.texte["contextMenu-clearStyle"] ?? "Alle Hervorhebungen entfernen", (1...5).map { "SEARCH_UNMARKALLEXT\($0)" } + ["SEARCH_CLEARALLMARKS"]),
            .separator(),
            befehl("EDIT_UPPERCASE"), befehl("EDIT_LOWERCASE"), .separator(),
            befehl("EDIT_OPENSELECTEDFILETOEDIT"), befehl("EDIT_SEARCHONINTERNET"), .separator(),
            befehl("EDIT_BLOCK_COMMENT"), befehl("EDIT_STREAM_COMMENT"), .separator(),
            befehl("VIEW_FOLD_CURRENT"), befehl("VIEW_UNFOLD_CURRENT"),
        ] { menue.addItem(e) }
        return menue
    }

    private static func appMenue() -> NSMenuItem {
        let kopf = NSMenuItem(title: "Kladde", action: nil, keyEquivalent: "")
        let menue = NSMenu(title: "Kladde")
        func e(_ t: String, _ a: Selector, _ k: String = "", _ m: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let i = NSMenuItem(title: t, action: a, keyEquivalent: k)
            i.keyEquivalentModifierMask = m
            return i
        }
        let dienste = NSMenuItem(title: "Dienste", action: nil, keyEquivalent: "")
        dienste.submenu = NSMenu(title: "Dienste")
        NSApp.servicesMenu = dienste.submenu
        for i in [
            e("Über Kladde", #selector(AppDelegate.zeigeUeber(_:))), .separator(),
            e("Einstellungen …", #selector(AppDelegate.zeigeEinstellungen(_:)), ","), .separator(), dienste, .separator(),
            e("Kladde ausblenden", #selector(NSApplication.hide(_:)), "h"),
            e("Andere ausblenden", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            e("Alle einblenden", #selector(NSApplication.unhideAllApplications(_:))), .separator(),
            e("Kladde beenden", #selector(NSApplication.terminate(_:)), "q"),
        ] { menue.addItem(i) }
        kopf.submenu = menue
        return kopf
    }

    /// «Sprache»: die eigene Liste nach Anfangsbuchstaben, dann die Einträge von
    /// Notepad++ für benutzerdefinierte Sprachen samt den importierten.
    private static func sprachen(in menue: NSMenu, aus daten: [Oberflaeche.Eintrag]) {
        let eigene = Menue.sprachEintraege()
        if let erster = eigene.first { erster.title = Oberflaeche.gemeinsam.titel("IDM_LANG_TEXT") }
        eigene.forEach(menue.addItem)
        menue.addItem(.separator())
        for d in daten {
            if case .untermenue(let titel, _, let kinder) = d, kinder.contains(where: {
                if case .befehl(let id, _, _, _) = $0 { return id == "IDM_LANG_USER_DLG" }
                return false
            }) {
                let kopf = NSMenuItem(title: Mac.text(titel), action: nil, keyEquivalent: "")
                let unter = NSMenu(title: titel)
                eintraege(kinder).forEach(unter.addItem)
                unter.addItem(.separator())
                let liste = BenutzersprachenMenue.gemeinsam.menue()
                liste.submenu?.items.forEach { _ in }
                unter.addItem(liste)
                kopf.submenu = unter
                menue.addItem(kopf)
            }
        }
    }

    static func eintraege(_ liste: [Oberflaeche.Eintrag]) -> [NSMenuItem] {
        liste.map { e -> NSMenuItem in
            switch e {
            case .trenner: return .separator()
            case .befehl(let id, let titel, let kuerzel, _): return eintrag(id: id, titel: titel, kuerzel: kuerzel)
            case .untermenue(let titel, _, let kinder):
                let kopf = NSMenuItem(title: Mac.text(titel), action: nil, keyEquivalent: "")
                let unter = NSMenu(title: kopf.title)
                eintraege(kinder).forEach(unter.addItem)
                kopf.submenu = unter
                return kopf
            }
        }
    }

    /// Ein Befehl: ausführbar über Hauptfenster.befehl, sonst ausgegraut.
    static func eintrag(id: String, titel: String, kuerzel: Oberflaeche.Kuerzel?) -> NSMenuItem {
        let item = NSMenuItem(title: Mac.text(titel), action: nil, keyEquivalent: "")
        item.representedObject = id
        if Hauptfenster.befehle.contains(id) {
            item.action = #selector(Hauptfenster.befehl(_:))
            item.target = Hauptfenster.gemeinsam
        }
        if let (taste, maske) = macKuerzel(id: id, kuerzel) {
            item.keyEquivalent = taste
            item.keyEquivalentModifierMask = maske
        }
        // Beim Verweilen im Menü: was der Befehl tut.
        item.toolTip = Beschreibung.text(id)
        return item
    }

    /// Kürzel von Notepad++ auf dem Mac: Ctrl wird ⌘, Alt ⌥, Shift ⇧. Wo macOS
    /// ⌘ selbst belegt (⌘Q, ⌘H, ⌘M, ⌘Leertaste …), bleibt es ⌃.
    static func macKuerzel(id: String, _ k: Oberflaeche.Kuerzel?) -> (String, NSEvent.ModifierFlags)? {
        // Eigene Zuordnungen für Mac-Gewohnheiten.
        switch id {
        case "IDM_FILE_EXIT": return ("q", .command)
        case "IDM_EDIT_REDO": return ("z", [.command, .shift])
        default: break
        }
        guard let k, let taste = taste(k.taste) else { return nil }
        var maske: NSEvent.ModifierFlags = []
        if k.ctrl { maske.insert(.command) }
        if k.alt { maske.insert(.option) }
        if k.shift { maske.insert(.shift) }
        let vonMacBelegt: Set<String> = ["q", "h", "m", "`", " ", "\t", ","]
        if maske == .command, vonMacBelegt.contains(taste) || id == "IDM_VIEW_TAB_NEXT" || id == "IDM_VIEW_TAB_PREV" {
            maske = [.control]
        }
        if maske == [.command, .shift], ["3", "4", "5", "\t"].contains(taste) { maske = [.control, .shift] }
        return (taste, maske)
    }

    private static func taste(_ vk: String) -> String? {
        if vk.count == 1 { return vk.lowercased() }
        if vk.hasPrefix("F"), let n = Int(vk.dropFirst()), (1...20).contains(n) { return Menue.taste(NSF1FunctionKey + n - 1) }
        if vk.hasPrefix("NUMPAD"), let n = Int(vk.dropFirst(6)) { return "\(n)" }
        switch vk {
        case "TAB": return "\t"
        case "UP": return Menue.taste(NSUpArrowFunctionKey)
        case "DOWN": return Menue.taste(NSDownArrowFunctionKey)
        case "LEFT": return Menue.taste(NSLeftArrowFunctionKey)
        case "RIGHT": return Menue.taste(NSRightArrowFunctionKey)
        case "ADD", "OEM_PLUS": return "+"
        case "SUBTRACT", "OEM_MINUS": return "-"
        case "DIVIDE", "OEM_2": return "/"
        case "MULTIPLY": return "*"
        case "OEM_PERIOD": return "."
        case "OEM_COMMA": return ","
        case "SPACE": return " "
        case "RETURN": return "\r"
        case "DELETE": return Menue.taste(NSDeleteFunctionKey)
        case "BACK": return "\u{8}"
        case "HOME": return Menue.taste(NSHomeFunctionKey)
        case "END": return Menue.taste(NSEndFunctionKey)
        case "PRIOR": return Menue.taste(NSPageUpFunctionKey)
        case "NEXT": return Menue.taste(NSPageDownFunctionKey)
        case "INSERT": return nil
        default: return nil
        }
    }
}

/// «Fenster»: unten die offenen Dokumente, wie in Notepad++.
final class FensterMenue: NSObject, NSMenuDelegate {
    static let gemeinsam = FensterMenue()
    var festeEintraege = 0

    func menuNeedsUpdate(_ menu: NSMenu) {
        while menu.items.count > festeEintraege { menu.removeItem(at: festeEintraege) }
        let tabs = Hauptfenster.gemeinsam.tabs
        guard !tabs.isEmpty else { return }
        menu.addItem(.separator())
        for (i, d) in tabs.prefix(20).enumerated() {
            let e = NSMenuItem(title: "\(i + 1): \(d.tabTitel)", action: #selector(waehle(_:)), keyEquivalent: "")
            e.target = self
            e.tag = i
            e.state = d === Hauptfenster.gemeinsam.aktivesDokument ? .on : .off
            menu.addItem(e)
        }
    }

    @objc private func waehle(_ sender: NSMenuItem) {
        let tabs = Hauptfenster.gemeinsam.tabs
        if sender.tag < tabs.count { Hauptfenster.gemeinsam.aktiviere(tabs[sender.tag]) }
    }
}
