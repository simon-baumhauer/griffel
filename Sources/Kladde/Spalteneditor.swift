import AppKit

/// Der Dialog «Spalteneditor» wie «Edit → Column Editor» in Notepad++: fügt
/// in jede Zeile denselben Text oder eine Zahlenfolge ein, in derselben Spalte.
/// Mit Rechteckauswahl (⌥ + Ziehen) in deren Zeilen, sonst ab der Zeile der
/// Einfügemarke bis zum Ende.
enum Spalteneditor {
    private static let ablage = UserDefaults.standard

    static func zeige(in fenster: NSWindow, editor: Editor) {
        let alsText = NSButton(radioButtonWithTitle: "Text einfügen:", target: nil, action: nil)
        let alsZahl = NSButton(radioButtonWithTitle: "Zahlen einfügen:", target: nil, action: nil)
        let gruppe = RadioGruppe([alsText, alsZahl])
        for k in [alsText, alsZahl] {
            k.target = gruppe
            k.action = #selector(RadioGruppe.gewaehlt(_:))
        }
        let zahlenGewaehlt = ablage.bool(forKey: "SpalteZahlen")
        alsText.state = zahlenGewaehlt ? .off : .on
        alsZahl.state = zahlenGewaehlt ? .on : .off

        let text = NSTextField(string: ablage.string(forKey: "SpalteText") ?? "")
        text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        let anfang = zahlfeld("SpalteAnfang", 1)
        let schritt = zahlfeld("SpalteSchritt", 1)
        let wiederholen = zahlfeld("SpalteWiederholen", 1)
        let fuehrend = NSPopUpButton()
        fuehrend.addItems(withTitles: ["Keine", "Nullen", "Leerzeichen"])
        fuehrend.selectItem(at: ablage.integer(forKey: "SpalteFuehrend"))
        let format = NSPopUpButton()
        format.addItems(withTitles: ["Dezimal", "Hexadezimal", "Oktal", "Binär"])
        format.selectItem(at: ablage.integer(forKey: "SpalteFormat"))

        func beschriftung(_ t: String) -> NSTextField {
            let f = NSTextField(labelWithString: t)
            f.alignment = .right
            return f
        }
        let raster = NSGridView(views: [
            [alsText, text],
            [alsZahl, NSGridCell.emptyContentView],
            [beschriftung("Anfang:"), anfang],
            [beschriftung("Schritt:"), schritt],
            [beschriftung("Jede Zahl so oft:"), wiederholen],
            [beschriftung("Auffüllen mit:"), fuehrend],
            [beschriftung("Format:"), format],
        ])
        raster.rowSpacing = 6
        raster.columnSpacing = 8
        raster.rowAlignment = .firstBaseline
        raster.column(at: 1).width = 200
        raster.frame = NSRect(origin: .zero, size: raster.fittingSize)

        let frage = NSAlert()
        frage.messageText = "Spalteneditor"
        frage.informativeText = "Fügt in jede Zeile ab der Einfügemarke ein, in derselben Spalte. Mit Rechteckauswahl (⌥ + Ziehen) nur in deren Zeilen."
        frage.accessoryView = raster
        frage.addButton(withTitle: "Einfügen")
        frage.addButton(withTitle: "Abbrechen")
        frage.window.initialFirstResponder = zahlenGewaehlt ? anfang : text
        frage.beginSheetModal(for: fenster) { antwort in
            _ = gruppe
            guard antwort == .alertFirstButtonReturn else { return }
            let zahlen = alsZahl.state == .on
            ablage.set(zahlen, forKey: "SpalteZahlen")
            ablage.set(text.stringValue, forKey: "SpalteText")
            ablage.set(anfang.integerValue, forKey: "SpalteAnfang")
            ablage.set(schritt.integerValue, forKey: "SpalteSchritt")
            ablage.set(wiederholen.integerValue, forKey: "SpalteWiederholen")
            ablage.set(fuehrend.indexOfSelectedItem, forKey: "SpalteFuehrend")
            ablage.set(format.indexOfSelectedItem, forKey: "SpalteFormat")

            if zahlen {
                var folge = Zahlenfolge()
                folge.anfang = anfang.integerValue
                folge.schritt = schritt.integerValue
                folge.wiederholen = max(1, wiederholen.integerValue)
                folge.fuehrend = Zahlenfolge.Fuehrend(rawValue: fuehrend.indexOfSelectedItem) ?? .keine
                folge.basis = [10, 16, 8, 2][max(0, format.indexOfSelectedItem)]
                _ = editor.fuegeInSpalteEin { folge.texte($0) }
            } else {
                let t = text.stringValue
                guard !t.isEmpty else { return }
                _ = editor.fuegeInSpalteEin { Array(repeating: t, count: $0) }
            }
            fenster.makeFirstResponder(editor.ansicht.content())
        }
    }

    private static func zahlfeld(_ schluessel: String, _ vorgabe: Int) -> NSTextField {
        let wert = ablage.object(forKey: schluessel) as? Int ?? vorgabe
        let feld = NSTextField(string: "\(wert)")
        let format = NumberFormatter()
        format.allowsFloats = false
        feld.formatter = format
        feld.widthAnchor.constraint(equalToConstant: 80).isActive = true
        return feld
    }
}
