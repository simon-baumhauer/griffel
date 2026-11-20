import AppKit

/// Was ein Befehl genau tut, in einem Satz: für den Hinweis über den Knöpfen der
/// Werkzeugleiste und als Tooltip in den Menüs. Notepad++ selbst zeigt nur den
/// Namen; Griffel erklärt dazu, was passiert.
enum Beschreibung {
    static func text(_ id: String) -> String? { texte[id] }

    /// Das Kürzel eines Befehls in Mac-Schreibweise, etwa «⇧⌘S» oder «F3».
    static func kuerzel(_ id: String) -> String? {
        guard let (taste, maske) = Befehlsmenue.macKuerzel(id: id, Oberflaeche.gemeinsam.kuerzel(id)) else { return nil }
        var s = ""
        if maske.contains(.control) { s += "⌃" }
        if maske.contains(.option) { s += "⌥" }
        if maske.contains(.shift) { s += "⇧" }
        if maske.contains(.command) { s += "⌘" }
        return s + lesbar(taste)
    }

    private static func lesbar(_ taste: String) -> String {
        guard let z = taste.unicodeScalars.first else { return taste }
        let v = Int(z.value)
        if (NSF1FunctionKey...NSF35FunctionKey).contains(v) { return "F\(v - NSF1FunctionKey + 1)" }
        switch v {
        case NSUpArrowFunctionKey: return "↑"
        case NSDownArrowFunctionKey: return "↓"
        case NSLeftArrowFunctionKey: return "←"
        case NSRightArrowFunctionKey: return "→"
        case NSDeleteFunctionKey: return "⌦"
        case NSHomeFunctionKey: return "↖"
        case NSEndFunctionKey: return "↘"
        case NSPageUpFunctionKey: return "⇞"
        case NSPageDownFunctionKey: return "⇟"
        case 8, 127: return "⌫"
        case 9: return "⇥"
        case 13: return "↩"
        case 32: return "Leertaste"
        default: return taste.uppercased()
        }
    }

