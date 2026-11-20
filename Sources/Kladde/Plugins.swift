import AppKit
import ScintillaBruecke

/// Das Menü «Plugins» mit den Werkzeugen, die man in Notepad++ als Plugins
/// nachinstalliert: JSON Viewer, XML Tools, MIME Tools und Converter. Hier
/// eingebaut und neu geschrieben (KladdeKern/Formatierer.swift). Die Menüs
/// heissen wie bei den Plugins, auch auf Englisch, damit man sie wiederfindet.
/// Jeder Befehl wirkt auf die Auswahl, ohne Auswahl auf das ganze Dokument;
/// Rückgängig nimmt ihn in einem Schritt zurück.
final class Plugins: NSObject, NSMenuItemValidation {
    static let gemeinsam = Plugins()

    struct Befehl {
        let id: String
        let titel: String
        let kuerzel: (String, NSEvent.ModifierFlags)?
        let beschreibung: String
    }

    /// Plugin, seine Befehle (nil: Trenner).
    static let gruppen: [(String, [Befehl?])] = [
        ("JSON Viewer", [
            Befehl(id: "json.viewer", titel: "Show JSON Viewer", kuerzel: ("j", [.command, .option, .shift]),
                   beschreibung: "Zeigt das JSON rechts als Baum mit Schlüsseln und Werten; ein Klick springt zur Stelle."),
            Befehl(id: "json.format", titel: "Format JSON", kuerzel: ("m", [.command, .option, .shift]),
                   beschreibung: "Rückt das JSON ein, ein Wert je Zeile. Reihenfolge, Zahlen und Texte bleiben genau wie sie sind."),
            Befehl(id: "json.compress", titel: "Compress JSON", kuerzel: ("c", [.command, .option, .shift]),
                   beschreibung: "Schreibt das JSON in eine Zeile ohne Leerraum."),
            nil,
            Befehl(id: "json.validate", titel: "Validate JSON", kuerzel: nil,
                   beschreibung: "Prüft das JSON und springt bei einem Fehler an die Stelle."),
        ]),
        ("XML Tools", [
            Befehl(id: "xml.pretty", titel: "Pretty print", kuerzel: ("b", [.command, .option, .shift]),
                   beschreibung: "Rückt das XML ein, ein Element je Zeile; Text zwischen Start- und End-Tag bleibt in der Zeile."),
            Befehl(id: "xml.linearize", titel: "Linarize XML", kuerzel: ("l", [.command, .option, .shift]),
                   beschreibung: "Schreibt das XML in eine Zeile, ohne Leerraum zwischen den Tags."),
            nil,
            Befehl(id: "xml.check", titel: "Check XML syntax now", kuerzel: ("x", [.command, .option, .shift]),
                   beschreibung: "Prüft, ob das XML wohlgeformt ist, und springt bei einem Fehler an die Stelle."),
        ]),
        ("MIME Tools", [
            Befehl(id: "mime.base64", titel: "Base64 Encode", kuerzel: nil, beschreibung: "Kodiert die Auswahl (UTF-8) als Base64."),
            Befehl(id: "mime.unbase64", titel: "Base64 Decode", kuerzel: nil,
                   beschreibung: "Dekodiert Base64 (auch die URL-Variante mit - und _) zu Text."),
            nil,
            Befehl(id: "mime.url", titel: "URL Encode", kuerzel: nil,
                   beschreibung: "Prozent-kodiert alles ausser Buchstaben, Ziffern und «-._~»."),
            Befehl(id: "mime.unurl", titel: "URL Decode", kuerzel: nil, beschreibung: "Macht aus %20 und + wieder Zeichen."),
        ]),
        ("Converter", [
            Befehl(id: "conv.hex", titel: "ASCII -> HEX", kuerzel: nil, beschreibung: "Schreibt jedes Byte (UTF-8) als zwei Hex-Ziffern."),
            Befehl(id: "conv.unhex", titel: "HEX -> ASCII", kuerzel: nil,
                   beschreibung: "Macht aus Hex-Ziffern wieder Text; Leerraum dazwischen ist erlaubt."),
        ]),
    ]

