import AppKit
import ScintillaBruecke

/// Das Fenster eines Dokuments. Mehrere Dokumente landen als Tabs im selben
/// Fenster (tabbingMode), die Tableiste zeichnet macOS. Oben sitzt bei Bedarf
/// die Suchleiste, unten die Statusleiste; dazwischen der Editor, auf Wunsch
/// zweimal (geteilte Ansicht).
final class EditorFenster: NSWindowController, NSMenuItemValidation {
    /// Die Hauptansicht; sie gehört dem Dokument.
    let editor: Editor
    /// Die zweite Ansicht bei geteilter Ansicht.
    private var zweiter: Editor?
    /// Wer zuletzt den Fokus hatte; auf ihn wirken Menü, Suchleiste und Statusleiste.
    private weak var zuletztAktiv: Editor?

    private var suchleiste: Suchleiste!
    private let statusleiste = Statusleiste()
    /// Hält den Editor oder die geteilte Ansicht.
    private let inhalt = NSView()
    private var teilung: NSSplitView?
    private var erscheinung: NSKeyValueObservation?
    /// Editorbereich links, Funktionsliste rechts (wenn eingeschaltet).
    private let rumpf = NSSplitView()
    private let funktionsliste = FunktionslistenAnsicht()
    private var einstellungen: NSObjectProtocol?
    private var ausgewertet = -1
    private var auswertungGeplant = false

    var aktiv: Editor { zuletztAktiv ?? editor }

