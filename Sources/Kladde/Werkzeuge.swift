import AppKit
import CryptoKit
import ScintillaBruecke

/// Was hinter einzelnen Menübefehlen steckt und nicht in den Editor gehört.
enum Werkzeuge {
    static func zwischenablage(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static var architektur: String {
        #if arch(arm64)
            return "Apple Silicon (arm64)"
        #else
            return "Intel (x86_64)"
        #endif
    }

    /// Terminal in einem Ordner (Notepad++: Eingabeaufforderung).
    static func terminal(in ordner: URL) {
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else { return }
        NSWorkspace.shared.open([ordner], withApplicationAt: terminal, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Firefox, Chrome oder Edge, wenn installiert (Ansicht → Aktuelle Datei betrachten in).
    static func browser(_ id: String) -> URL? {
        let kennung: String
        switch id.replacingOccurrences(of: "IDM_", with: "") {
        case "VIEW_IN_FIREFOX": kennung = "org.mozilla.firefox"
        case "VIEW_IN_CHROME": kennung = "com.google.Chrome"
        case "VIEW_IN_EDGE": kennung = "com.microsoft.edgemac"
        default: return nil
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: kennung)
    }

    // MARK: Drucken

    /// Druckt den Text in der Schrift des Editors, mit Kopfzeile (Dateiname) wie Notepad++.
    static func drucke(_ e: Editor, titel: String, mitDialog: Bool) {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isVerticallyCentered = false
        let breite = info.paperSize.width - info.leftMargin - info.rightMargin
        let ansicht = NSTextView(frame: NSRect(x: 0, y: 0, width: breite, height: 100))
        let schriftart = String(cString: e.nachrichtText(SCI_STYLEGETFONT, Int(STYLE_DEFAULT)))
        let schrift = NSFont(name: schriftart, size: 10) ?? .monospacedSystemFont(ofSize: 10, weight: .regular)
        ansicht.textStorage?.setAttributedString(NSAttributedString(
            string: String(decoding: e.utf8, as: UTF8.self), attributes: [.font: schrift, .foregroundColor: NSColor.black]))
        ansicht.sizeToFit()
        let lauf = NSPrintOperation(view: ansicht, printInfo: info)
        lauf.jobTitle = titel
        lauf.showsPrintPanel = mitDialog
        lauf.showsProgressPanel = mitDialog
        if let fenster = Hauptfenster.gemeinsam.window {
            lauf.runModal(for: fenster, delegate: nil, didRun: nil, contextInfo: nil)
        } else {
            lauf.run()
        }
    }

    // MARK: Hashwerte

    private static func wert(_ art: String, _ daten: Data) -> String {
        let d: any Sequence<UInt8>
        switch art {
        case "MD5": d = Insecure.MD5.hash(data: daten)
        case "SHA1": d = Insecure.SHA1.hash(data: daten)
        case "SHA256": d = SHA256.hash(data: daten)
        default: d = SHA512.hash(data: daten)
        }
        return d.map { String(format: "%02x", $0) }.joined()
    }

    /// Werkzeuge → MD5/SHA-1/SHA-256/SHA-512: aus Text, aus Dateien oder aus der Auswahl in die Zwischenablage.
    static func hash(_ voll: String, editor: Editor?, fenster: NSWindow?) {
        let id = voll.replacingOccurrences(of: "IDM_TOOL_", with: "")
        guard let art = id.split(separator: "_").first.map(String.init) else { return }
        let o = Oberflaeche.gemeinsam
        let anzeige = ["MD5": "MD5", "SHA1": "SHA1", "SHA256": "SHA256", "SHA512": "SHA512"][art]!
        if id.hasSuffix("GENERATEINTOCLIPBOARD") {
            guard let e = editor, let text = e.text(e.auswahl), !text.isEmpty else { return NSSound.beep() }
            // Je Zeile ein Wert, wie Notepad++.
            let zeilen = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            zwischenablage(zeilen.map { wert(art, Data($0.utf8)) }.joined(separator: "\n"))
            return
        }
        guard let fenster else { return }
        if id.hasSuffix("GENERATEFROMFILE") {
            let wahl = NSOpenPanel()
            wahl.allowsMultipleSelection = true
            wahl.title = o.texte["\(anzeige == "SHA1" ? "SHA1" : anzeige)FromFilesDlg.title"] ?? "\(anzeige) aus Dateien"
            wahl.beginSheetModal(for: fenster) { antwort in
                guard antwort == .OK else { return }
                let zeilen = wahl.urls.map { u in
                    ((try? Data(contentsOf: u)).map { wert(art, $0) } ?? "–") + "  " + u.lastPathComponent
                }
                zeige(zeilen.joined(separator: "\n"), titel: wahl.title ?? "", fenster: fenster)
            }
            return
        }
        // Aus eingegebenem Text.
        let frage = NSAlert()
        frage.messageText = o.texte["\(anzeige)FromTextDlg.title"] ?? "\(anzeige)"
        let eingabe = NSTextView(frame: NSRect(x: 0, y: 0, width: 420, height: 90))
        eingabe.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        eingabe.isRichText = false
        let rollen = NSScrollView(frame: eingabe.frame)
        rollen.documentView = eingabe
        rollen.hasVerticalScroller = true
        rollen.borderType = .bezelBorder
        frage.accessoryView = rollen
        frage.addButton(withTitle: "Berechnen")
        frage.addButton(withTitle: "Abbrechen")
        frage.window.initialFirstResponder = eingabe
        frage.beginSheetModal(for: fenster) { antwort in
            guard antwort == .alertFirstButtonReturn else { return }
            let zeilen = eingabe.string.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            let ergebnis = zeilen.map { wert(art, Data($0.utf8)) }.joined(separator: "\n")
            DispatchQueue.main.async { zeige(ergebnis, titel: frage.messageText, fenster: fenster) }
        }
    }

    private static func zeige(_ text: String, titel: String, fenster: NSWindow) {
        let hinweis = NSAlert()
        hinweis.messageText = titel
        hinweis.informativeText = text
        hinweis.addButton(withTitle: "In die Zwischenablage")
        hinweis.addButton(withTitle: "Schliessen")
        hinweis.beginSheetModal(for: fenster) { if $0 == .alertFirstButtonReturn { zwischenablage(text) } }
    }

    // MARK: Ausführen

    /// Ausführen → Externes Programm ausführen: ein Befehl für die Shell, mit den
    /// Variablen von Notepad++ ($(FULL_CURRENT_PATH), $(CURRENT_DIRECTORY) …).
    static func ausfuehren(dokument: Dokument?, editor: Editor?, fenster: NSWindow?) {
        guard let fenster else { return }
        let o = Oberflaeche.gemeinsam
        let frage = NSAlert()
        frage.messageText = o.texte["Run.title"] ?? "Ausführen"
        frage.informativeText = "Befehl für die Shell. Variablen: $(FULL_CURRENT_PATH), $(CURRENT_DIRECTORY), $(FILE_NAME), $(NAME_PART), $(EXT_PART), $(CURRENT_WORD), $(CURRENT_LINE)"
        let feld = NSTextField(string: UserDefaults.standard.string(forKey: "LetzterBefehl") ?? "open \"$(FULL_CURRENT_PATH)\"")
        feld.frame = NSRect(x: 0, y: 0, width: 420, height: 24)
        frage.accessoryView = feld
        frage.addButton(withTitle: o.texte["Run.1"] ?? "Ausführen")
        frage.addButton(withTitle: o.texte["Run.2"] ?? "Abbrechen")
        frage.window.initialFirstResponder = feld
        frage.beginSheetModal(for: fenster) { antwort in
            guard antwort == .alertFirstButtonReturn else { return }
            UserDefaults.standard.set(feld.stringValue, forKey: "LetzterBefehl")
            var befehl = feld.stringValue
            let url = dokument?.fileURL
            var wort = ""
            if let e = editor {
                let m = e.marke
                wort = e.auswahl.isEmpty
                    ? e.text(e.nachricht(SCI_WORDSTARTPOSITION, m, 1)..<e.nachricht(SCI_WORDENDPOSITION, m, 1)) ?? ""
                    : e.text(e.auswahl) ?? ""
            }
            let variablen: [String: String] = [
                "FULL_CURRENT_PATH": url?.path ?? "", "CURRENT_DIRECTORY": url?.deletingLastPathComponent().path ?? "",
                "FILE_NAME": url?.lastPathComponent ?? (dokument?.tabTitel ?? ""),
                "NAME_PART": url?.deletingPathExtension().lastPathComponent ?? "", "EXT_PART": url.map { "." + $0.pathExtension } ?? "",
                "CURRENT_WORD": wort, "CURRENT_LINE": "\(editor?.aktuelleZeile ?? 1)",
            ]
            for (n, w) in variablen { befehl = befehl.replacingOccurrences(of: "$(\(n))", with: w) }
            let prozess = Process()
            prozess.executableURL = URL(fileURLWithPath: "/bin/zsh")
            prozess.arguments = ["-lc", befehl]
            if let ordner = url?.deletingLastPathComponent() { prozess.currentDirectoryURL = ordner }
            do { try prozess.run() } catch { NSApp.presentError(error) }
        }
    }
}

extension Editor {
    /// Text, den Scintilla in einen Puffer schreibt (etwa SCI_STYLEGETFONT).
    func nachrichtText(_ n: Int32, _ w: Int) -> [CChar] {
        let laenge = nachricht(n, w, 0)
        var puffer = [CChar](repeating: 0, count: max(1, laenge + 1))
        puffer.withUnsafeMutableBufferPointer { _ = nachricht(n, w, Int(bitPattern: $0.baseAddress)) }
        return puffer
    }
}

// MARK: - Sonderansichten

extension Hauptfenster {
    private static var postItZustand = false
    private static var freiZustand = false
    private static var beginn: (stelle: Int, spalte: Bool)?

    /// Ansicht → Post-it: nur der Text, randlos und immer im Vordergrund.
    var postIt: Bool {
        get { Self.postItZustand }
        set {
            Self.postItZustand = newValue
            for v in [werkzeugleiste, tableiste, statusleiste] as [NSView] { v.isHidden = newValue }
            window?.level = newValue ? .floating : .normal
        }
    }

    /// Ansicht → Ablenkungsfreier Modus: Vollbild, nur der Text.
    var ablenkungsfrei: Bool {
        get { Self.freiZustand }
        set {
            Self.freiZustand = newValue
            for v in [werkzeugleiste, tableiste, statusleiste] as [NSView] { v.isHidden = newValue }
            if (window?.styleMask.contains(.fullScreen) ?? false) != newValue { window?.toggleFullScreen(nil) }
        }
    }

    var beginnAuswahl: Int? { Self.beginn?.stelle }
    var beginnSpalte: Bool { Self.beginn?.spalte ?? false }

    /// Bearbeiten → Auswahl beginnen/beenden: erster Aufruf merkt die Stelle,
    /// der zweite wählt bis zur Marke aus (im Spaltenmodus als Rechteck).
    func beginnEndeAuswahl(spalte: Bool) {
        guard let e = aktiv else { return }
        if let b = Self.beginn {
            Self.beginn = nil
            e.nachricht(SCI_SETSELECTIONMODE, Int(b.spalte ? SC_SEL_RECTANGLE : SC_SEL_STREAM))
            e.nachricht(SCI_SETANCHOR, b.stelle)
            e.nachricht(SCI_SETCURRENTPOS, e.marke)
        } else {
            Self.beginn = (e.marke, spalte)
        }
    }
}

// MARK: - Überwachung (tail -f)

extension Dokument {
    private static var waechter: [ObjectIdentifier: DispatchSourceFileSystemObject] = [:]

    /// Ansicht → Überwachen (tail -f): Ändert sich die Datei, lädt Kladde sie neu
    /// und springt ans Ende; solange ist das Dokument schreibgeschützt.
    var ueberwacht: Bool {
        get { Self.waechter[ObjectIdentifier(self)] != nil }
        set {
            let schluessel = ObjectIdentifier(self)
            Self.waechter[schluessel]?.cancel()
            Self.waechter[schluessel] = nil
            schreibgeschuetzt = newValue
            guard newValue, let url = fileURL else { return }
            let fd = Darwin.open(url.path, O_EVTONLY)
            guard fd >= 0 else { return }
            let quelle = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend], queue: .main)
            quelle.setEventHandler { [weak self] in self?.ladeUeberwacht() }
            quelle.setCancelHandler { Darwin.close(fd) }
            quelle.resume()
            Self.waechter[schluessel] = quelle
            ladeUeberwacht()
        }
    }

    private func ladeUeberwacht() {
        guard let url = fileURL, let daten = try? Data(contentsOf: url), let e = editor else { return }
        let datei = Textdatei(daten: daten, als: self.datei.kodierung)
        e.nachricht(SCI_SETREADONLY, 0)
        e.lade(datei)
        e.nachricht(SCI_SETREADONLY, 1)
        e.nachricht(SCI_DOCUMENTEND)
        updateChangeCount(.changeCleared)
    }
}
