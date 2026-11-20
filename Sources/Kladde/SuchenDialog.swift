import AppKit

/// Der Dialog «Suchen und ersetzen» von Notepad++, gebaut aus FindReplaceDlg.rc:
/// gleiche Bedienelemente an gleicher Stelle (Dialogeinheiten umgerechnet),
/// Reiter Suchen, Ersetzen, In Dateien suchen, Hervorheben; unten die Statuszeile.
final class SuchenDialog: NSWindowController, NSWindowDelegate, NSTabViewDelegate, NSComboBoxDelegate {
    enum Reiter: Int { case suchen, ersetzen, inDateien, markieren }

    static let gemeinsam = SuchenDialog()

    private let reiterLeiste = NSTabView()
    private let inhalt = Flaeche()
    private let status = NSTextField(labelWithString: "")
    private var elemente: [String: NSView] = [:]
    private var reiter = Reiter.suchen
    private var schliessenOrt: NSPoint?
    private let ablage = UserDefaults.standard

    private final class Flaeche: NSView { override var isFlipped: Bool { true } }

    // Dialogeinheiten → Punkte (MS Shell Dlg 8 auf dem Mac etwas grösser).
    private static let sx: CGFloat = 1.62
    private static let sy: CGFloat = 1.78
    private static let oben: CGFloat = 16  // die Reiter von Notepad++ liegen über y = 16

    private static let gemeinsame: Set<String> = [
        "IDFINDWHAT_STATIC", "IDFINDWHAT", "IDC_MODE_STATIC", "IDNORMAL", "IDEXTENDED", "IDREGEXP", "IDREDOTMATCHNL",
        "IDWHOLEWORD", "IDMATCHCASE", "IDCANCEL", "IDC_TRANSPARENT_CHECK", "IDC_TRANSPARENT_GRPBOX",
        "IDC_TRANSPARENT_LOSSFOCUS_RADIO", "IDC_TRANSPARENT_ALWAYS_RADIO", "IDC_PERCENTAGE_SLIDER",
    ]
    private static let jeReiter: [Reiter: Set<String>] = [
        .suchen: ["IDC_BACKWARDDIRECTION", "IDWRAP", "IDOK", "IDCCOUNTALL", "IDC_FINDALL_CURRENTFILE", "IDC_FINDALL_OPENEDFILES",
                  "IDC_REPLACEINSELECTION", "IDC_IN_SELECTION_CHECK"],
        .ersetzen: ["ID_STATICTEXT_REPLACE", "IDREPLACEWITH", "IDD_FINDREPLACE_SWAP_BUTTON", "IDC_BACKWARDDIRECTION", "IDWRAP",
                    "IDOK", "IDREPLACE", "IDREPLACEALL", "IDC_REPLACE_OPENEDFILES", "IDC_REPLACEINSELECTION", "IDC_IN_SELECTION_CHECK"],
        .inDateien: ["ID_STATICTEXT_REPLACE", "IDREPLACEWITH", "IDD_FINDREPLACE_SWAP_BUTTON", "IDD_FINDINFILES_FILTERS_STATIC",
                     "IDD_FINDINFILES_FILTERS_COMBO", "IDC_FIF_FILTER_TIP_STATIC", "IDD_FINDINFILES_DIR_STATIC",
                     "IDD_FINDINFILES_DIR_COMBO", "IDD_FINDINFILES_BROWSE_BUTTON", "IDD_FINDINFILES_SETDIRFROMDOC_BUTTON",
                     "IDD_FINDINFILES_RECURSIVE_CHECK", "IDD_FINDINFILES_INHIDDENDIR_CHECK", "IDD_FINDINFILES_FIND_BUTTON",
                     "IDD_FINDINFILES_REPLACEINFILES"],
        .markieren: ["IDC_MARKLINE_CHECK", "IDC_PURGE_CHECK", "IDCMARKALL", "IDC_CLEAR_ALL", "IDC_COPY_MARKED_TEXT",
                     "IDC_REPLACEINSELECTION", "IDC_IN_SELECTION_CHECK"],
    ]
    private static let standardknopf: [Reiter: String] = [
        .suchen: "IDOK", .ersetzen: "IDOK", .inDateien: "IDD_FINDINFILES_FIND_BUTTON", .markieren: "IDCMARKALL",
    ]