    init(editor: Editor) {
        self.editor = editor
        let fenster = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        fenster.tabbingMode = .preferred
        fenster.tabbingIdentifier = "Kladde"
        fenster.minSize = NSSize(width: 480, height: 200)
        super.init(window: fenster)

        suchleiste = Suchleiste(editor: { [unowned self] in self.aktiv })
        suchleiste.schliessen = { [weak self] in self?.schliesseSuche() }
        statusleiste.quelle = { [weak self] in
            guard let self else { return nil }
            return (self.aktiv, self.document as? Dokument)
        }

        rumpf.isVertical = true
        rumpf.dividerStyle = .thin
        rumpf.addArrangedSubview(inhalt)
        let stapel = NSStackView(views: [suchleiste, rumpf, statusleiste])
        stapel.orientation = .vertical
        stapel.spacing = 0
        stapel.alignment = .leading
        stapel.distribution = .fill
        for ansicht in [suchleiste!, rumpf, statusleiste] as [NSView] {
            ansicht.translatesAutoresizingMaskIntoConstraints = false
            ansicht.widthAnchor.constraint(equalTo: stapel.widthAnchor).isActive = true
        }
        rumpf.setContentHuggingPriority(.init(1), for: .vertical)
        rumpf.setContentCompressionResistancePriority(.init(1), for: .vertical)
        suchleiste.isHidden = true
        fenster.contentView = stapel
        fuelle(mit: editor.ansicht)
        melde(editor)

        fenster.center()
        fenster.setFrameAutosaveName("Editor")
        // Was beim Start wieder aufgeht, bestimmt die eigene Sitzung (Sitzung.swift);
        // die Wiederherstellung von macOS würde Dateien doppelt öffnen.
        fenster.isRestorable = false
        fenster.makeFirstResponder(editor.ansicht.content())

        // Wechselt macOS zwischen hell und dunkel, wechseln die Editoren mit.
        erscheinung = NSApp.observe(\.effectiveAppearance) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.editor.wendeDarstellungAn()
                self?.zweiter?.wendeDarstellungAn()
            }
        }
        editor.spracheGewechselt = { [weak self] sprache in
            self?.zweiter?.uebernimmSprache(sprache)
            self?.ausgewertet = -1
            self?.planeFunktionsliste()
        }
        funktionsliste.springe = { [weak self] stelle in
            guard let self else { return }
            self.aktiv.waehleAus(stelle..<stelle)
            self.aktiv.ansicht.message(UInt32(SCI_VERTICALCENTRECARET), wParam: 0, lParam: 0)
            self.window?.makeFirstResponder(self.aktiv.ansicht.content())
        }
        einstellungen = NotificationCenter.default.addObserver(
            forName: Einstellungen.geaendert, object: nil, queue: .main
        ) { [weak self] _ in self?.zeigeFunktionsliste(Einstellungen.funktionslisteSichtbar) }
        zeigeFunktionsliste(Einstellungen.funktionslisteSichtbar)
        DispatchQueue.main.async { [weak self] in self?.statusleiste.aktualisiere() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("EditorFenster entsteht nur im Code") }

    /// Statusleiste und Fokus hören auf diesen Editor.
    deinit {
        if let einstellungen { NotificationCenter.default.removeObserver(einstellungen) }
    }

    // MARK: Funktionsliste

    private func zeigeFunktionsliste(_ an: Bool) {
        let sichtbar = funktionsliste.superview != nil
        guard an != sichtbar else { return }
        if an {
            rumpf.addArrangedSubview(funktionsliste)
            rumpf.setHoldingPriority(.init(260), forSubviewAt: 1)
            rumpf.layoutSubtreeIfNeeded()
            rumpf.setPosition(max(240, rumpf.bounds.width - 240), ofDividerAt: 0)
            ausgewertet = -1
            planeFunktionsliste()
        } else {
            funktionsliste.removeFromSuperview()
        }
    }

    /// Wertet höchstens einmal je halbe Sekunde aus, und nur nach Änderungen.
    private func planeFunktionsliste() {
        guard funktionsliste.superview != nil, !auswertungGeplant, ausgewertet != editor.aenderungszahl else { return }
        auswertungGeplant = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            self.auswertungGeplant = false
            self.ausgewertet = self.editor.aenderungszahl
            self.funktionsliste.aktualisiere(text: self.editor.suchtext, sprache: self.editor.sprache)
        }
    }

    /// Für die Selbstprüfung.
    var funktionslisteNamen: [String] { funktionsliste.namen }

    @objc func funktionslisteUmschalten(_ sender: Any?) {
        Einstellungen.funktionslisteSichtbar.toggle()
    }

    private func melde(_ e: Editor) {
        e.zustandGeaendert = { [weak self] in
            self?.statusleiste.aktualisiere()
            self?.planeFunktionsliste()
        }
        e.fokussiert = { [weak self, weak e] in
            self?.zuletztAktiv = e
            self?.statusleiste.aktualisiere()
        }
    }

    private func fuelle(mit ansicht: NSView) {
        inhalt.subviews.forEach { $0.removeFromSuperview() }
        ansicht.translatesAutoresizingMaskIntoConstraints = false
        inhalt.addSubview(ansicht)
        NSLayoutConstraint.activate([
            ansicht.leadingAnchor.constraint(equalTo: inhalt.leadingAnchor),
            ansicht.trailingAnchor.constraint(equalTo: inhalt.trailingAnchor),
            ansicht.topAnchor.constraint(equalTo: inhalt.topAnchor),
            ansicht.bottomAnchor.constraint(equalTo: inhalt.bottomAnchor),
        ])
    }

    // MARK: Geteilte Ansicht

    /// 0 keine, 1 übereinander, 2 nebeneinander. Beide Ansichten zeigen
    /// denselben Text; Widerrufen, Lesezeichen und Markierungen gelten für beide.
    @objc func geteilteAnsicht(_ sender: NSMenuItem) { teile(sender.tag) }

    func teile(_ art: Int) {
        guard art != 0 else {
            if let z = zweiter {
                z.ansicht.removeFromSuperview()
                if zuletztAktiv === z { zuletztAktiv = editor }
                zweiter = nil
            }
            teilung = nil
            fuelle(mit: editor.ansicht)
            window?.makeFirstResponder(editor.ansicht.content())
            statusleiste.aktualisiere()
            return
        }
        let z = zweiter ?? Editor(teiltMit: editor)
        if zweiter == nil {
            zweiter = z
            melde(z)
            z.position = editor.position
            z.ersteZeile = editor.ersteZeile
        }
        let split = NSSplitView()
        split.isVertical = art == 2
        split.dividerStyle = .thin
        editor.ansicht.removeFromSuperview()
        z.ansicht.removeFromSuperview()
        editor.ansicht.translatesAutoresizingMaskIntoConstraints = true
        z.ansicht.translatesAutoresizingMaskIntoConstraints = true
        split.addArrangedSubview(editor.ansicht)
        split.addArrangedSubview(z.ansicht)
        teilung = split
        fuelle(mit: split)
        split.layoutSubtreeIfNeeded()
        let ganz = split.isVertical ? split.bounds.width : split.bounds.height
        split.setPosition(ganz / 2, ofDividerAt: 0)
    }

    var geteilt: Int { teilung == nil ? 0 : (teilung!.isVertical ? 2 : 1) }

    // MARK: Menü «Darstellung»

    @objc func zeilenumbruchUmschalten(_ sender: Any?) {
        let an = !editor.umbruch
        editor.umbruch = an
        zweiter?.umbruch = an
    }
    @objc func schriftGroesser(_ sender: Any?) { aktiv.vergroessere() }
    @objc func schriftKleiner(_ sender: Any?) { aktiv.verkleinere() }
    @objc func schriftOriginal(_ sender: Any?) { aktiv.originalgroesse() }
    @objc func allesEinklappen(_ sender: Any?) { aktiv.klappeAlles(ein: true) }
    @objc func allesAusklappen(_ sender: Any?) { aktiv.klappeAlles(ein: false) }

    // MARK: Menü «Bearbeiten»

    @objc func dupliziere(_ sender: Any?) { aktiv.dupliziere() }
    @objc func loescheZeilen(_ sender: Any?) { aktiv.loescheZeilen() }
    @objc func zeilenHoch(_ sender: Any?) { aktiv.zeilenHoch() }
    @objc func zeilenRunter(_ sender: Any?) { aktiv.zeilenRunter() }
    @objc func verbindeZeilen(_ sender: Any?) { aktiv.verbindeZeilen() }
    @objc func kommentar(_ sender: Any?) { aktiv.schalteKommentar(block: false) }
    @objc func blockkommentar(_ sender: Any?) { aktiv.schalteKommentar(block: true) }
    @objc func ueberschreiben(_ sender: Any?) { aktiv.schalteUeberschreiben() }

    @objc func sortiere(_ sender: NSMenuItem) {
        guard let wert = sender.representedObject as? String, let art = Zeilenwerkzeug.Sortierung(rawValue: wert) else { return }
        let (bereich, zeilen) = aktiv.zeilenFuerBefehl()
        aktiv.ersetzeZeilen(bereich, durch: Zeilenwerkzeug.sortiere(zeilen, art))
    }

    /// Die Befehle unter «Zeilen» und «Leerzeichen», nach tag.
    @objc func zeilenBefehl(_ sender: NSMenuItem) {
        let (bereich, zeilen) = aktiv.zeilenFuerBefehl()
        let breite = Einstellungen.tabbreite
        let neu: [String]
        switch sender.tag {
        case 1: neu = Zeilenwerkzeug.ohneDoppelte(zeilen)
        case 2: neu = Zeilenwerkzeug.ohneAufeinanderfolgendeDoppelte(zeilen)
        case 3: neu = Zeilenwerkzeug.ohneLeere(zeilen, auchNurLeerzeichen: false)
        case 4: neu = Zeilenwerkzeug.ohneLeere(zeilen, auchNurLeerzeichen: true)
        case 10: neu = Zeilenwerkzeug.kuerze(zeilen, .ende)
        case 11: neu = Zeilenwerkzeug.kuerze(zeilen, .anfang)
        case 12: neu = Zeilenwerkzeug.kuerze(zeilen, .beide)
        case 13: neu = Zeilenwerkzeug.tabsZuLeerzeichen(zeilen, breite: breite)
        case 14: neu = Zeilenwerkzeug.fuehrendeLeerzeichenZuTabs(zeilen, breite: breite)
        default: return
        }
        aktiv.ersetzeZeilen(bereich, durch: neu)
    }

    @objc func schreibung(_ sender: NSMenuItem) {
        guard let wert = sender.representedObject as? String, let art = Schreibung(rawValue: wert) else { return }
        aktiv.wandleAuswahl(art.wende(an:))
    }

    @objc func spalteneditor(_ sender: Any?) {
        guard let fenster = window else { return }
        Spalteneditor.zeige(in: fenster, editor: aktiv)
    }

    // MARK: Menü «Suchen»

    @objc func zeigeSuche(_ sender: Any?) { oeffneSuche(ersetzen: false) }
    @objc func zeigeErsetzen(_ sender: Any?) { oeffneSuche(ersetzen: true) }

    func oeffneSuche(ersetzen: Bool) {
        suchleiste.ersetzenSichtbar = ersetzen
        suchleiste.isHidden = false
        suchleiste.fokussiere()
    }

    func schliesseSuche() {
        suchleiste.isHidden = true
        aktiv.loescheMarkierungen(Editor.indikatorSuche)
        window?.makeFirstResponder(aktiv.ansicht.content())
    }

    @objc func weitersuchen(_ sender: Any?) { melde(Suchaktion.weiter(in: aktiv)) }
    @objc func rueckwaertsSuchen(_ sender: Any?) { melde(Suchaktion.weiter(in: aktiv, rueckwaerts: true)) }

    /// Wie ⌘E im Mac: die Auswahl wird zum Suchtext.
    @objc func auswahlSuchen(_ sender: Any?) {
        guard let text = aktiv.text(aktiv.auswahl), !text.isEmpty else { return NSSound.beep() }
        var o = SuchZustand.gemeinsam.optionen
        o.text = text
        o.modus = .normal
        SuchZustand.gemeinsam.optionen = o
    }

    @objc func markierungenEntfernen(_ sender: Any?) {
        aktiv.loescheMarkierungen(Editor.indikatorMarkiert)
        aktiv.loescheMarkierungen(Editor.indikatorSuche)
    }

    /// Antwort in der Leiste; ist sie zu, genügt bei «nicht gefunden» ein Ton.
    private func melde(_ antwort: Suchaktion.Antwort) {
        if suchleiste.isHidden {
            if antwort.fehler { NSSound.beep() }
        } else {
            suchleiste.zeige(antwort)
        }
    }

    @objc func geheZuZeile(_ sender: Any?) {
        guard let fenster = window else { return }
        let e = aktiv
        let frage = NSAlert()
        frage.messageText = "Gehe zu Zeile"
        frage.informativeText = "Zeile 1 bis \(e.zeilenanzahl), jetzt \(e.aktuelleZeile)"
        let feld = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        feld.placeholderString = "\(e.aktuelleZeile)"
        frage.accessoryView = feld
        frage.addButton(withTitle: "Gehe zu")
        frage.addButton(withTitle: "Abbrechen")
        frage.window.initialFirstResponder = feld
        frage.beginSheetModal(for: fenster) { antwort in
            guard antwort == .alertFirstButtonReturn,
                let zeile = Int(feld.stringValue.trimmingCharacters(in: .whitespaces))
            else { return }
            e.geheZuZeile(zeile)
            fenster.makeFirstResponder(e.ansicht.content())
        }
    }

    @objc func zurPassendenKlammer(_ sender: Any?) { aktiv.geheZurPassendenKlammer(auswaehlen: false) }
    @objc func bisZurPassendenKlammer(_ sender: Any?) { aktiv.geheZurPassendenKlammer(auswaehlen: true) }

    // MARK: Lesezeichen

    @objc func lesezeichenSchalten(_ sender: Any?) { aktiv.schalteLesezeichen() }
    @objc func naechstesLesezeichen(_ sender: Any?) { aktiv.springeZuLesezeichen(rueckwaerts: false) }
    @objc func vorherigesLesezeichen(_ sender: Any?) { aktiv.springeZuLesezeichen(rueckwaerts: true) }
    @objc func lesezeichenEntfernen(_ sender: Any?) { aktiv.lesezeichen = [] }
    @objc func lesezeichenUmkehren(_ sender: Any?) { aktiv.kehreLesezeichenUm() }
    @objc func lesezeichenZeilenLoeschen(_ sender: Any?) { aktiv.loescheZeilenMitLesezeichen() }
    @objc func zeilenOhneLesezeichenLoeschen(_ sender: Any?) { aktiv.loescheZeilenMitLesezeichen(ohne: true) }

    @objc func lesezeichenKopieren(_ sender: Any?) {
        let text = aktiv.lesezeichenText()
        guard !text.isEmpty else { return NSSound.beep() }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    @objc func lesezeichenAusschneiden(_ sender: Any?) {
        lesezeichenKopieren(sender)
        aktiv.loescheZeilenMitLesezeichen()
    }

    // MARK: Menü «Makro»

    @objc func makroAufnahme(_ sender: Any?) {
        let makros = Makros.gemeinsam
        if makros.nimmtAuf { makros.beende() } else { makros.starte(in: aktiv) }
    }

    /// Ohne Namen das zuletzt aufgenommene, sonst das gesicherte dieses Namens.
    @objc func makroAbspielen(_ sender: Any?) {
        let makros = Makros.gemeinsam
        if makros.nimmtAuf { makros.beende() }
        let name = (sender as? NSMenuItem)?.representedObject as? String
        let schritte = name.flatMap { n in makros.gesicherte.first { $0.name == n }?.schritte } ?? makros.aktuelles
        makros.spiele(schritte, in: aktiv)
    }

    @objc func makroSichern(_ sender: Any?) {
        let makros = Makros.gemeinsam
        if makros.nimmtAuf { makros.beende() }
        guard let fenster = window, !makros.aktuelles.isEmpty else { return NSSound.beep() }
        let frage = NSAlert()
        frage.messageText = "Aufgenommenes Makro sichern"
        frage.informativeText = "\(makros.aktuelles.count) Schritte. Unter diesem Namen steht es im Menü «Makro»."
        let feld = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        feld.placeholderString = "Name"
        frage.accessoryView = feld
        frage.addButton(withTitle: "Sichern")
        frage.addButton(withTitle: "Abbrechen")
        frage.window.initialFirstResponder = feld
        frage.beginSheetModal(for: fenster) { antwort in
            let name = feld.stringValue.trimmingCharacters(in: .whitespaces)
            guard antwort == .alertFirstButtonReturn, !name.isEmpty else { return }
            makros.sichere(name)
        }
    }

    /// «Run a Macro Multiple Times» von Notepad++: n-mal oder bis zum Ende der Datei.
    @objc func makroMehrfach(_ sender: Any?) {
        let makros = Makros.gemeinsam
        if makros.nimmtAuf { makros.beende() }
        guard let fenster = window else { return }
        let e = aktiv

        let auswahl = NSPopUpButton()
        auswahl.addItem(withTitle: "Zuletzt aufgenommenes Makro")
        for makro in makros.gesicherte { auswahl.addItem(withTitle: makro.name) }
        let nMal = NSButton(radioButtonWithTitle: "So oft:", target: nil, action: nil)
        let bisEnde = NSButton(radioButtonWithTitle: "Bis zum Ende der Datei", target: nil, action: nil)
        nMal.state = .on
        let anzahl = NSTextField(string: "1")
        anzahl.widthAnchor.constraint(equalToConstant: 60).isActive = true
        let zeileN = NSStackView(views: [nMal, anzahl])
        let stapel = NSStackView(views: [auswahl, zeileN, bisEnde])
        stapel.orientation = .vertical
        stapel.alignment = .leading
        stapel.frame = NSRect(x: 0, y: 0, width: 300, height: 90)
        // Radioknöpfe in verschiedenen Zeilen schliessen sich nicht von selbst aus.
        let umschalten = RadioGruppe([nMal, bisEnde])
        nMal.target = umschalten
        bisEnde.target = umschalten
        nMal.action = #selector(RadioGruppe.gewaehlt(_:))
        bisEnde.action = #selector(RadioGruppe.gewaehlt(_:))

        let frage = NSAlert()
        frage.messageText = "Makro mehrfach abspielen"
        frage.accessoryView = stapel
        frage.addButton(withTitle: "Abspielen")
        frage.addButton(withTitle: "Abbrechen")
        frage.beginSheetModal(for: fenster) { antwort in
            _ = umschalten
            guard antwort == .alertFirstButtonReturn else { return }
            let schritte = auswahl.indexOfSelectedItem == 0
                ? makros.aktuelles : makros.gesicherte[auswahl.indexOfSelectedItem - 1].schritte
            if bisEnde.state == .on {
                makros.spieleBisEnde(schritte, in: e)
            } else {
                makros.spiele(schritte, in: e, mal: max(1, min(anzahl.integerValue, 100_000)))
            }
        }
    }

    // MARK: Prüfen

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(zeilenumbruchUmschalten(_:)):
            menuItem.state = editor.umbruch ? .on : .off
        case #selector(ueberschreiben(_:)):
            menuItem.state = aktiv.stand.ueberschreiben ? .on : .off
        case #selector(funktionslisteUmschalten(_:)):
            menuItem.state = Einstellungen.funktionslisteSichtbar ? .on : .off
        case #selector(geteilteAnsicht(_:)):
            menuItem.state = menuItem.tag == geteilt ? .on : .off
        case #selector(weitersuchen(_:)), #selector(rueckwaertsSuchen(_:)):
            return !SuchZustand.gemeinsam.optionen.text.isEmpty
        case #selector(makroAbspielen(_:)):
            return (menuItem.representedObject != nil) || !Makros.gemeinsam.aktuelles.isEmpty || Makros.gemeinsam.nimmtAuf
        case #selector(makroSichern(_:)):
            return !Makros.gemeinsam.aktuelles.isEmpty || Makros.gemeinsam.nimmtAuf
        case #selector(makroAufnahme(_:)):
            menuItem.title = Makros.gemeinsam.nimmtAuf ? "Aufnahme beenden" : "Aufnahme starten"
        default:
            break
        }
        return true
    }
}

/// Radioknöpfe, die nicht im selben Elternelement liegen, schliessen sich nicht
/// selbst aus; diese Gruppe tut es.
final class RadioGruppe: NSObject {
    private let knoepfe: [NSButton]
    init(_ knoepfe: [NSButton]) { self.knoepfe = knoepfe }
    @objc func gewaehlt(_ sender: NSButton) {
        for k in knoepfe { k.state = k === sender ? .on : .off }
    }
}