    /// Die Untermenüs für den Anfang des Menüs «Plugins».
    func menueEintraege() -> [NSMenuItem] {
        Self.gruppen.map { name, befehle in
            let kopf = NSMenuItem(title: name, action: nil, keyEquivalent: "")
            let m = NSMenu(title: name)
            for b in befehle {
                guard let b else { m.addItem(.separator()); continue }
                let i = NSMenuItem(title: b.titel, action: #selector(gewaehlt(_:)), keyEquivalent: b.kuerzel?.0 ?? "")
                if let k = b.kuerzel { i.keyEquivalentModifierMask = k.1 }
                i.target = self
                i.representedObject = b.id
                i.toolTip = b.beschreibung
                m.addItem(i)
            }
            kopf.submenu = m
            return kopf
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let id = menuItem.representedObject as? String, let e = Hauptfenster.gemeinsam.aktiv else { return false }
        if id == "json.viewer" {
            menuItem.state = Einstellungen.jsonViewerSichtbar ? .on : .off
            return true
        }
        let pruefen = id == "json.validate" || id == "xml.check"
        return pruefen || !(Hauptfenster.gemeinsam.aktivesDokument?.schreibgeschuetzt ?? false) && e.laenge > 0
    }

    @objc func gewaehlt(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        fuehreAus(id)
    }

    // MARK: Ausführen

    /// Der Bereich, auf den ein Befehl wirkt: die Auswahl, sonst alles.
    private func bereich(_ e: Editor) -> Range<Int> {
        let a = e.auswahl
        return a.isEmpty ? 0..<e.laenge : a
    }

    private var einzug: String {
        Einstellungen.tabsAlsLeerzeichen ? String(repeating: " ", count: Einstellungen.tabbreite) : "\t"
    }

    func fuehreAus(_ id: String) {
        let h = Hauptfenster.gemeinsam
        if id == "json.viewer" {
            Einstellungen.jsonViewerSichtbar.toggle()
            return
        }
        guard let e = h.aktiv else { return }
        let b = bereich(e)
        let text = e.text(b) ?? ""
        let ganz = b == 0..<e.laenge
        switch id {
        case "json.format", "json.compress", "json.validate":
            do {
                if id == "json.validate" {
                    _ = try JSONWerkzeug.lies(text)
                    h.melde(Suchaktion.Antwort(text: "JSON ist gültig"))
                    return
                }
                let neu = id == "json.format" ? try JSONWerkzeug.formatiere(text, einzug: einzug) : try JSONWerkzeug.komprimiere(text)
                ersetze(e, b, neu, ganz: ganz)
                if ganz, h.aktivesDokument?.gewaehlteSprache == nil, !e.sprache.name.hasPrefix("json"),
                   let json = Sprachdaten.gemeinsam.sprache("json") {
                    // Wie der JSON Viewer: Das Dokument wird als JSON gefärbt.
                    h.aktivesDokument?.gewaehlteSprache = "json"
                    e.setzeSprache(json)
                }
            } catch let f as Formatfehler {
                zeigeFehler(e, b, f, titel: "Ungültiges JSON")
            } catch {}
        case "xml.check":
            if let f = XMLWerkzeug.pruefe(text) { zeigeFehler(e, b, f, titel: "XML ist nicht wohlgeformt") }
            else { h.melde(Suchaktion.Antwort(text: "XML Tools: Kein Fehler gefunden")) }
        case "xml.pretty": ersetze(e, b, XMLWerkzeug.formatiere(text, einzug: einzug), ganz: ganz)
        case "xml.linearize": ersetze(e, b, XMLWerkzeug.linearisiere(text), ganz: ganz)
        case "mime.base64": ersetze(e, b, Kodierwerkzeug.base64(text), ganz: ganz)
        case "mime.unbase64": ersetzeOderMelde(e, b, Kodierwerkzeug.ausBase64(text), "Kein gültiges Base64", ganz: ganz)
        case "mime.url": ersetze(e, b, Kodierwerkzeug.url(text), ganz: ganz)
        case "mime.unurl": ersetzeOderMelde(e, b, Kodierwerkzeug.ausURL(text), "Keine gültige URL-Kodierung", ganz: ganz)
        case "conv.hex": ersetze(e, b, Kodierwerkzeug.hex(text), ganz: ganz)
        case "conv.unhex": ersetzeOderMelde(e, b, Kodierwerkzeug.ausHex(text), "Keine gültigen Hex-Ziffern", ganz: ganz)
        default: break
        }
    }

    private func ersetze(_ e: Editor, _ b: Range<Int>, _ neu: String, ganz: Bool) {
        guard e.text(b) != neu else { return }
        e.ersetze([(b, neu)])
        // Eine Auswahl bleibt ausgewählt, damit man gleich weiterarbeiten kann.
        if !ganz { e.waehleAus(b.lowerBound..<b.lowerBound + neu.utf8.count) } else { e.waehleAus(0..<0) }
        if Einstellungen.jsonViewerSichtbar { JSONAnsicht.gemeinsam.aktualisiere() }
    }

    private func ersetzeOderMelde(_ e: Editor, _ b: Range<Int>, _ neu: String?, _ meldung: String, ganz: Bool) {
        if let neu { ersetze(e, b, neu, ganz: ganz) } else { Hauptfenster.gemeinsam.melde(Suchaktion.Antwort(text: meldung, fehler: true)) }
    }

    /// Wie die Plugins: eine Meldung, danach steht die Marke an der Fehlerstelle.
    private func zeigeFehler(_ e: Editor, _ b: Range<Int>, _ f: Formatfehler, titel: String) {
        let stelle = Self.stelle(in: e.text(b) ?? "", zeile: f.zeile, spalte: f.spalte) + b.lowerBound
        e.waehleAus(stelle..<stelle)
        e.nachricht(SCI_SCROLLCARET)
        Hauptfenster.gemeinsam.melde(Suchaktion.Antwort(text: "\(titel): \(f.text)", fehler: true))
        guard let fenster = Hauptfenster.gemeinsam.window else { return }
        let a = NSAlert()
        a.messageText = titel
        a.informativeText = f.text
        a.alertStyle = .warning
        a.beginSheetModal(for: fenster)
    }

    /// Byte-Stelle zu Zeile und Spalte (Zeichen) in einem Text.
    static func stelle(in text: String, zeile: Int, spalte: Int) -> Int {
        var bytes = 0
        for (n, z) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            if n + 1 == zeile { return bytes + String(z.prefix(max(0, spalte - 1))).utf8.count }
            bytes += z.utf8.count + 1
        }
        return text.utf8.count
    }
}

/// Die Leiste «JSON Viewer»: das JSON des Dokuments als Baum, Schlüssel und
/// Wert je Zeile. Ein Klick wählt den Pfad aus und zeigt ihn unten an.
final class JSONAnsicht: NSView, NSOutlineViewDataSource, NSOutlineViewDelegate {
    static let gemeinsam = JSONAnsicht()