    private static let texte: [String: String] = [
        // Datei
        "IDM_FILE_NEW": "Legt ein neues, leeres Dokument in einem neuen Tab an («neu 1», «neu 2» …).",
        "IDM_FILE_OPEN": "Öffnet eine oder mehrere Dateien, jede in einem eigenen Tab. Über ▾ die zuletzt benutzten.",
        "IDM_FILE_SAVE": "Schreibt das aktive Dokument in seine Datei, mit Zeichensatz und Zeilenenden wie angezeigt.",
        "IDM_FILE_SAVEAS": "Sichert das Dokument unter einem neuen Namen; der Tab zeigt danach auf die neue Datei.",
        "IDM_FILE_SAVECOPYAS": "Schreibt eine Kopie in eine andere Datei; der Tab bleibt bei der bisherigen.",
        "IDM_FILE_SAVEALL": "Sichert alle geänderten Dokumente in allen Tabs.",
        "IDM_FILE_CLOSE": "Schliesst den aktiven Tab; bei ungesicherten Änderungen fragt Griffel nach.",
        "IDM_FILE_CLOSEALL": "Schliesst alle Tabs; ungesicherte Änderungen fragt Griffel einzeln ab.",
        "IDM_FILE_CLOSEALL_BUT_CURRENT": "Schliesst alle Tabs ausser dem aktiven.",
        "IDM_FILE_CLOSEALL_BUT_PINNED": "Schliesst alle Tabs, die nicht angeheftet sind.",
        "IDM_FILE_CLOSEALL_TOLEFT": "Schliesst alle Tabs links vom aktiven.",
        "IDM_FILE_CLOSEALL_TORIGHT": "Schliesst alle Tabs rechts vom aktiven.",
        "IDM_FILE_CLOSEALL_UNCHANGED": "Schliesst alle Tabs ohne ungesicherte Änderungen.",
        "IDM_FILE_PRINT": "Druckt das Dokument; vorher erscheint der Druckdialog von macOS.",
        "IDM_FILE_PRINTNOW": "Druckt sofort auf dem Standarddrucker, ohne Dialog.",
        "IDM_FILE_RELOAD": "Liest die Datei neu von der Platte; ungesicherte Änderungen gehen nach Rückfrage verloren.",
        "IDM_FILE_RENAME": "Benennt die Datei auf der Platte um, der Tab folgt.",
        "IDM_FILE_DELETE": "Verschiebt die Datei in den Papierkorb und schliesst den Tab.",
        "IDM_FILE_OPENFOLDERASWORKSPACE": "Zeigt einen Ordner links als Baum, zum schnellen Öffnen seiner Dateien.",
        "IDM_FILE_LOADSESSION": "Öffnet alle Dateien einer gesicherten Sitzung (.griffel-sitzung).",
        "IDM_FILE_SAVESESSION": "Merkt sich alle offenen Tabs als Sitzungsdatei, um sie später wieder zu öffnen.",
        "IDM_FILE_OPEN_FOLDER": "Zeigt die Datei im Finder.",
        "IDM_FILE_OPEN_CMD": "Öffnet ein Terminal im Ordner der Datei.",
        // Bearbeiten
        "IDM_EDIT_CUT": "Schneidet die Auswahl aus und legt sie in die Zwischenablage.",
        "IDM_EDIT_COPY": "Kopiert die Auswahl in die Zwischenablage.",
        "IDM_EDIT_PASTE": "Fügt den Inhalt der Zwischenablage an der Einfügemarke ein.",
        "IDM_EDIT_UNDO": "Nimmt die letzte Änderung zurück. Jedes Dokument hat seinen eigenen Verlauf.",
        "IDM_EDIT_REDO": "Stellt die zuletzt rückgängig gemachte Änderung wieder her.",
        "IDM_EDIT_DELETE": "Löscht die Auswahl oder das Zeichen rechts der Einfügemarke.",
        "IDM_EDIT_SELECTALL": "Wählt den ganzen Text aus.",
        "IDM_EDIT_DUP_LINE": "Verdoppelt die aktuelle Zeile oder die Auswahl.",
        "IDM_EDIT_LINE_UP": "Verschiebt die aktuelle Zeile oder die ausgewählten Zeilen eine Zeile nach oben.",
        "IDM_EDIT_LINE_DOWN": "Verschiebt die aktuelle Zeile oder die ausgewählten Zeilen eine Zeile nach unten.",
        "IDM_EDIT_JOIN_LINES": "Verbindet die ausgewählten Zeilen zu einer, mit Leerzeichen dazwischen.",
        "IDM_EDIT_SPLIT_LINES": "Bricht die ausgewählten Zeilen an der Breite des Fensters um.",
        "IDM_EDIT_REMOVE_ANY_DUP_LINES": "Entfernt jede Zeile, die weiter oben schon vorkommt.",
        "IDM_EDIT_REMOVE_CONSECUTIVE_DUP_LINES": "Entfernt Zeilen, die direkt der gleichen folgen.",
        "IDM_EDIT_REMOVEEMPTYLINES": "Entfernt leere Zeilen.",
        "IDM_EDIT_REMOVEEMPTYLINESWITHBLANK": "Entfernt leere Zeilen, auch solche mit nur Leerzeichen oder Tabs.",
        "IDM_EDIT_TRIMTRAILING": "Entfernt Leerzeichen und Tabs am Zeilenende.",
        "IDM_EDIT_TRIMLINEHEAD": "Entfernt Leerzeichen und Tabs am Zeilenanfang.",
        "IDM_EDIT_TRIM_BOTH": "Entfernt Leerzeichen und Tabs am Anfang und am Ende jeder Zeile.",
        "IDM_EDIT_UPPERCASE": "Schreibt die Auswahl in GROSSBUCHSTABEN.",
        "IDM_EDIT_LOWERCASE": "Schreibt die Auswahl in kleinbuchstaben.",
        "IDM_EDIT_PROPERCASE_FORCE": "Schreibt jedes Wort der Auswahl mit grossem Anfangsbuchstaben.",
        "IDM_EDIT_SENTENCECASE_FORCE": "Schreibt jeden Satz der Auswahl mit grossem Anfangsbuchstaben.",
        "IDM_EDIT_INVERTCASE": "Kehrt gross und klein in der Auswahl um.",
        "IDM_EDIT_BLOCK_COMMENT": "Kommentiert die Zeilen mit dem Zeilenkommentar der Sprache aus, oder wieder ein.",
        "IDM_EDIT_BLOCK_COMMENT_SET": "Setzt den Zeilenkommentar der Sprache vor jede ausgewählte Zeile.",
        "IDM_EDIT_BLOCK_UNCOMMENT": "Entfernt den Zeilenkommentar vor den ausgewählten Zeilen.",
        "IDM_EDIT_STREAM_COMMENT": "Setzt die Auswahl in einen Blockkommentar, etwa /* … */.",
        "IDM_EDIT_COLUMNMODE": "Fügt Text oder eine Zahlenfolge in jede Zeile der Rechteckauswahl ein.",
        "IDM_EDIT_AUTOCOMPLETE": "Zeigt Vorschläge zum Wort an der Einfügemarke, aus Wortliste und Text.",
        "IDM_EDIT_FUNCCALLTIP": "Zeigt die Parameter der Funktion, in deren Klammern die Marke steht.",
        "IDM_EDIT_INSERT_DATETIME_SHORT": "Fügt Datum und Uhrzeit kurz ein.",
        "IDM_EDIT_INSERT_DATETIME_LONG": "Fügt Datum und Uhrzeit ausführlich ein.",
        "IDM_EDIT_FULLPATHTOCLIP": "Kopiert den vollständigen Pfad der Datei in die Zwischenablage.",
        "IDM_EDIT_FILENAMETOCLIP": "Kopiert den Dateinamen in die Zwischenablage.",
        "IDM_EDIT_CURRENTDIRTOCLIP": "Kopiert den Ordner der Datei in die Zwischenablage.",
        // Suchen
        "IDM_SEARCH_FIND": "Öffnet den Dialog «Suchen» mit der Auswahl als Suchtext. Über ▾ Ersetzen, In Dateien suchen und mehr.",
        "IDM_SEARCH_REPLACE": "Öffnet den Dialog auf dem Reiter «Ersetzen».",
        "IDM_SEARCH_FINDINFILES": "Sucht oder ersetzt in allen passenden Dateien eines Ordners; die Treffer stehen unten im Suchergebnis.",
        "IDM_SEARCH_FINDNEXT": "Springt zum nächsten Treffer des letzten Suchtexts.",
        "IDM_SEARCH_FINDPREV": "Springt zum vorherigen Treffer des letzten Suchtexts.",
        "IDM_SEARCH_FINDINCREMENT": "Blendet unter dem Text eine Suchzeile ein, die schon beim Tippen sucht.",
        "IDM_SEARCH_MARK": "Öffnet den Dialog auf dem Reiter «Hervorheben»: alle Treffer farbig markieren, auf Wunsch mit Lesezeichen.",
        "IDM_SEARCH_GOTOLINE": "Springt zu einer Zeile oder Stelle im Text.",
        "IDM_SEARCH_GOTOMATCHINGBRACE": "Springt zur passenden Klammer.",
        "IDM_SEARCH_TOGGLE_BOOKMARK": "Setzt oder entfernt ein Lesezeichen in der aktuellen Zeile.",
        "IDM_SEARCH_NEXT_BOOKMARK": "Springt zum nächsten Lesezeichen.",
        "IDM_SEARCH_PREV_BOOKMARK": "Springt zum vorherigen Lesezeichen.",
        "IDM_SEARCH_CLEAR_BOOKMARKS": "Entfernt alle Lesezeichen.",
        // Ansicht
        "IDM_VIEW_ZOOMIN": "Vergrössert die Schrift im Editor. Über ▾ verkleinern oder zurücksetzen.",
        "IDM_VIEW_ZOOMOUT": "Verkleinert die Schrift im Editor.",
        "IDM_VIEW_ZOOMRESTORE": "Setzt die Schriftgrösse auf 100 % zurück.",
        "IDM_VIEW_SYNSCROLLV": "In der geteilten Ansicht scrollen beide Seiten senkrecht gemeinsam.",
        "IDM_VIEW_SYNSCROLLH": "In der geteilten Ansicht scrollen beide Seiten waagrecht gemeinsam.",
        "IDM_VIEW_WRAP": "Bricht lange Zeilen am Fensterrand um, ohne den Text zu ändern.",
        "IDM_VIEW_ALL_CHARACTERS": "Zeigt Leerzeichen, Tabs und Zeilenenden als Zeichen. Über ▾ nur einzelne davon.",
        "IDM_VIEW_TAB_SPACE": "Zeigt Leerzeichen als Punkte und Tabs als Pfeile.",
        "IDM_VIEW_EOL": "Zeigt die Zeilenenden als CR LF, LF oder CR.",
        "IDM_VIEW_INDENT_GUIDE": "Zeigt senkrechte Linien für die Einrückungsebenen.",
        "IDM_VIEW_DOC_MAP": "Zeigt rechts eine verkleinerte Karte des ganzen Dokuments; ein Klick springt hin.",
        "IDM_VIEW_DOCLIST": "Zeigt links alle offenen Dokumente als Liste.",
        "IDM_VIEW_FUNC_LIST": "Zeigt rechts die Klassen und Funktionen des Dokuments; ein Klick springt hin.",
        "IDM_VIEW_FILEBROWSER": "Zeigt links den Ordner als Arbeitsbereich.",
        "IDM_VIEW_MONITORING": "Überwacht die Datei wie «tail -f»: Was ein anderes Programm anhängt, erscheint sofort; Bearbeiten ist gesperrt.",
        "IDM_VIEW_ALWAYSONTOP": "Hält das Fenster über allen anderen.",
        "IDM_VIEW_POSTIT": "Blendet Werkzeug-, Tab- und Statusleiste aus, wie ein Notizzettel.",
        "IDM_VIEW_DISTRACTIONFREE": "Zeigt nur den Text, bildschirmfüllend und mittig.",
        "IDM_VIEW_FOLDALL": "Klappt alle Blöcke ein.",
        "IDM_VIEW_UNFOLDALL": "Klappt alle Blöcke aus.",
        "IDM_VIEW_CLONE_TO_ANOTHER_VIEW": "Zeigt dasselbe Dokument ein zweites Mal daneben, zum Vergleichen zweier Stellen.",
        // Sprache und Makros
        "IDM_LANG_USER_DLG": "Benutzerdefinierte Sprachen: eine UDL-Datei aus Notepad++ importieren oder den Ordner öffnen.",
        "IDM_MACRO_STARTRECORDINGMACRO": "Beginnt die Aufnahme: Tasten, Text und Befehle werden zum Makro.",
        "IDM_MACRO_STOPRECORDINGMACRO": "Beendet die Aufnahme des Makros.",
        "IDM_MACRO_PLAYBACKRECORDEDMACRO": "Spielt das zuletzt aufgenommene Makro einmal ab. Über ▾ ein gesichertes Makro.",
        "IDM_MACRO_RUNMULTIMACRODLG": "Spielt ein Makro mehrmals ab, oder bis zum Ende der Datei.",
        "IDM_MACRO_SAVECURRENTMACRO": "Sichert das aufgenommene Makro unter einem Namen; es erscheint dann im Menü «Makros».",
        // Werkzeuge, Ausführen, Hilfe
        "IDM_EXECUTE": "Führt einen Befehl in der Shell aus, mit Variablen wie $(FULL_CURRENT_PATH).",
        "IDM_TOOL_MD5_GENERATE": "Berechnet den MD5-Hashwert eines Textes.",
        "IDM_TOOL_SHA256_GENERATE": "Berechnet den SHA-256-Hashwert eines Textes.",
        "IDM_SETTING_PREFERENCE": "Öffnet die Einstellungen.",
    ]
}
