import AppKit

/// Das Fenster eines Dokuments. Mehrere Dokumente landen als Tabs im selben
/// Fenster (tabbingMode), die Tableiste zeichnet macOS. Oben sitzt bei Bedarf
/// die Suchleiste.
final class EditorFenster: NSWindowController, NSMenuItemValidation {
    let editor: Editor
    private let suchleiste: Suchleiste
    private var erscheinung: NSKeyValueObservation?

    init(editor: Editor) {
        self.editor = editor
        suchleiste = Suchleiste(editor: editor)
        let fenster = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false)
        fenster.tabbingMode = .preferred
        fenster.tabbingIdentifier = "Kladde"
        fenster.minSize = NSSize(width: 480, height: 200)

        let stapel = NSStackView(views: [suchleiste, editor.ansicht])
        stapel.orientation = .vertical
        stapel.spacing = 0
        stapel.alignment = .leading
        stapel.distribution = .fill
        for ansicht in [suchleiste, editor.ansicht] as [NSView] {
            ansicht.translatesAutoresizingMaskIntoConstraints = false
            ansicht.widthAnchor.constraint(equalTo: stapel.widthAnchor).isActive = true
        }
        editor.ansicht.setContentHuggingPriority(.init(1), for: .vertical)
        editor.ansicht.setContentCompressionResistancePriority(.init(1), for: .vertical)
        suchleiste.isHidden = true
        fenster.contentView = stapel

        fenster.center()
        fenster.setFrameAutosaveName("Editor")
        // Was beim Start wieder aufgeht, bestimmt die eigene Sitzung (Sitzung.swift);
        // die Wiederherstellung von macOS würde Dateien doppelt öffnen.
        fenster.isRestorable = false
        super.init(window: fenster)
        fenster.makeFirstResponder(editor.ansicht.content())

        suchleiste.schliessen = { [weak self] in self?.schliesseSuche() }

        // Wechselt macOS zwischen hell und dunkel, wechselt der Editor mit.
        erscheinung = NSApp.observe(\.effectiveAppearance) { [weak editor] _, _ in
            DispatchQueue.main.async { editor?.wendeDarstellungAn() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("EditorFenster entsteht nur im Code") }

    // MARK: Menü «Darstellung»

    @objc func zeilenumbruchUmschalten(_ sender: Any?) { editor.umbruch.toggle() }
    @objc func schriftGroesser(_ sender: Any?) { editor.vergroessere() }
    @objc func schriftKleiner(_ sender: Any?) { editor.verkleinere() }
    @objc func schriftOriginal(_ sender: Any?) { editor.originalgroesse() }
    @objc func allesEinklappen(_ sender: Any?) { editor.klappeAlles(ein: true) }
    @objc func allesAusklappen(_ sender: Any?) { editor.klappeAlles(ein: false) }

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
        editor.loescheMarkierungen(Editor.indikatorSuche)
        window?.makeFirstResponder(editor.ansicht.content())
    }

    @objc func weitersuchen(_ sender: Any?) { melde(Suchaktion.weiter(in: editor)) }
    @objc func rueckwaertsSuchen(_ sender: Any?) { melde(Suchaktion.weiter(in: editor, rueckwaerts: true)) }

    /// Wie ⌘E im Mac: die Auswahl wird zum Suchtext.
    @objc func auswahlSuchen(_ sender: Any?) {
        guard let text = editor.text(editor.auswahl), !text.isEmpty else { return NSSound.beep() }
        var o = SuchZustand.gemeinsam.optionen
        o.text = text
        o.modus = .normal
        SuchZustand.gemeinsam.optionen = o
    }

    @objc func markierungenEntfernen(_ sender: Any?) {
        editor.loescheMarkierungen(Editor.indikatorMarkiert)
        editor.loescheMarkierungen(Editor.indikatorSuche)
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
        let frage = NSAlert()
        frage.messageText = "Gehe zu Zeile"
        frage.informativeText = "Zeile 1 bis \(editor.zeilenanzahl), jetzt \(editor.aktuelleZeile)"
        let feld = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        feld.placeholderString = "\(editor.aktuelleZeile)"
        frage.accessoryView = feld
        frage.addButton(withTitle: "Gehe zu")
        frage.addButton(withTitle: "Abbrechen")
        frage.window.initialFirstResponder = feld
        frage.beginSheetModal(for: fenster) { [weak self] antwort in
            guard let self, antwort == .alertFirstButtonReturn,
                let zeile = Int(feld.stringValue.trimmingCharacters(in: .whitespaces))
            else { return }
            self.editor.geheZuZeile(zeile)
            fenster.makeFirstResponder(self.editor.ansicht.content())
        }
    }

    @objc func zurPassendenKlammer(_ sender: Any?) { editor.geheZurPassendenKlammer(auswaehlen: false) }
    @objc func bisZurPassendenKlammer(_ sender: Any?) { editor.geheZurPassendenKlammer(auswaehlen: true) }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(zeilenumbruchUmschalten(_:)) {
            menuItem.state = editor.umbruch ? .on : .off
        }
        if menuItem.action == #selector(weitersuchen(_:)) || menuItem.action == #selector(rueckwaertsSuchen(_:)) {
            return !SuchZustand.gemeinsam.optionen.text.isEmpty
        }
        return true
    }
}