    final class Knoten {
        let schluessel: String
        let wert: JSONWert
        let pfad: String
        lazy var kinder: [Knoten] = {
            switch wert {
            case .objekt(let e): return e.map { Knoten(schluessel: $0.0, wert: $0.1, pfad: pfad + (Self.einfach($0.0) ? ".\($0.0)" : "[\"\($0.0)\"]")) }
            case .liste(let e): return e.enumerated().map { Knoten(schluessel: "[\($0.offset)]", wert: $0.element, pfad: pfad + "[\($0.offset)]") }
            default: return []
            }
        }()
        init(schluessel: String, wert: JSONWert, pfad: String) {
            self.schluessel = schluessel
            self.wert = wert
            self.pfad = pfad
        }
        static func einfach(_ s: String) -> Bool { !s.isEmpty && s.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" } }
    }

    private let liste = NSOutlineView()
    private let pfad = NSTextField(labelWithString: "")
    private let hinweis = NSTextField(wrappingLabelWithString: "")
    private var wurzel: Knoten?

    private override init(frame: NSRect) {
        super.init(frame: frame)
        for (id, titel, breite) in [("k", "Schlüssel", 110.0), ("w", "Wert", 120.0)] {
            let s = NSTableColumn(identifier: .init(id))
            s.title = titel
            s.width = breite
            liste.addTableColumn(s)
        }
        liste.outlineTableColumn = liste.tableColumns[0]
        liste.rowSizeStyle = .small
        liste.usesAlternatingRowBackgroundColors = true
        liste.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        liste.dataSource = self
        liste.delegate = self
        liste.target = self
        liste.action = #selector(geklickt)
        let rollen = NSScrollView()
        rollen.documentView = liste
        rollen.hasVerticalScroller = true
        rollen.hasHorizontalScroller = true
        rollen.autohidesScrollers = true

        let neu = NSButton(image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Aktualisieren") ?? NSImage(),
                           target: self, action: #selector(aktualisiere))
        neu.isBordered = false
        neu.toolTip = "Aus dem Dokument neu lesen"
        let format = NSButton(title: "Format", target: self, action: #selector(formatieren))
        format.controlSize = .small
        format.bezelStyle = .rounded
        format.toolTip = "Format JSON"
        let kopf = NSStackView(views: [neu, format, NSView()])
        pfad.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        pfad.lineBreakMode = .byTruncatingMiddle
        pfad.isSelectable = true
        hinweis.textColor = .secondaryLabelColor
        hinweis.font = .systemFont(ofSize: 11)
        let stapel = NSStackView(views: [kopf, hinweis, rollen, pfad])
        stapel.orientation = .vertical
        stapel.alignment = .leading
        stapel.spacing = 4
        stapel.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        stapel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stapel)
        for v in [kopf, hinweis, rollen, pfad] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            v.widthAnchor.constraint(equalTo: stapel.widthAnchor, constant: -12).isActive = true
        }
        rollen.setContentHuggingPriority(.init(1), for: .vertical)
        NSLayoutConstraint.activate([
            stapel.topAnchor.constraint(equalTo: topAnchor), stapel.bottomAnchor.constraint(equalTo: bottomAnchor),
            stapel.leadingAnchor.constraint(equalTo: leadingAnchor), stapel.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    @objc private func formatieren() { Plugins.gemeinsam.fuehreAus("json.format") }

    /// Liest das Dokument (oder die Auswahl) neu.
    @objc func aktualisiere() {
        guard let e = Hauptfenster.gemeinsam.aktiv else { return zeige(nil, "Kein Dokument offen.") }
        let a = e.auswahl
        let text = e.text(a.isEmpty ? 0..<e.laenge : a) ?? ""
        do {
            zeige(Knoten(schluessel: "JSON", wert: try JSONWerkzeug.lies(text), pfad: "$"), nil)
        } catch let f as Formatfehler {
            zeige(nil, "Kein gültiges JSON: \(f.text)")
        } catch {}
    }

    private func zeige(_ k: Knoten?, _ meldung: String?) {
        wurzel = k
        hinweis.stringValue = meldung ?? ""
        hinweis.isHidden = meldung == nil
        pfad.stringValue = ""
        liste.reloadData()
        if let k { liste.expandItem(k); k.kinder.prefix(50).forEach { liste.expandItem($0) } }
    }

    var anzahlZeilen: Int { liste.numberOfRows }

    @objc private func geklickt() {
        guard let k = liste.item(atRow: liste.clickedRow) as? Knoten else { return }
        pfad.stringValue = k.pfad
    }

    func outlineView(_ o: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? Knoten)?.kinder.count ?? (wurzel == nil ? 0 : 1)
    }

    func outlineView(_ o: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? Knoten)?.kinder[index] ?? wurzel!
    }

    func outlineView(_ o: NSOutlineView, isItemExpandable item: Any) -> Bool { !((item as? Knoten)?.kinder.isEmpty ?? true) }

    func outlineView(_ o: NSOutlineView, viewFor spalte: NSTableColumn?, item: Any) -> NSView? {
        guard let k = item as? Knoten else { return nil }
        let istSchluessel = spalte?.identifier.rawValue == "k"
        let t = NSTextField(labelWithString: istSchluessel ? k.schluessel : k.wert.kurz)
        t.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        t.lineBreakMode = .byTruncatingTail
        if !istSchluessel {
            switch k.wert {
            case .text: t.textColor = NSColor(rgb: Hauptfenster.istDunkel ? 0xCE9178 : 0x808080)
            case .zahl: t.textColor = NSColor(rgb: Hauptfenster.istDunkel ? 0xB5CEA8 : 0xFF8000)
            case .wahr, .falsch, .null: t.textColor = NSColor(rgb: Hauptfenster.istDunkel ? 0x569CD6 : 0x0000FF)
            default: t.textColor = .secondaryLabelColor
            }
        }
        return t
    }
}