    // MARK: Aufbau

    private init() {
        let d = Oberflaeche.gemeinsam.suchen
        let breite = CGFloat(d.groesse[0]) * Self.sx
        let hoehe = (CGFloat(d.groesse[1]) - Self.oben) * Self.sy + 70
        let fenster = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: breite + 16, height: hoehe),
            styleMask: [.titled, .closable], backing: .buffered, defer: true)
        fenster.isFloatingPanel = true
        fenster.hidesOnDeactivate = true
        fenster.isRestorable = false
        fenster.setFrameAutosaveName("SuchenDialog")
        super.init(window: fenster)
        fenster.delegate = self

        let titel = d.titel
        for (r, schluessel) in [(Reiter.suchen, "titleFind"), (.ersetzen, "titleReplace"), (.inDateien, "titleFindInFiles"), (.markieren, "titleMark")] {
            let item = NSTabViewItem(identifier: r.rawValue)
            item.label = (titel[schluessel] ?? nil) ?? schluessel
            item.view = NSView()
            reiterLeiste.addTabViewItem(item)
        }
        reiterLeiste.delegate = self
        reiterLeiste.translatesAutoresizingMaskIntoConstraints = false
        status.translatesAutoresizingMaskIntoConstraints = false
        status.font = .systemFont(ofSize: 11)
        status.lineBreakMode = .byTruncatingTail
        let wurzel = NSView()
        wurzel.addSubview(reiterLeiste)
        wurzel.addSubview(status)
        NSLayoutConstraint.activate([
            reiterLeiste.topAnchor.constraint(equalTo: wurzel.topAnchor, constant: 6),
            reiterLeiste.leadingAnchor.constraint(equalTo: wurzel.leadingAnchor, constant: 4),
            reiterLeiste.trailingAnchor.constraint(equalTo: wurzel.trailingAnchor, constant: -4),
            status.topAnchor.constraint(equalTo: reiterLeiste.bottomAnchor, constant: 2),
            status.leadingAnchor.constraint(equalTo: wurzel.leadingAnchor, constant: 10),
            status.trailingAnchor.constraint(equalTo: wurzel.trailingAnchor, constant: -10),
            status.bottomAnchor.constraint(equalTo: wurzel.bottomAnchor, constant: -4),
        ])
        fenster.contentView = wurzel
        inhalt.frame = NSRect(x: 0, y: 0, width: breite, height: hoehe - 70)
        baueElemente(d.elemente)
        uebernehme()
        wechsle(.suchen)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private static let weglassen: Set<String> = [
        "IDC_HIGHLIGHT_MODE", "IDC_2_BUTTONS_MODE", "IDC_FINDPREV", "IDC_FINDNEXT", "IDC_REPLACEANDSTOP",
        "IDC_CONFIRMREPLACEOPENDOCS", "IDD_FINDINFILES_PROJECT1_CHECK", "IDD_FINDINFILES_PROJECT2_CHECK",
        "IDD_FINDINFILES_PROJECT3_CHECK", "IDD_FINDINFILES_REPLACEINPROJECTS",
    ]

    private func rechteck(_ e: Oberflaeche.Element, hoehe: CGFloat? = nil) -> NSRect {
        // Notepad++ kürzt den Rahmen «In Auswahl» zur Laufzeit bis vor die Knöpfe (resizeDialogElements).
        let breite = e.id == "IDC_REPLACEINSELECTION" ? min(e.b, 298 - e.x - 6) : e.b
        return NSRect(
            x: CGFloat(e.x) * Self.sx, y: (CGFloat(e.y) - Self.oben) * Self.sy,
            width: CGFloat(breite) * Self.sx, height: hoehe ?? CGFloat(e.h) * Self.sy)
    }

    private func baueElemente(_ liste: [Oberflaeche.Element]) {
        for e in liste where !Self.weglassen.contains(e.id) {
            let text = Mac.text(e.text)
            var ansicht: NSView
            switch e.art {
            case "RTEXT", "LTEXT":
                let f = NSTextField(labelWithString: text)
                f.alignment = e.art == "RTEXT" ? .right : .left
                f.font = .systemFont(ofSize: 12)
                f.lineBreakMode = .byClipping
                if e.id == "IDC_FIF_FILTER_TIP_STATIC" {
                    f.toolTip = "Muster durch Leerzeichen getrennt, etwa «*.swift *.md». Mit «!» ausschliessen: «!*.min.js», Ordner «!\\build»."
                    f.textColor = .linkColor
                }
                ansicht = f
                // Rechtsbündige Beschriftungen dürfen nach links wachsen (Mac-Schrift ist breiter).
                var r = rechteck(e, hoehe: 18).offsetBy(dx: 0, dy: -2)
                if e.art == "RTEXT" { r = NSRect(x: max(2, r.minX - 12), y: r.minY, width: r.maxX - max(2, r.minX - 12), height: r.height) }
                ansicht.frame = r
            case "COMBOBOX":
                let c = NSComboBox()
                c.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
                c.completes = false
                c.delegate = self
                c.numberOfVisibleItems = 10
                ansicht = c
                ansicht.frame = rechteck(e, hoehe: 24).offsetBy(dx: 0, dy: -3)
            case "PUSHBUTTON":
                let k = NSButton(title: text, target: self, action: #selector(gedrueckt(_:)))
                if e.h > 15 {
                    k.bezelStyle = .regularSquare
                    (k.cell as? NSButtonCell)?.wraps = true
                    (k.cell as? NSButtonCell)?.lineBreakMode = .byWordWrapping
                    k.frame = rechteck(e)
                } else {
                    k.bezelStyle = .rounded
                    k.frame = rechteck(e, hoehe: 28).offsetBy(dx: -3, dy: -3).insetBy(dx: -3, dy: 0)
                }
                if text.isEmpty, e.id == "IDD_FINDREPLACE_SWAP_BUTTON" { k.title = "⇅" }
                k.font = .systemFont(ofSize: e.h > 15 ? 11 : 12)
                ansicht = k
            case "CHECKBOX":
                let k = NSButton(checkboxWithTitle: text, target: self, action: #selector(optionGeaendert))
                ansicht = k
                ansicht.frame = rechteck(e, hoehe: 18).offsetBy(dx: 0, dy: -2)
            case "RADIO":
                let k = NSButton(radioButtonWithTitle: text, target: self, action: #selector(radioGeaendert(_:)))
                ansicht = k
                ansicht.frame = rechteck(e, hoehe: 18).offsetBy(dx: 0, dy: -2)
            case "GROUPBOX":
                // Ein Windows-Gruppenrahmen: dünne Linie, Titel auf der oberen Kante.
                let b = NSBox()
                b.boxType = .custom
                b.borderColor = .separatorColor
                b.fillColor = .clear
                b.borderWidth = 1
                b.cornerRadius = 3
                b.titlePosition = .noTitle
                ansicht = b
                ansicht.frame = rechteck(e).insetBy(dx: -2, dy: 0).offsetBy(dx: 0, dy: 4)
                if !text.isEmpty {
                    let t = NSTextField(labelWithString: text)
                    t.font = .systemFont(ofSize: 11)
                    t.drawsBackground = true
                    t.backgroundColor = .windowBackgroundColor
                    t.sizeToFit()
                    t.frame.origin = NSPoint(x: ansicht.frame.minX + 8, y: ansicht.frame.minY - t.frame.height / 2)
                    t.identifier = NSUserInterfaceItemIdentifier(e.id + ".titel")
                    inhalt.addSubview(t)
                    elemente[e.id + ".titel"] = t
                }
            case "SPLITBUTTON":
                let k = NSButton(title: "⇅", target: self, action: #selector(tauschen))
                k.bezelStyle = .rounded
                k.toolTip = Oberflaeche.gemeinsam.suchen.elemente.isEmpty ? nil : "Suchen mit Ersetzen vertauschen"
                ansicht = k
                ansicht.frame = rechteck(e, hoehe: 26)
            case "SLIDER":
                let s = NSSlider(value: 80, minValue: 20, maxValue: 100, target: self, action: #selector(optionGeaendert))
                s.controlSize = .small
                ansicht = s
                ansicht.frame = rechteck(e, hoehe: 18)
            default:
                continue
            }
            ansicht.identifier = NSUserInterfaceItemIdentifier(e.id)
            if let k = ansicht as? NSButton, e.art == "PUSHBUTTON" || e.art == "SPLITBUTTON" { k.identifier = .init(e.id) }
            // Gruppenrahmen hinter die Elemente.
            if e.art == "GROUPBOX" { inhalt.addSubview(ansicht, positioned: .below, relativeTo: nil) } else { inhalt.addSubview(ansicht) }
            elemente[e.id] = ansicht
        }
        (elemente["IDD_FINDREPLACE_SWAP_BUTTON"] as? NSButton)?.action = #selector(tauschen)
        (elemente["IDD_FINDREPLACE_SWAP_BUTTON"] as? NSButton)?.title = "⇅"
    }

    // MARK: Zeigen

    /// Öffnet den Dialog auf einem Reiter; die Auswahl im Editor wird zum Suchtext.
    func zeige(_ r: Reiter, ordner: String? = nil) {
        if let e = Hauptfenster.gemeinsam.aktiv, let text = e.text(e.auswahl), !text.isEmpty, !text.contains("\n"), text.count < 200 {
            var o = SuchZustand.gemeinsam.optionen
            o.text = text
            SuchZustand.gemeinsam.optionen = o
        }
        if let ordner { (elemente["IDD_FINDINFILES_DIR_COMBO"] as? NSComboBox)?.stringValue = ordner }
        uebernehme()
        wechsle(r)
        if window?.isVisible != true, let haupt = Hauptfenster.gemeinsam.window {
            let f = window!.frame
            window?.setFrameOrigin(NSPoint(x: haupt.frame.midX - f.width / 2, y: haupt.frame.midY - f.height / 2 + 60))
        }
        showWindow(nil)
        window?.makeFirstResponder(elemente["IDFINDWHAT"])
    }

    private func wechsle(_ r: Reiter) {
        reiter = r
        if reiterLeiste.selectedTabViewItem.map { reiterLeiste.indexOfTabViewItem($0) } != r.rawValue { reiterLeiste.selectTabViewItem(at: r.rawValue) }
        let item = reiterLeiste.tabViewItem(at: r.rawValue)
        inhalt.removeFromSuperview()
        item.view?.addSubview(inhalt)
        // Wie Notepad++: Im Reiter «In Dateien suchen» rückt «Schließen» unter «Ersetzen in Dateien».
        if let schliessen = elemente["IDCANCEL"] {
            if schliessenOrt == nil { schliessenOrt = schliessen.frame.origin }
            if r == .inDateien, let oben = elemente["IDD_FINDINFILES_REPLACEINFILES"] {
                schliessen.setFrameOrigin(NSPoint(x: schliessenOrt!.x, y: oben.frame.maxY + 6))
            } else {
                schliessen.setFrameOrigin(schliessenOrt!)
            }
        }
        let sichtbar = Self.gemeinsame.union(Self.jeReiter[r] ?? [])
        for (id, v) in elemente { v.isHidden = !sichtbar.contains(id.replacingOccurrences(of: ".titel", with: "")) }
        let titel = Oberflaeche.gemeinsam.suchen.titel
        window?.title = (titel[["titleFind", "titleReplace", "titleFindInFiles", "titleMark"][r.rawValue]] ?? nil) ?? ""
        if let k = elemente[Self.standardknopf[r] ?? ""] as? NSButton { window?.defaultButtonCell = k.cell as? NSButtonCell }
        aktualisiereRegexAbhaengig()
    }

    func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        guard let i = tabViewItem?.identifier as? Int, let r = Reiter(rawValue: i), r != reiter else { return }
        wechsle(r)
    }

    // MARK: Zustand

    private func kombi(_ id: String) -> NSComboBox? { elemente[id] as? NSComboBox }
    private func haken(_ id: String) -> Bool { (elemente[id] as? NSButton)?.state == .on }
    private func setzeHaken(_ id: String, _ an: Bool) { (elemente[id] as? NSButton)?.state = an ? .on : .off }

    private func uebernehme() {
        let o = SuchZustand.gemeinsam.optionen
        kombi("IDFINDWHAT")?.stringValue = o.text
        kombi("IDREPLACEWITH")?.stringValue = o.ersetzung
        for (id, schluessel) in [("IDFINDWHAT", "VerlaufSuchen"), ("IDREPLACEWITH", "VerlaufErsetzen"),
                                 ("IDD_FINDINFILES_FILTERS_COMBO", "VerlaufFilter"), ("IDD_FINDINFILES_DIR_COMBO", "VerlaufOrdner")] {
            kombi(id)?.removeAllItems()
            kombi(id)?.addItems(withObjectValues: ablage.stringArray(forKey: schluessel) ?? [])
        }
        if kombi("IDD_FINDINFILES_FILTERS_COMBO")?.stringValue.isEmpty ?? false {
            kombi("IDD_FINDINFILES_FILTERS_COMBO")?.stringValue = ablage.string(forKey: "DateiSucheFilter") ?? "*.*"
        }
        if kombi("IDD_FINDINFILES_DIR_COMBO")?.stringValue.isEmpty ?? false {
            kombi("IDD_FINDINFILES_DIR_COMBO")?.stringValue = ablage.string(forKey: "DateiSucheOrdner")
                ?? Hauptfenster.gemeinsam.aktivesDokument?.fileURL?.deletingLastPathComponent().path ?? NSHomeDirectory()
        }
        setzeHaken("IDWHOLEWORD", o.ganzesWort)
        setzeHaken("IDMATCHCASE", o.grossKlein)
        setzeHaken("IDWRAP", o.umbruch)
        setzeHaken("IDREDOTMATCHNL", o.punktFindetZeilenende)
        setzeHaken("IDNORMAL", o.modus == .normal)
        setzeHaken("IDEXTENDED", o.modus == .erweitert)
        setzeHaken("IDREGEXP", o.modus == .regulaer)
        setzeHaken("IDD_FINDINFILES_RECURSIVE_CHECK", ablage.object(forKey: "DateiSucheUnterordner") as? Bool ?? true)
        setzeHaken("IDD_FINDINFILES_INHIDDENDIR_CHECK", ablage.bool(forKey: "DateiSucheVersteckte"))
        setzeHaken("IDC_PURGE_CHECK", ablage.object(forKey: "SuchenLeeren") as? Bool ?? true)
        setzeHaken("IDC_TRANSPARENT_LOSSFOCUS_RADIO", true)
        aktualisiereRegexAbhaengig()
    }

    /// Text und Schalter in den gemeinsamen Suchzustand.
    private func uebertrage() {
        var o = SuchZustand.gemeinsam.optionen
        o.text = kombi("IDFINDWHAT")?.stringValue ?? o.text
        o.ersetzung = kombi("IDREPLACEWITH")?.stringValue ?? o.ersetzung
        o.ganzesWort = haken("IDWHOLEWORD")
        o.grossKlein = haken("IDMATCHCASE")
        o.umbruch = haken("IDWRAP")
        o.punktFindetZeilenende = haken("IDREDOTMATCHNL")
        o.modus = haken("IDREGEXP") ? .regulaer : haken("IDEXTENDED") ? .erweitert : .normal
        SuchZustand.gemeinsam.optionen = o
        ablage.set(haken("IDD_FINDINFILES_RECURSIVE_CHECK"), forKey: "DateiSucheUnterordner")
        ablage.set(haken("IDD_FINDINFILES_INHIDDENDIR_CHECK"), forKey: "DateiSucheVersteckte")
        ablage.set(haken("IDC_PURGE_CHECK"), forKey: "SuchenLeeren")
    }

    private func merke(_ id: String, _ schluessel: String) {
        guard let wert = kombi(id)?.stringValue, !wert.isEmpty else { return }
        var liste = ablage.stringArray(forKey: schluessel) ?? []
        liste.removeAll { $0 == wert }
        liste.insert(wert, at: 0)
        ablage.set(Array(liste.prefix(10)), forKey: schluessel)
        kombi(id)?.removeAllItems()
        kombi(id)?.addItems(withObjectValues: Array(liste.prefix(10)))
    }

    private func aktualisiereRegexAbhaengig() {
        (elemente["IDREDOTMATCHNL"] as? NSButton)?.isEnabled = haken("IDREGEXP")
        // «Nur ganze Wörter» geht in Notepad++ nicht mit regulären Ausdrücken.
        (elemente["IDWHOLEWORD"] as? NSButton)?.isEnabled = !haken("IDREGEXP")
        let ein = haken("IDC_TRANSPARENT_CHECK")
        for id in ["IDC_TRANSPARENT_LOSSFOCUS_RADIO", "IDC_TRANSPARENT_ALWAYS_RADIO", "IDC_PERCENTAGE_SLIDER"] {
            (elemente[id] as? NSControl)?.isEnabled = ein
        }
        setzeDurchsicht(aktiv: window?.isKeyWindow ?? true)
    }

    @objc private func optionGeaendert() {
        uebertrage()
        aktualisiereRegexAbhaengig()
    }

    @objc private func radioGeaendert(_ sender: NSButton) {
        let gruppen = [["IDNORMAL", "IDEXTENDED", "IDREGEXP"], ["IDC_TRANSPARENT_LOSSFOCUS_RADIO", "IDC_TRANSPARENT_ALWAYS_RADIO"]]
        guard let id = sender.identifier?.rawValue, let gruppe = gruppen.first(where: { $0.contains(id) }) else { return }
        for g in gruppe { setzeHaken(g, g == id) }
        optionGeaendert()
    }

    func controlTextDidChange(_ obj: Notification) { uebertrage() }
    func comboBoxSelectionDidChange(_ notification: Notification) { DispatchQueue.main.async { self.uebertrage() } }

    @objc private func tauschen() {
        guard let a = kombi("IDFINDWHAT"), let b = kombi("IDREPLACEWITH") else { return }
        (a.stringValue, b.stringValue) = (b.stringValue, a.stringValue)
        uebertrage()
    }

    // MARK: Durchsichtigkeit

    private func setzeDurchsicht(aktiv: Bool) {
        guard haken("IDC_TRANSPARENT_CHECK") else { window?.alphaValue = 1; return }
        let wert = CGFloat((elemente["IDC_PERCENTAGE_SLIDER"] as? NSSlider)?.doubleValue ?? 80) / 100
        window?.alphaValue = haken("IDC_TRANSPARENT_ALWAYS_RADIO") || !aktiv ? wert : 1
    }

    func windowDidBecomeKey(_ notification: Notification) { setzeDurchsicht(aktiv: true) }
    func windowDidResignKey(_ notification: Notification) { setzeDurchsicht(aktiv: false) }

    // MARK: Knöpfe

    func zeigeStatus(_ antwort: Suchaktion.Antwort) {
        status.stringValue = antwort.text
        status.textColor = antwort.fehler ? .systemRed : .systemBlue
    }

    @objc private func gedrueckt(_ sender: NSButton) {
        uebertrage()
        merke("IDFINDWHAT", "VerlaufSuchen")
        let haupt = Hauptfenster.gemeinsam
        guard let id = sender.identifier?.rawValue else { return }
        let nurAuswahl = haken("IDC_IN_SELECTION_CHECK")
        let e = haupt.aktiv
        switch id {
        case "IDOK":
            if let e { zeigeStatus(Suchaktion.weiter(in: e, rueckwaerts: haken("IDC_BACKWARDDIRECTION"))) }
        case "IDCCOUNTALL":
            guard let e, let muster = try? SuchZustand.gemeinsam.muster() else { return }
            let n = muster.alle(in: e.suchtext, bereich: nurAuswahl ? e.auswahl : nil).count
            zeigeStatus(Suchaktion.Antwort(text: "Zählen: \(n) Treffer", fehler: n == 0))
        case "IDC_FINDALL_CURRENTFILE":
            if let d = haupt.aktivesDokument { zeigeStatus(Suchergebnisse.gemeinsam.findeAlle(in: [d])) }
        case "IDC_FINDALL_OPENEDFILES": zeigeStatus(Suchergebnisse.gemeinsam.findeAlle(in: haupt.tabs))
        case "IDREPLACE":
            merke("IDREPLACEWITH", "VerlaufErsetzen")
            if let e { zeigeStatus(Suchaktion.ersetzen(in: e)) }
        case "IDREPLACEALL":
            merke("IDREPLACEWITH", "VerlaufErsetzen")
            if let e { zeigeStatus(Suchaktion.alleErsetzen(in: e, nurAuswahl: nurAuswahl)) }
        case "IDC_REPLACE_OPENEDFILES":
            merke("IDREPLACEWITH", "VerlaufErsetzen")
            zeigeStatus(Suchaktion.alleErsetzenInOffenen())
        case "IDD_FINDINFILES_FIND_BUTTON": starteDateisuche(ersetzen: false)
        case "IDD_FINDINFILES_REPLACEINFILES":
            merke("IDREPLACEWITH", "VerlaufErsetzen")
            starteDateisuche(ersetzen: true)
        case "IDD_FINDINFILES_BROWSE_BUTTON":
            let wahl = NSOpenPanel()
            wahl.canChooseDirectories = true
            wahl.canChooseFiles = false
            wahl.beginSheetModal(for: window!) { [weak self] a in
                if a == .OK, let u = wahl.url { self?.kombi("IDD_FINDINFILES_DIR_COMBO")?.stringValue = u.path }
            }
        case "IDD_FINDINFILES_SETDIRFROMDOC_BUTTON":
            if let u = haupt.aktivesDokument?.fileURL { kombi("IDD_FINDINFILES_DIR_COMBO")?.stringValue = u.deletingLastPathComponent().path }
        case "IDCMARKALL":
            guard let e else { return }
            zeigeStatus(Suchaktion.alleMarkieren(
                in: e, nurAuswahl: nurAuswahl, lesezeichen: haken("IDC_MARKLINE_CHECK"), leeren: haken("IDC_PURGE_CHECK")))
        case "IDC_CLEAR_ALL":
            e?.loescheMarkierungen(Editor.indikatorMarkiert)
            status.stringValue = ""
        case "IDC_COPY_MARKED_TEXT":
            guard let e else { return }
            let t = e.markierterText([Editor.indikatorMarkiert])
            if t.isEmpty { NSSound.beep() } else { Werkzeuge.zwischenablage(t) }
        case "IDCANCEL": close()
        default: break
        }
    }

    /// In Dateien suchen oder ersetzen; `bestaetigt` und `fertig` für die Selbstprüfung.
    func starteDateisuche(ersetzen: Bool, bestaetigt: Bool = false, fertig: ((String) -> Void)? = nil) {
        uebertrage()
        merke("IDD_FINDINFILES_FILTERS_COMBO", "VerlaufFilter")
        merke("IDD_FINDINFILES_DIR_COMBO", "VerlaufOrdner")
        let auftrag = Dateisuche.Auftrag(
            ordner: kombi("IDD_FINDINFILES_DIR_COMBO")?.stringValue ?? "",
            filter: kombi("IDD_FINDINFILES_FILTERS_COMBO")?.stringValue ?? "",
            unterordner: haken("IDD_FINDINFILES_RECURSIVE_CHECK"), versteckte: haken("IDD_FINDINFILES_INHIDDENDIR_CHECK"))
        ablage.set(auftrag.ordner, forKey: "DateiSucheOrdner")
        ablage.set(auftrag.filter, forKey: "DateiSucheFilter")
        Dateisuche.gemeinsam.starte(
            auftrag, ersetzen: ersetzen, bestaetigt: bestaetigt, fenster: window ?? Hauptfenster.gemeinsam.window,
            meldung: { [weak self] text, fehler in self?.zeigeStatus(Suchaktion.Antwort(text: text, fehler: fehler)) },
            fertig: fertig)
    }

    /// Für die Selbstprüfung.
    func setze(ordner: String, filter: String) {
        kombi("IDD_FINDINFILES_DIR_COMBO")?.stringValue = ordner
        kombi("IDD_FINDINFILES_FILTERS_COMBO")?.stringValue = filter
    }
}
